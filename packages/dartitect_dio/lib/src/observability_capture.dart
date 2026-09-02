import 'dart:collection';
import 'dart:typed_data';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart';

import 'route_template.dart';

/// Request/response sides eligible for explicit diagnostic capture.
enum DioObservabilityCaptureMode {
  /// Lifecycle metadata only; no payload surface is inspected.
  metadataOnly,

  /// Request-side opt-ins only.
  request,

  /// Response-side opt-ins only.
  response,

  /// Request- and response-side opt-ins.
  requestAndResponse,
}

/// Transport read policy, separate from destination privacy policy.
final class DioObservabilityCapturePolicy {
  /// Keeps the 1.0-style zero-payload behavior.
  const DioObservabilityCapturePolicy.metadataOnly()
    : mode = DioObservabilityCaptureMode.metadataOnly,
      captureHeaders = false,
      captureBody = false,
      captureQuery = false,
      maxTextCodePoints = 4096,
      maxCollectionEntries = 50,
      maxDepth = 6,
      maxNodes = 512;

  /// Enables selected, already-materialized JSON surfaces.
  const DioObservabilityCapturePolicy.diagnostic({
    this.mode = DioObservabilityCaptureMode.requestAndResponse,
    this.captureHeaders = false,
    this.captureBody = false,
    this.captureQuery = false,
    this.maxTextCodePoints = 4096,
    this.maxCollectionEntries = 50,
    this.maxDepth = 6,
    this.maxNodes = 512,
  });

  /// Eligible request/response sides.
  final DioObservabilityCaptureMode mode;

  /// Whether already-materialized header values may be inspected.
  final bool captureHeaders;

  /// Whether already-materialized JSON/text bodies may be inspected.
  final bool captureBody;

  /// Whether already-materialized query structures may be inspected.
  final bool captureQuery;

  /// Per-string Unicode code-point bound before runtime sanitization.
  final int maxTextCodePoints;

  /// Entries retained from one map or list.
  final int maxCollectionEntries;

  /// Maximum JSON container depth.
  final int maxDepth;

  /// Maximum values and keys visited by one phase capture.
  final int maxNodes;

  /// Whether request payload surfaces are eligible.
  bool get capturesRequest =>
      mode == DioObservabilityCaptureMode.request ||
      mode == DioObservabilityCaptureMode.requestAndResponse;

  /// Whether response payload surfaces are eligible.
  bool get capturesResponse =>
      mode == DioObservabilityCaptureMode.response ||
      mode == DioObservabilityCaptureMode.requestAndResponse;
}

/// Unsafe interceptor composition that can bypass privacy policy.
final class DioObservabilityConflictException implements Exception {
  /// Creates a safe static conflict.
  const DioObservabilityConflictException(this.message);

  /// Actionable message without request data.
  final String message;

  @override
  String toString() => message;
}

/// Explicit classified capture for already-materialized Dio JSON structures.
///
/// [DioInstrumentation] and [DioTelemetryInterceptor] remain the recommended
/// metadata-only defaults. This interceptor never reads streams, multipart,
/// binary data, files, or unknown objects.
final class DioObservabilityInterceptor extends Interceptor {
  /// Creates an unattached interceptor.
  DioObservabilityInterceptor({
    required this.logger,
    required RouteTemplateResolver routeTemplate,
    this.capturePolicy = const DioObservabilityCapturePolicy.metadataOnly(),
  }) : _routeTemplate = routeTemplate {
    _validateCapturePolicy(capturePolicy);
  }

  /// Validates the Dio composition, attaches one interceptor, and returns it.
  static DioObservabilityInterceptor attach(
    Dio dio, {
    required DartitectLogger logger,
    required RouteTemplateResolver routeTemplate,
    DioObservabilityCapturePolicy capturePolicy =
        const DioObservabilityCapturePolicy.metadataOnly(),
  }) {
    for (final interceptor in dio.interceptors) {
      if (interceptor is DioObservabilityInterceptor) {
        throw const DioObservabilityConflictException(
          'Dartitect classified Dio capture is already installed.',
        );
      }
      if (interceptor is LogInterceptor) {
        throw const DioObservabilityConflictException(
          'Dio LogInterceptor can bypass observability privacy; remove it '
          'before attaching classified capture.',
        );
      }
    }
    final interceptor = DioObservabilityInterceptor(
      logger: logger,
      routeTemplate: routeTemplate,
      capturePolicy: capturePolicy,
    );
    dio.interceptors.add(interceptor);
    return interceptor;
  }

