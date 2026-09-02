import 'dart:async';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:sentry/sentry.dart' as sentry;

/// Sentry log adapter whose public input is [PreparedLogEvent] only.
final class SentryPreparedLogSink extends PreparedLogSink {
  /// Creates an adapter borrowing [hub].
  const SentryPreparedLogSink({required sentry.Hub hub}) : _hub = hub;

  final sentry.Hub _hub;

  @override
  Future<void> emitPrepared(PreparedLogEvent event) async {
    if (event.level.index < LogLevel.error.index) {
      await _hub.addBreadcrumb(
        sentry.Breadcrumb(
          message: event.message,
          timestamp: event.timestamp,
          category: 'dartitect',
          level: _level(event.level),
          data: _boundedContext(event.context.attributes),
        ),
      );
      return;
    }
    await _hub.captureEvent(
      sentry.SentryEvent(
        timestamp: event.timestamp,
        throwable: event.error,
        message: sentry.SentryMessage(event.message),
        level: _level(event.level),
        logger: 'dartitect',
        contexts: _contexts(event.context, operation: 'dartitect.log'),
      ),
      stackTrace: _stackTrace(event.stackTrace),
    );
  }
}

/// Sentry error adapter whose public input is [PreparedErrorEvent] only.
final class SentryPreparedErrorReporter extends PreparedErrorReporter {
  /// Creates an adapter borrowing [hub].
  const SentryPreparedErrorReporter({required sentry.Hub hub}) : _hub = hub;

  final sentry.Hub _hub;

  @override
  Future<void> reportPrepared(PreparedErrorEvent event) async {
    await _hub.captureEvent(
      sentry.SentryEvent(
        timestamp: event.timestamp,
        throwable: event.error,
        level: switch (event.severity) {
          ErrorSeverity.warning => sentry.SentryLevel.warning,
          ErrorSeverity.error => sentry.SentryLevel.error,
          ErrorSeverity.fatal => sentry.SentryLevel.fatal,
        },
        logger: 'dartitect',
        fingerprint: event.fingerprint.isEmpty ? null : event.fingerprint,
        tags: <String, String>{
          'dartitect.mechanism': event.mechanism.name,
          'dartitect.handled': event.handled ? 'true' : 'false',
        },
        contexts: _contexts(event.context, operation: 'dartitect.error'),
      ),
      stackTrace: _stackTrace(event.stackTrace),
    );
  }
}

/// Sentry tracer whose public inputs are prepared tracing types only.
final class SentryPreparedTracer extends PreparedTracer {
  /// Creates an adapter borrowing [hub].
  SentryPreparedTracer({required sentry.Hub hub, TraceIdGenerator? fallbackIds})
    : _hub = hub,
      _fallbackIds = fallbackIds ?? SecureTraceIdGenerator();

  final sentry.Hub _hub;
  final TraceIdGenerator _fallbackIds;

  @override
  PreparedSpan startPreparedSpan(PreparedSpanStart start) {
    final parent = start.parent;
    final transactionContext = sentry.SentryTransactionContext(
      start.name,
      'dartitect.${start.kind.name}',
      traceId: parent == null ? null : sentry.SentryId.fromId(parent.traceId),
      parentSpanId: parent == null ? null : sentry.SpanId.fromId(parent.spanId),
      parentSamplingDecision: parent == null
          ? null
          : sentry.SentryTracesSamplingDecision(parent.sampled),
      origin: 'manual',
    );
    final delegate = _hub.startTransactionWithContext(
      transactionContext,
      bindToScope: false,
    );
    var dataCount = 0;
    for (final entry in start.attributes.entries) {
      if (dataCount >= _maxContextEntries) break;
      if (!_validDataKey(entry.key)) continue;
      delegate.setData(entry.key, entry.value);
      dataCount += 1;
    }
    final sentryTraceId = delegate.context.traceId.toString();
    final sentrySpanId = delegate.context.spanId.toString();
    final context = TraceContext(
      traceId: _validId(sentryTraceId, 32)
          ? sentryTraceId
          : parent?.traceId ?? _fallbackIds.nextTraceId(),
      spanId: _validId(sentrySpanId, 16)
          ? sentrySpanId
          : _fallbackIds.nextSpanId(),
      traceFlags: parent?.traceFlags ?? '01',
      traceState: parent?.traceState,
    );
    return _SentryPreparedSpan(delegate, context, dataCount);
  }
}

