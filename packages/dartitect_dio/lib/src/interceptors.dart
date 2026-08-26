// Telemetry observer failures must not replace request behavior.
// ignore_for_file: dartitect_empty_catch

import 'dart:async';

import 'package:dio/dio.dart';

import 'route_template.dart';

/// Adds consumer-owned auth and tenant values to outgoing requests.
///
/// Callbacks run per request and no token is stored globally. Returning null
/// omits the corresponding header.
final class DartitectHeadersInterceptor extends Interceptor {
  /// Creates a header interceptor.
  DartitectHeadersInterceptor({
    this.authorization,
    this.tenant,
    this.authorizationHeader = 'Authorization',
    this.tenantHeader = 'X-Tenant-Id',
  });

  /// Supplies the complete authorization header value.
  final FutureOr<String?> Function(RequestOptions options)? authorization;

  /// Supplies a tenant identifier.
  final FutureOr<String?> Function(RequestOptions options)? tenant;

  /// Authorization header name.
  final String authorizationHeader;

  /// Tenant header name.
  final String tenantHeader;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final authValue = await authorization?.call(options);
      final tenantValue = await tenant?.call(options);
      if (authValue != null) options.headers[authorizationHeader] = authValue;
      if (tenantValue != null) options.headers[tenantHeader] = tenantValue;
      handler.next(options);
    } catch (error, stackTrace) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: error,
          stackTrace: stackTrace,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }
}

/// Secret-free request metadata passed to [DioTelemetryObserver].
final class DioTelemetryEvent {
  /// Creates a telemetry event.
  const DioTelemetryEvent({
    required this.phase,
    required this.method,
    required this.routeTemplate,
    this.statusCode,
    this.elapsed,
    this.errorType,
  });

  /// `request`, `response`, or `error`.
  final String phase;

  /// HTTP method.
  final String method;

  /// Consumer-supplied static route template, never the request URI.
  final RouteTemplate routeTemplate;

  /// Response status when available.
  final int? statusCode;

  /// Time since this request entered the interceptor.
  final Duration? elapsed;

  /// Dio error category, without body/headers.
  final DioExceptionType? errorType;
}

/// Receives redacted, synchronous Dio telemetry.
abstract interface class DioTelemetryObserver {
  /// Receives [event]. Implementations should return quickly.
  void onEvent(DioTelemetryEvent event);
}

/// Emits request lifecycle metadata without headers, body, or query values.
final class DioTelemetryInterceptor extends Interceptor {
  /// Creates a telemetry interceptor.
  DioTelemetryInterceptor(
    this.observer, {
    required RouteTemplateResolver routeTemplate,
  }) : _routeTemplate = routeTemplate;

  /// Consumer-owned telemetry destination.
  final DioTelemetryObserver observer;
  final RouteTemplateResolver _routeTemplate;
  final Expando<Stopwatch> _timers = Expando<Stopwatch>();

  /// Events omitted because no prevalidated template was supplied.
  int omittedEventCount = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _timers[options] = Stopwatch()..start();
    _emitFor(options, phase: 'request', method: options.method);
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    _emitFor(
      options,
      phase: 'response',
      method: options.method,
      statusCode: response.statusCode,
      elapsed: _finish(options),
    );
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _emitFor(
      error.requestOptions,
      phase: 'error',
      method: error.requestOptions.method,
      statusCode: error.response?.statusCode,
      elapsed: _finish(error.requestOptions),
      errorType: error.type,
    );
    handler.next(error);
  }

  Duration? _finish(RequestOptions options) {
    final timer = _timers[options];
    timer?.stop();
    return timer?.elapsed;
  }

  void _emitFor(
    RequestOptions options, {
    required String phase,
    required String method,
    int? statusCode,
    Duration? elapsed,
    DioExceptionType? errorType,
  }) {
    final route = _routeTemplate(options);
    if (route == null) {
      omittedEventCount += 1;
      return;
    }
    _emit(
      DioTelemetryEvent(
        phase: phase,
        method: method,
        routeTemplate: route,
        statusCode: statusCode,
        elapsed: elapsed,
        errorType: errorType,
      ),
    );
  }

  void _emit(DioTelemetryEvent event) {
    try {
      observer.onEvent(event);
    } on Object {
      // Telemetry is isolated from request behavior.
    }
  }
}
