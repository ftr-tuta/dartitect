import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:dio/dio.dart';

import 'cancellation_binding.dart';
import 'result_mapping.dart';
import 'route_template.dart';

/// Cancellation contract accepted by typed JSON execution.
typedef CancellationToken = CancellationSignal;

/// One validated, explicitly declared JSON endpoint.
final class DioEndpoint<T> {
  /// Creates an endpoint for one supported HTTP method.
  DioEndpoint({
    required String method,
    required this.route,
    required this.decode,
    required Set<int> acceptedStatusCodes,
  }) : method = method.toUpperCase(),
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
  }

  /// Uppercase GET, POST, PUT, PATCH, or DELETE.
  final String method;

  /// Static validated route with named dynamic segments.
  final RouteTemplate route;

  /// Consumer-owned JSON-to-value decoder.
  final T Function(Object? json) decode;

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
    Object? jsonBody,
    CancellationToken? cancellation,
  });
}

/// Borrowed-Dio implementation of [DioJsonClient].
///
/// The caller owns and closes [dio] after all requests and instrumentation.
final class DefaultDioJsonClient implements DioJsonClient {
  /// Creates a typed executor over a borrowed [dio].
  const DefaultDioJsonClient(this.dio);

  /// Borrowed provider client.
  final Dio dio;

  @override
  Future<Result<DioResponse<T>, DioFailure>> execute<T>(
    DioEndpoint<T> endpoint, {
    Map<String, Object?> query = const <String, Object?>{},
    Map<String, String> pathParameters = const <String, String>{},
    Object? jsonBody,
    CancellationToken? cancellation,
  }) async {
    final resolved = _resolveRoute(endpoint.route, pathParameters);
    if (resolved case Err<DioFailure>(:final failure, :final stackTrace)) {
      return Err<DioFailure>(failure, stackTrace);
    }
    final path = (resolved as Ok<String>).value;
    final binding = cancellation == null
        ? null
        : DioCancellationBinding(cancellation);
    try {
      final captured = await captureDioException<Response<String>>(
        () => dio.request<String>(
          path,
          data: jsonBody,
          queryParameters: query,
          cancelToken: binding?.token,
          options: Options(
            method: endpoint.method,
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        ),
      );
      switch (captured) {
        case Err<Object>(:final failure, :final stackTrace):
          return Err<DioFailure>(failure as DioFailure, stackTrace);
        case Ok<dynamic>(:final value):
          final response = value as Response<String>;
          final status = response.statusCode;
          if (status == null ||
              !endpoint.acceptedStatusCodes.contains(status)) {
            return Err<DioFailure>(
              DioHttpFailure(statusCode: status),
              StackTrace.current,
            );
          }
          try {
            return Ok<DioResponse<T>>(
              DioResponse<T>(
                payload: endpoint.decode(
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
      binding?.dispose();
    }
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
