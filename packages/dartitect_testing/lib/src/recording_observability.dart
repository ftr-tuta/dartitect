import 'package:dartitect_observability/dartitect_observability.dart';

/// In-memory log destination with lifecycle counters.
final class RecordingLogSink extends LogSink {
  /// Sanitized events in delivery order.
  final List<LogEvent> events = <LogEvent>[];

  /// Flush calls.
  int flushCalls = 0;

  /// Dispose calls.
  int disposeCalls = 0;

  @override
  void emit(LogEvent event) => events.add(event);

  @override
  void flush() => flushCalls += 1;

  @override
  void dispose() => disposeCalls += 1;
}

/// In-memory error reporter with lifecycle counters.
final class RecordingErrorReporter extends ErrorReporter {
  /// Sanitized events in delivery order.
  final List<ErrorEvent> events = <ErrorEvent>[];

  /// Flush calls.
  int flushCalls = 0;

  /// Dispose calls.
  int disposeCalls = 0;

  @override
  void report(ErrorEvent event) => events.add(event);

  @override
  void flush() => flushCalls += 1;

  @override
  void dispose() => disposeCalls += 1;
}

/// Deterministic tracer recording all spans and exact end calls.
final class RecordingTracer extends Tracer {
  /// Creates a tracer with deterministic valid IDs.
  RecordingTracer({TraceIdGenerator? ids})
    : _ids = ids ?? DeterministicTraceIdGenerator();

  final TraceIdGenerator _ids;

  /// Created spans in order.
  final List<RecordingSpan> spans = <RecordingSpan>[];

  /// Flush calls.
  int flushCalls = 0;

  /// Dispose calls.
  int disposeCalls = 0;

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    final span = RecordingSpan(
      name: name,
      kind: kind,
      attributes: <String, Object?>{...attributes},
      context: TraceContext(
        traceId: parent?.traceId ?? _ids.nextTraceId(),
        spanId: _ids.nextSpanId(),
        traceFlags: parent?.traceFlags ?? '01',
        traceState: parent?.traceState,
      ),
    );
    spans.add(span);
    return span;
  }

  @override
  void flush() => flushCalls += 1;

  @override
  void dispose() => disposeCalls += 1;
}

/// One mutable recorded span.
final class RecordingSpan extends Span {
  /// Creates a recording span.
  RecordingSpan({
    required this.name,
    required this.kind,
    required this.attributes,
    required this.context,
  });

  /// Operation name.
  final String name;

  /// Span category.
  final SpanKind kind;

  /// Recorded attributes.
  final Map<String, Object?> attributes;

  /// Recorded events.
  final List<(String, Map<String, Object?>)> events =
      <(String, Map<String, Object?>)>[];

  /// Number of end attempts accepted.
  int endCalls = 0;

  /// Final status.
  SpanStatus? status;

  /// Final error.
  Object? error;

  @override
  final TraceContext context;

  @override
  bool get isEnded => endCalls > 0;

  @override
  void addEvent(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    if (!isEnded) events.add((name, <String, Object?>{...attributes}));
  }

  @override
  void setAttribute(String key, Object? value) {
    if (!isEnded) attributes[key] = value;
  }

  @override
  void end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (isEnded) return;
    endCalls += 1;
    this.status = status;
    this.error = error;
  }
}

/// Predictable valid W3C IDs without global state.
final class DeterministicTraceIdGenerator implements TraceIdGenerator {
  var _next = 1;

  @override
  String nextSpanId() => (_next++).toRadixString(16).padLeft(16, '0');

  @override
  String nextTraceId() => (_next++).toRadixString(16).padLeft(32, '0');
}
