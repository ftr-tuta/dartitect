import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dio/dio.dart';

import 'route_template.dart';

/// Signals that a Dio client would produce duplicate tracing/telemetry.
final class DioInstrumentationConflictException implements Exception {
  /// Creates a conflict with a safe diagnostic message.
  const DioInstrumentationConflictException(this.message);

  /// Actionable conflict description.
  final String message;

  @override
  String toString() => message;
}

/// Minimal, payload-free Dio request tracing.
///
/// It never records request/response bodies, headers, query values, or path.
/// Trace headers are injected only when an explicit [TracePropagator] is
/// supplied. Dispose it before the owning Dio client.
final class DioInstrumentation extends Interceptor implements Disposable {
  DioInstrumentation._({
    required Tracer tracer,
    required RouteTemplateResolver routeTemplate,
    TracePropagator? propagator,
  }) : _tracer = tracer,
       _routeTemplate = routeTemplate,
       _propagator = propagator;

  /// Validates [dio], attaches exactly one instrumentation, and returns it.
  static DioInstrumentation attach(
    Dio dio, {
    required Tracer tracer,
    required RouteTemplateResolver routeTemplate,
    TracePropagator? propagator,
  }) {
    for (final interceptor in dio.interceptors) {
      if (interceptor is DioInstrumentation) {
        throw const DioInstrumentationConflictException(
          'Dartitect Dio instrumentation is already installed.',
        );
      }
      final type = interceptor.runtimeType.toString().toLowerCase();
      if (type.contains('sentry') && type.contains('dio')) {
        throw const DioInstrumentationConflictException(
          'sentry_dio instrumentation is already installed; choose one Dio tracer.',
        );
      }
    }
    final instrumentation = DioInstrumentation._(
      tracer: tracer,
      routeTemplate: routeTemplate,
      propagator: propagator,
    );
    dio.interceptors.add(instrumentation);
    return instrumentation;
  }

  final Tracer _tracer;
  final RouteTemplateResolver _routeTemplate;
  final TracePropagator? _propagator;
  final Map<RequestOptions, Span> _active = <RequestOptions, Span>{};
  bool _disposed = false;

  /// Tracer failures isolated from request behavior.
  int traceFailureCount = 0;

  /// Requests omitted from tracing because route metadata was unavailable.
  int omittedRequestCount = 0;

  /// Number of unfinished requests, exposed for leak assertions.
  int get activeRequestCount => _active.length;

  /// Whether this instrumentation has ended its active spans.
  bool get isDisposed => _disposed;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_disposed) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: const DioInstrumentationConflictException(
            'Dio instrumentation was disposed.',
          ),
        ),
      );
      return;
    }
    final span = _startSpan(options);
    _active[options] = span;
    final propagator = _propagator;
    if (propagator != null) {
      final injected = <String, String>{};
      try {
        propagator.inject(injected, span.context);
      } on Object {
        traceFailureCount += 1;
        injected.clear();
      }
      for (final entry in injected.entries) {
        options.headers[entry.key] = entry.value;
      }
    }
    handler.next(options);
  }

  Span _startSpan(RequestOptions options) {
    final route = _routeTemplate(options);
    if (route == null) {
      omittedRequestCount += 1;
      return NoOpTracer().startSpan('HTTP request', kind: SpanKind.client);
    }
    try {
      return _tracer.startSpan(
        'HTTP ${options.method.toUpperCase()} ${route.value}',
        kind: SpanKind.client,
        attributes: <String, Object?>{
          'http.request.method': options.method.toUpperCase(),
          'http.route': route.value,
        },
      );
    } on Object {
      traceFailureCount += 1;
      return NoOpTracer().startSpan('HTTP request', kind: SpanKind.client);
    }
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    final statusCode = response.statusCode;
    final span = _active.remove(response.requestOptions);
    if (span != null) {
      if (statusCode != null) {
        span.setAttribute('http.response.status_code', statusCode);
      }
      _end(
        span,
        statusCode == null || statusCode < 400
            ? SpanStatus.ok
            : SpanStatus.error,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final span = _active.remove(error.requestOptions);
    if (span != null) {
      span.setAttribute('error.type', error.type.name);
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        span.setAttribute('http.response.status_code', statusCode);
      }
      _end(
        span,
        error.type == DioExceptionType.cancel
            ? SpanStatus.cancelled
            : SpanStatus.error,
      );
    }
    handler.next(error);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final spans = _active.values.toList(growable: false);
    _active.clear();
    for (final span in spans) {
      _end(span, SpanStatus.cancelled);
    }
  }

  void _end(Span span, SpanStatus status) {
    try {
      final result = span.end(status: status);
      if (result is Future<void>) {
        unawaited(
          result.catchError((Object _, StackTrace _) {
            traceFailureCount += 1;
          }),
        );
      }
    } on Object {
      // Tracing cannot alter request behavior.
      traceFailureCount += 1;
    }
  }
}