  /// Runtime-owned logger that synchronously consumes classified values.
  final DartitectLogger logger;

  /// Explicit transport read policy.
  final DioObservabilityCapturePolicy capturePolicy;

  final RouteTemplateResolver _routeTemplate;
  final Expando<Stopwatch> _timers = Expando<Stopwatch>();

  /// Events omitted because route metadata was absent or invalid.
  int omittedEventCount = 0;

  /// Unsupported body/header/query surfaces omitted without inspection.
  int omittedCaptureCount = 0;

  /// Capture or logger failures isolated from request behavior.
  int captureFailureCount = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _timers[options] = Stopwatch()..start();
    _emit(
      options,
      phase: 'request',
      requestData: capturePolicy.capturesRequest,
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    _emit(
      response.requestOptions,
      phase: 'response',
      statusCode: response.statusCode,
      elapsed: _finish(response.requestOptions),
      responseData: capturePolicy.capturesResponse ? response.data : null,
      responseHeaders: capturePolicy.capturesResponse ? response.headers : null,
      captureResponseData: capturePolicy.capturesResponse,
    );
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _emit(
      error.requestOptions,
      phase: 'error',
      statusCode: error.response?.statusCode,
      elapsed: _finish(error.requestOptions),
      errorType: error.type,
      responseData: capturePolicy.capturesResponse
          ? error.response?.data
          : null,
      responseHeaders: capturePolicy.capturesResponse
          ? error.response?.headers
          : null,
      captureResponseData: capturePolicy.capturesResponse,
    );
    handler.next(error);
  }

  Duration? _finish(RequestOptions options) {
    final timer = _timers[options];
    timer?.stop();
    return timer?.elapsed;
  }

  void _emit(
    RequestOptions options, {
    required String phase,
    bool requestData = false,
    bool captureResponseData = false,
    int? statusCode,
    Duration? elapsed,
    DioExceptionType? errorType,
    Object? responseData,
    Headers? responseHeaders,
  }) {
    final RouteTemplate? route;
    try {
      route = _routeTemplate(options);
    } on Object {
      omittedEventCount += 1;
      return;
    }
    if (route == null) {
      omittedEventCount += 1;
      return;
    }
    final attributes = <String, Object?>{
      'http.phase': ObservabilityClassifiedValue<Object?>(
        phase,
        classes: <ObservabilityDataClass>{ObservabilityDataClass.safeEnum},
      ),
      'http.method': ObservabilityClassifiedValue<Object?>(
        options.method.toUpperCase(),
        classes: <ObservabilityDataClass>{ObservabilityDataClass.httpMethod},
      ),
      'http.route_template': ObservabilityClassifiedValue<Object?>(
        route.value,
        classes: <ObservabilityDataClass>{
          ObservabilityDataClass.httpRouteTemplate,
        },
      ),
      if (statusCode != null)
        'http.status': ObservabilityClassifiedValue<Object?>(
          statusCode,
          classes: <ObservabilityDataClass>{ObservabilityDataClass.httpStatus},
        ),
      if (elapsed != null)
        'http.elapsed': ObservabilityClassifiedValue<Object?>(
          elapsed,
          classes: <ObservabilityDataClass>{
            ObservabilityDataClass.safeDuration,
          },
        ),
      if (errorType != null)
        'http.error_type': ObservabilityClassifiedValue<Object?>(
          errorType.name,
          classes: <ObservabilityDataClass>{
            ObservabilityDataClass.httpErrorType,
          },
        ),
    };
    final budget = _CaptureBudget(capturePolicy);
    if (requestData) {
      if (capturePolicy.captureQuery) {
        _addCaptured(
          attributes,
          key: 'http.query',
          raw: options.queryParameters,
          dataClass: ObservabilityDataClass.httpQuery,
          budget: budget,
        );
      }
      if (capturePolicy.captureHeaders) {
        _addCaptured(
          attributes,
          key: 'http.request.headers',
          raw: options.headers,
          dataClass: ObservabilityDataClass.httpHeader,
          budget: budget,
        );
      }
      if (capturePolicy.captureBody) {
        _addCaptured(
          attributes,
          key: 'http.request.body',
          raw: options.data,
          dataClass: ObservabilityDataClass.httpRequestBody,
          budget: budget,
        );
      }
    }
    if (captureResponseData) {
      if (capturePolicy.captureHeaders && responseHeaders != null) {
        _addCaptured(
          attributes,
          key: 'http.response.headers',
          raw: responseHeaders.map,
          dataClass: ObservabilityDataClass.httpHeader,
          budget: budget,
        );
      }
      if (capturePolicy.captureBody) {
        _addCaptured(
          attributes,
          key: 'http.response.body',
          raw: responseData,
          dataClass: ObservabilityDataClass.httpResponseBody,
          budget: budget,
        );
      }
    }
    try {
      logger.event(
        ObservabilityLogEvent(
          name: ObservabilityEventName('dio.$phase'),
          level: phase == 'error' ? LogLevel.warning : LogLevel.debug,
          message: () => 'dio.$phase',
          context: ObservabilityContext(attributes: attributes),
        ),
      );
    } on Object {
      captureFailureCount += 1;
    }
  }

