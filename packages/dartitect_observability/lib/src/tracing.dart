import 'dart:async';
import 'dart:math';

/// Work category used by tracing destinations.
enum SpanKind {
  /// Work internal to the current application.
  internal,

  /// Outbound client request.
  client,

  /// Inbound server request.
  server,

  /// Message production operation.
  producer,

  /// Message consumption operation.
  consumer,
}

/// Final outcome of a span.
enum SpanStatus {
  /// No explicit outcome was recorded.
  unset,

  /// Operation completed successfully.
  ok,

  /// Operation failed.
  error,

  /// Operation was cancelled cooperatively.
  cancelled,
}

/// Valid W3C trace identity.
final class TraceContext {
  /// Creates and validates a trace context.
  TraceContext({
    required this.traceId,
    required this.spanId,
    this.traceFlags = '00',
    this.traceState,
  }) {
    if (!_traceId.hasMatch(traceId) || _allZero.hasMatch(traceId)) {
      throw FormatException(
        'traceId must be 32 non-zero lowercase hex digits.',
      );
    }
    if (!_spanId.hasMatch(spanId) || _allZero.hasMatch(spanId)) {
      throw FormatException('spanId must be 16 non-zero lowercase hex digits.');
    }
    if (!_flags.hasMatch(traceFlags)) {
      throw FormatException('traceFlags must be two lowercase hex digits.');
    }
    if (traceState case final value? when value.length > 512) {
      throw FormatException('tracestate exceeds the W3C 512 character limit.');
    }
  }

  /// 16-byte W3C trace identifier.
  final String traceId;

  /// 8-byte W3C span identifier.
  final String spanId;

  /// W3C trace flags.
  final String traceFlags;

  /// Validated tracestate value, when supplied by a configured propagator.
  final String? traceState;

  /// Whether the sampled flag is set.
  bool get sampled => (int.parse(traceFlags, radix: 16) & 1) == 1;

  /// W3C `traceparent` value.
  String get traceParent => '00-$traceId-$spanId-$traceFlags';

  /// Parses a version-00 W3C traceparent without throwing.
  static TraceContext? tryParse(String? traceParent, {String? traceState}) {
    if (traceParent == null) return null;
    final match = _traceParent.firstMatch(traceParent.trim());
    if (match == null) return null;
    try {
      return TraceContext(
        traceId: match.group(1)!,
        spanId: match.group(2)!,
        traceFlags: match.group(3)!,
        traceState: _validTraceState(traceState),
      );
    } on FormatException {
      return null;
    }
  }

  static String? _validTraceState(String? value) {
    if (value == null || value.isEmpty || value.length > 512) return null;
    if (value.contains(RegExp(r'[\r\n]'))) return null;
    return value;
  }

  static final RegExp _traceId = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _spanId = RegExp(r'^[0-9a-f]{16}$');
  static final RegExp _flags = RegExp(r'^[0-9a-f]{2}$');
  static final RegExp _allZero = RegExp(r'^0+$');
  static final RegExp _traceParent = RegExp(
    r'^00-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$',
  );
}

/// Generates trace and span IDs without global state.
abstract interface class TraceIdGenerator {
  /// Returns 32 lowercase hexadecimal digits, not all zero.
  String nextTraceId();

  /// Returns 16 lowercase hexadecimal digits, not all zero.
  String nextSpanId();
}

/// Secure random W3C ID generator.
final class SecureTraceIdGenerator implements TraceIdGenerator {
  /// Creates an isolate-local generator.
  SecureTraceIdGenerator() : _random = Random.secure();

  final Random _random;

  @override
  String nextTraceId() => _hex(16);

  @override
  String nextSpanId() => _hex(8);

  String _hex(int bytes) {
    final buffer = StringBuffer();
    var nonZero = false;
    for (var index = 0; index < bytes; index += 1) {
      final value = _random.nextInt(256);
      nonZero = nonZero || value != 0;
      buffer.write(value.toRadixString(16).padLeft(2, '0'));
    }
    if (!nonZero) return '${'0' * (bytes * 2 - 1)}1';
    return buffer.toString();
  }
}

/// One active tracing operation.
abstract class Span {
  /// Creates a span base.
  const Span();

  /// Trace identity propagated to children.
  TraceContext get context;

  /// Whether [end] has already completed or begun.
  bool get isEnded;

  /// Adds sanitized metadata.
  void setAttribute(String key, Object? value);

  /// Adds a sanitized event to the span.
  void addEvent(String name, {Map<String, Object?> attributes = const {}});

  /// Ends this span. Repeated calls are harmless.
  FutureOr<void> end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  });
}

/// Destination that creates spans.
abstract class Tracer {
  /// Creates a tracer base.
  const Tracer();

  /// Starts a span with an optional remote or local parent.
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  });

  /// Drains pending tracing work.
  FutureOr<void> flush() {}

  /// Releases destination-owned resources.
  FutureOr<void> dispose() {}
}

/// Tracer used when tracing is disabled.
final class NoOpTracer extends Tracer {
  /// Creates a no-op tracer with isolate-local IDs.
  NoOpTracer({TraceIdGenerator? idGenerator})
    : _ids = idGenerator ?? SecureTraceIdGenerator();

  final TraceIdGenerator _ids;

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) => _NoOpSpan(
    TraceContext(
      traceId: parent?.traceId ?? _ids.nextTraceId(),
      spanId: _ids.nextSpanId(),
      traceFlags: parent?.traceFlags ?? '00',
      traceState: parent?.traceState,
    ),
  );
}

final class _NoOpSpan extends Span {
  _NoOpSpan(this.context);

  @override
  final TraceContext context;

  @override
  bool isEnded = false;

  @override
  void addEvent(String name, {Map<String, Object?> attributes = const {}}) {}

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) {
    isEnded = true;
  }
}

/// Explicit distributed-trace header propagation.
abstract interface class TracePropagator {
  /// Extracts trace headers, returning null for malformed input.
  TraceContext? extract(Map<String, String> headers);

  /// Injects only supported trace headers.
  void inject(Map<String, String> headers, TraceContext context);
}

/// W3C `traceparent`/`tracestate` propagator. Baggage is never injected.
final class W3CTracePropagator implements TracePropagator {
  /// Creates a W3C propagator.
  const W3CTracePropagator();

  @override
  TraceContext? extract(Map<String, String> headers) {
    String? traceParent;
    String? traceState;
    for (final entry in headers.entries) {
      switch (entry.key.toLowerCase()) {
        case 'traceparent':
          traceParent = entry.value;
        case 'tracestate':
          traceState = entry.value;
      }
    }
    return TraceContext.tryParse(traceParent, traceState: traceState);
  }

  @override
  void inject(Map<String, String> headers, TraceContext context) {
    headers['traceparent'] = context.traceParent;
    if (context.traceState case final state?) headers['tracestate'] = state;
  }
}
