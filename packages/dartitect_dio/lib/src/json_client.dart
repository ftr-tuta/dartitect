import 'dart:async';
import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect/dartitect_credentials.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart';

import 'cancellation_binding.dart';
import 'credentials_interceptor.dart';
import 'instrumentation.dart';
import 'result_mapping.dart';
import 'retry_after.dart';
import 'route_template.dart';

/// Cancellation contract accepted by typed JSON execution.
typedef CancellationToken = CancellationSignal;

/// Decodes one payload for an explicitly declared response status.
typedef DioStatusDecoder<T> = T Function(Object? json);

/// Per-attempt transport context propagated into Dio execution.
final class DioRequestContext {
  /// Creates a bounded request context without headers or credential values.
  DioRequestContext({
    this.cancellation,
    this.deadline,
    this.traceParent,
    this.credentialGeneration,
  }) {
    if (deadline != null && !deadline!.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
  }

  /// Borrowed cooperative cancellation signal.
  final CancellationSignal? cancellation;

  /// Optional absolute UTC transport deadline.
  final DateTime? deadline;

  /// Validated parent trace identity used by installed instrumentation.
  final TraceContext? traceParent;

  /// Exact credential generation expected by an installed interceptor.
  final CredentialGeneration? credentialGeneration;
}

/// One validated, explicitly declared JSON endpoint.
final class DioEndpoint<T> {
  /// Creates an endpoint for one supported HTTP method.
  DioEndpoint({
    required String method,
    required this.route,
    this.decode,
    Map<int, DioStatusDecoder<T>>? statusDecoders,
    required Set<int> acceptedStatusCodes,
  }) : method = method.toUpperCase(),
       statusDecoders = Map<int, DioStatusDecoder<T>>.unmodifiable(
         statusDecoders ?? <int, DioStatusDecoder<T>>{},
       ),
       acceptedStatusCodes = Set<int>.unmodifiable(acceptedStatusCodes) {
    if (!const <String>{
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
    }.contains(this.method)) {
      throw ArgumentError.value(method, 'method', 'is not supported');
    }
    if (acceptedStatusCodes.isEmpty ||
        acceptedStatusCodes.any((status) => status < 100 || status > 599)) {
      throw ArgumentError.value(
        acceptedStatusCodes,
        'acceptedStatusCodes',
        'must contain valid HTTP status codes',
      );
    }
    if (decode == null &&
        !acceptedStatusCodes.every(this.statusDecoders.containsKey)) {
      throw ArgumentError(
        'Every accepted status requires a decoder when decode is omitted.',
      );
    }
    if (this.statusDecoders.keys.any(
      (status) => !acceptedStatusCodes.contains(status),
    )) {
      throw ArgumentError.value(
        this.statusDecoders.keys,
        'statusDecoders',
        'May contain only accepted status codes.',
      );
    }
  }

  /// Uppercase GET, POST, PUT, PATCH, or DELETE.
  final String method;

  /// Static validated route with named dynamic segments.
  final RouteTemplate route;

  /// Consumer-owned JSON-to-value decoder.
  final DioStatusDecoder<T>? decode;

  /// Status-specific decoders used for declared OpenAPI response unions.
  final Map<int, DioStatusDecoder<T>> statusDecoders;

  /// Status codes considered successful for this endpoint.
  final Set<int> acceptedStatusCodes;
}

/// Typed payload paired only with its non-sensitive HTTP status.
final class DioResponse<T> {
  /// Creates an accepted response.
  const DioResponse({required this.payload, required this.statusCode});

  /// Decoded consumer value.
  final T payload;

  /// Accepted HTTP response status.
  final int statusCode;
}

/// Provider-neutral typed JSON execution boundary implemented with Dio.
abstract interface class DioJsonClient {
  /// Executes [endpoint] without retaining headers, body, query, or payload in
  /// failures or telemetry.
  Future<Result<DioResponse<T>, DioFailure>> execute<T>(
    DioEndpoint<T> endpoint, {
    Map<String, Object?> query = const <String, Object?>{},
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, Object?> headers = const <String, Object?>{},
    Object? jsonBody,
    CancellationToken? cancellation,
    DioRequestContext? context,
  });
}

/// Borrowed-Dio implementation of [DioJsonClient].
///
/// The caller owns and closes [dio] after all requests and instrumentation.
final class DefaultDioJsonClient implements DioJsonClient {
  /// Creates a typed executor over a borrowed [dio].
  const DefaultDioJsonClient(this.dio, {this.retryAfter});

  /// Borrowed provider client.
  final Dio dio;

  /// Optional metadata extraction; transport execution never retries itself.
  final DioRetryAfterPolicy? retryAfter;

