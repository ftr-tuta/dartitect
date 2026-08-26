import 'dart:async';

import 'package:dartitect_observability/dartitect_observability.dart';

/// Payload-free tracing for ObjectBox Store open and close boundaries.
final class ObjectBoxInstrumentation {
  /// Creates instrumentation scoped to one Store composition.
  ObjectBoxInstrumentation({required this.tracer});

  /// Runtime-local tracer.
  final Tracer tracer;

  /// Tracer failures isolated from Store behavior.
  int traceFailureCount = 0;

  /// Traces Store acquisition without recording its filesystem path.
  Future<T> traceOpen<T>(FutureOr<T> Function() open) async {
    final span = _startSpan('ObjectBox Store open');
    final T value;
    try {
      value = await open();
    } catch (error, stackTrace) {
      await _endSafely(
        span,
        status: SpanStatus.error,
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _endSafely(span, status: SpanStatus.ok);
    return value;
  }

  /// Traces Store release and always ends the span.
  Future<void> traceClose(FutureOr<void> Function() close) async {
    final span = _startSpan('ObjectBox Store close');
    try {
      await close();
    } catch (error, stackTrace) {
      await _endSafely(
        span,
        status: SpanStatus.error,
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _endSafely(span, status: SpanStatus.ok);
  }

  Span _startSpan(String name) {
    try {
      return tracer.startSpan(name, kind: SpanKind.client);
    } on Object {
      traceFailureCount += 1;
      return NoOpTracer().startSpan(name, kind: SpanKind.client);
    }
  }

  Future<void> _endSafely(
    Span span, {
    required SpanStatus status,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    try {
      await span.end(status: status, error: error, stackTrace: stackTrace);
    } on Object {
      traceFailureCount += 1;
    }
  }
}