final class _SentryPreparedSpan extends PreparedSpan {
  _SentryPreparedSpan(this._delegate, this.context, this._dataCount);

  final sentry.ISentrySpan _delegate;
  int _dataCount;
  var _eventCount = 0;

  @override
  final TraceContext context;

  @override
  bool get isEnded => _delegate.finished;

  @override
  void setPreparedAttribute(PreparedSpanAttribute attribute) {
    if (isEnded ||
        _dataCount >= _maxContextEntries ||
        !_validDataKey(attribute.key)) {
      return;
    }
    _delegate.setData(attribute.key, attribute.value);
    _dataCount += 1;
  }

  @override
  void addPreparedEvent(PreparedSpanEvent event) {
    if (isEnded || _eventCount >= _maxSpanEvents) return;
    final prefix = 'event.${_eventCount++}';
    _delegate
      ..setData('$prefix.name', event.name)
      ..setData('$prefix.attributes', _boundedContext(event.attributes));
  }

  @override
  Future<void> endPrepared(PreparedSpanEnd end) async {
    if (isEnded) return;
    if (end.error != null) _delegate.throwable = end.error;
    await _delegate.finish(status: _status(end.status));
  }
}

sentry.Contexts _contexts(
  PreparedObservabilityContext context, {
  required String operation,
}) {
  final output = sentry.Contexts();
  final attributes = _boundedContext(context.attributes);
  if (attributes.isNotEmpty) output['dartitect'] = attributes;
  if (context.traceContext case final trace?) {
    output.trace = sentry.SentryTraceContext(
      operation: operation,
      traceId: sentry.SentryId.fromId(trace.traceId),
      spanId: sentry.SpanId.fromId(trace.spanId),
      sampled: trace.sampled,
      origin: 'manual',
    );
  }
  return output;
}

Map<String, dynamic> _boundedContext(Map<String, Object?> attributes) {
  final output = <String, dynamic>{};
  for (final entry in attributes.entries) {
    if (output.length >= _maxContextEntries) break;
    if (!_validDataKey(entry.key)) continue;
    output[entry.key] = entry.value;
  }
  return output;
}

bool _validDataKey(String key) =>
    key.isNotEmpty &&
    key.runes.length <= 80 &&
    !key.contains(RegExp(r'[\r\n]'));

StackTrace? _stackTrace(Object? value) => switch (value) {
  final List<String> frames => StackTrace.fromString(frames.join('\n')),
  final String marker => StackTrace.fromString(marker),
  _ => null,
};

sentry.SentryLevel _level(LogLevel level) => switch (level) {
  LogLevel.trace || LogLevel.debug => sentry.SentryLevel.debug,
  LogLevel.info => sentry.SentryLevel.info,
  LogLevel.warning => sentry.SentryLevel.warning,
  LogLevel.error => sentry.SentryLevel.error,
  LogLevel.fatal => sentry.SentryLevel.fatal,
};

sentry.SpanStatus? _status(SpanStatus status) => switch (status) {
  SpanStatus.unset => null,
  SpanStatus.ok => const sentry.SpanStatus.ok(),
  SpanStatus.error => const sentry.SpanStatus.internalError(),
  SpanStatus.cancelled => const sentry.SpanStatus.cancelled(),
};

bool _validId(String value, int length) =>
    value.length == length &&
    !RegExp(r'^0+$').hasMatch(value) &&
    RegExp(
      '^[0-9a-f]{$length}'
      r'$',
    ).hasMatch(value);

const int _maxContextEntries = 32;
const int _maxSpanEvents = 32;
