import 'dart:async';

import 'package:dartitect_observability/dartitect_observability.dart';

/// Closed set of Drift persistence operations visible to tracing.
enum DriftInstrumentedOperation {
  /// Opens a consumer database.
  open('Drift database open'),

  /// Closes an owned consumer database.
  close('Drift database close'),

  /// Runs a domain mutation transaction.
  transaction('Drift transaction'),

  /// Reads a synchronization checkpoint.
  checkpointRead('Drift checkpoint read'),

  /// Writes a synchronization checkpoint.
  checkpointWrite('Drift checkpoint write'),

  /// Removes a synchronization checkpoint.
  checkpointRemove('Drift checkpoint remove'),

  /// Appends a synchronization journal fact.
  journalAppend('Drift journal append'),

  /// Loads incomplete synchronization attempts.
  journalLoad('Drift journal load');

  const DriftInstrumentedOperation(this.spanName);

  /// Fixed, payload-free span name.
  final String spanName;
}

/// Payload-free and failure-isolated tracing for Drift boundaries.
///
/// The tracer is borrowed. This adapter passes only a fixed span name, kind,
/// and closed [SpanStatus]. It never forwards SQL, paths, tables, identifiers,
/// payloads, failures, exceptions, or stack traces.
final class DriftInstrumentation {
  /// Creates instrumentation around a borrowed [tracer].
  DriftInstrumentation({required this.tracer});

  /// Borrowed runtime-local tracer.
  final Tracer tracer;

  /// Number of tracer failures isolated from database behavior.
  int traceFailureCount = 0;

  /// Runs [operation] inside one sanitized persistence span.
  Future<T> trace<T>(
    DriftInstrumentedOperation kind,
    FutureOr<T> Function() operation,
  ) async {
    final span = _startSpan(kind.spanName);
    try {
      final value = await operation();
      await _endSafely(span, SpanStatus.ok);
      return value;
    } catch (error, stackTrace) {
      await _endSafely(span, SpanStatus.error);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Span _startSpan(String name) {
    try {
      return tracer.startSpan(name, kind: SpanKind.client);
    } on Object {
      traceFailureCount += 1;
      return NoOpTracer().startSpan(name, kind: SpanKind.client);
    }
  }

  Future<void> _endSafely(Span span, SpanStatus status) async {
    try {
      await span.end(status: status);
    } on Object {
      traceFailureCount += 1;
    }
  }
}