  void _addCaptured(
    Map<String, Object?> attributes, {
    required String key,
    required Object? raw,
    required ObservabilityDataClass dataClass,
    required _CaptureBudget budget,
  }) {
    try {
      final captured = budget.capture(raw, depth: 0);
      if (identical(captured, _unsupportedCapture)) {
        omittedCaptureCount += 1;
        return;
      }
      attributes[key] = ObservabilityClassifiedValue<Object?>(
        captured,
        classes: <ObservabilityDataClass>{dataClass},
      );
    } on Object {
      captureFailureCount += 1;
    }
  }
}

final class _CaptureBudget {
  _CaptureBudget(this.policy);

  final DioObservabilityCapturePolicy policy;
  final HashSet<Object> active = HashSet<Object>.identity();
  var nodes = 0;

  Object? capture(Object? input, {required int depth}) {
    if (nodes >= policy.maxNodes) return '[NODE_BUDGET]';
    nodes += 1;
    if (depth > policy.maxDepth) return '[MAX_DEPTH]';
    if (input == null || input is bool || input is num) return input;
    if (input is String) return _bounded(input);
    if (input is TypedData ||
        input is Stream<Object?> ||
        input is FormData ||
        input is List<int>) {
      return _unsupportedCapture;
    }
    if (input is List<Object?>) {
      if (!active.add(input)) return '[CYCLE]';
      try {
        final output = <Object?>[];
        for (final value in input.take(policy.maxCollectionEntries)) {
          final captured = capture(value, depth: depth + 1);
          if (identical(captured, _unsupportedCapture)) {
            output.add('[UNSUPPORTED]');
          } else {
            output.add(captured);
          }
        }
        if (input.length > policy.maxCollectionEntries) {
          output.add('[TRUNCATED]');
        }
        return List<Object?>.unmodifiable(output);
      } finally {
        active.remove(input);
      }
    }
    if (input is Map<Object?, Object?>) {
      if (!active.add(input)) return '[CYCLE]';
      try {
        final output = <String, Object?>{};
        var count = 0;
        for (final entry in input.entries) {
          if (count >= policy.maxCollectionEntries) {
            output['_truncated_entries'] = '[TRUNCATED]';
            break;
          }
          if (entry.key is! String) continue;
          final captured = capture(entry.value, depth: depth + 1);
          if (identical(captured, _unsupportedCapture)) continue;
          output[_bounded(entry.key! as String)] = captured;
          count += 1;
        }
        return Map<String, Object?>.unmodifiable(output);
      } finally {
        active.remove(input);
      }
    }
    return _unsupportedCapture;
  }

  String _bounded(String input) {
    final points = <int>[];
    final iterator = input.runes.iterator;
    while (points.length < policy.maxTextCodePoints && iterator.moveNext()) {
      points.add(iterator.current);
    }
    if (iterator.moveNext()) {
      return '${String.fromCharCodes(points)}…[TRUNCATED]';
    }
    return String.fromCharCodes(points);
  }
}

const Object _unsupportedCapture = _UnsupportedCapture();

final class _UnsupportedCapture {
  const _UnsupportedCapture();
}

void _validateCapturePolicy(DioObservabilityCapturePolicy policy) {
  if (policy.mode == DioObservabilityCaptureMode.metadataOnly &&
      (policy.captureBody || policy.captureHeaders || policy.captureQuery)) {
    throw ArgumentError(
      'metadataOnly cannot enable body, header, or query capture.',
    );
  }
  final limits = <String, int>{
    'maxTextCodePoints': policy.maxTextCodePoints,
    'maxCollectionEntries': policy.maxCollectionEntries,
    'maxDepth': policy.maxDepth,
    'maxNodes': policy.maxNodes,
  };
  for (final entry in limits.entries) {
    if (entry.value <= 0) {
      throw ArgumentError.value(entry.value, entry.key, 'must be > 0');
    }
  }
}