  @override
  Future<Result<DioResponse<T>, DioFailure>> execute<T>(
    DioEndpoint<T> endpoint, {
    Map<String, Object?> query = const <String, Object?>{},
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, Object?> headers = const <String, Object?>{},
    Object? jsonBody,
    CancellationToken? cancellation,
    DioRequestContext? context,
  }) async {
    if (cancellation != null && context?.cancellation != null) {
      throw ArgumentError(
        'Supply cancellation directly or through context, not both.',
      );
    }
    final resolved = _resolveRoute(endpoint.route, pathParameters);
    if (resolved case Err<DioFailure>(:final failure, :final stackTrace)) {
      return Err<DioFailure>(failure, stackTrace);
    }
    final path = (resolved as Ok<String>).value;
    final requestCancellation = _DioRequestCancellation(
      cancellation: context?.cancellation ?? cancellation,
      deadline: context?.deadline,
    );
    if (requestCancellation.deadlineExceeded) {
      requestCancellation.dispose();
      return Err<DioFailure>(
        DioDeadlineExceededFailure(deadline: context!.deadline!),
        StackTrace.current,
      );
    }
    try {
      final captured = await captureDioException<Response<String>>(
        () => dio.request<String>(
          path,
          data: jsonBody,
          queryParameters: query,
          cancelToken: requestCancellation.token,
          options: Options(
            method: endpoint.method,
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
            headers: headers,
            extra: <String, Object?>{
              if (context?.traceParent case final parent?)
                DioInstrumentation.parentTraceContextExtraKey: parent,
              if (context?.credentialGeneration case final generation?)
                DioCredentialsInterceptor.credentialGenerationExtraKey:
                    generation,
            },
          ),
        ),
        retryAfter: retryAfter,
      );
      switch (captured) {
        case Err<Object>(:final failure, :final stackTrace):
          if (requestCancellation.deadlineExceeded) {
            return Err<DioFailure>(
              DioDeadlineExceededFailure(deadline: context!.deadline!),
              stackTrace,
            );
          }
          return Err<DioFailure>(failure as DioFailure, stackTrace);
        case Ok<dynamic>(:final value):
          final response = value as Response<String>;
          final status = response.statusCode;
          if (status == null ||
              !endpoint.acceptedStatusCodes.contains(status)) {
            return Err<DioFailure>(
              DioHttpFailure(
                statusCode: status,
                retryAfter: retryAfter?.extract(response.headers),
              ),
              StackTrace.current,
            );
          }
          try {
            final decoder = endpoint.statusDecoders[status] ?? endpoint.decode!;
            return Ok<DioResponse<T>>(
              DioResponse<T>(
                payload: decoder(
                  response.data == null || response.data!.isEmpty
                      ? null
                      : jsonDecode(response.data!),
                ),
                statusCode: status,
              ),
            );
          } on Object catch (error, stackTrace) {
            return Err<DioFailure>(
              DioDecodingFailure(causeType: error.runtimeType.toString()),
              stackTrace,
            );
          }
      }
    } finally {
      requestCancellation.dispose();
    }
  }
}

final class _DioRequestCancellation implements Disposable {
  _DioRequestCancellation({
    required CancellationSignal? cancellation,
    required DateTime? deadline,
  }) {
    if (cancellation == null && deadline == null) return;
    _source = CancellationSource();
    _binding = DioCancellationBinding(_source!.signal);
    _registration = cancellation?.register(_source!.cancel);
    if (deadline != null) {
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) {
        _deadlineExceeded = true;
        _source!.cancel('Dio request deadline exceeded');
      } else {
        _deadlineTimer = Timer(remaining, () {
          _deadlineExceeded = true;
          _source!.cancel('Dio request deadline exceeded');
        });
      }
    }
  }

  CancellationSource? _source;
  DioCancellationBinding? _binding;
  CancellationRegistration? _registration;
  Timer? _deadlineTimer;
  bool _deadlineExceeded = false;

  CancelToken? get token => _binding?.token;

  bool get deadlineExceeded => _deadlineExceeded;

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    _registration?.dispose();
    _binding?.dispose();
    _source?.dispose();
    _deadlineTimer = null;
    _registration = null;
    _binding = null;
    _source = null;
  }
}

Result<String, DioFailure> _resolveRoute(
  RouteTemplate route,
  Map<String, String> parameters,
) {
  final requiredNames = <String>{};
  final segments = route.value.split('/');
  final resolved = <String>[];
  for (final segment in segments) {
    String? name;
    if (segment.startsWith(':')) {
      name = segment.substring(1);
    } else if (segment.startsWith('{') && segment.endsWith('}')) {
      name = segment.substring(1, segment.length - 1);
    }
    if (name == null) {
      resolved.add(segment);
      continue;
    }
    requiredNames.add(name);
    final value = parameters[name];
    if (value == null || value.isEmpty) {
      return Err<DioFailure>(
        const DioRouteFailure('A required path parameter is missing.'),
        StackTrace.current,
      );
    }
    resolved.add(Uri.encodeComponent(value));
  }
  if (parameters.keys.any((name) => !requiredNames.contains(name))) {
    return Err<DioFailure>(
      const DioRouteFailure('An unknown path parameter was supplied.'),
      StackTrace.current,
    );
  }
  return Ok<String>(resolved.join('/'));
}
