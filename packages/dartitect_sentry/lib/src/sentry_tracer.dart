import 'dart:async';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:sentry/sentry.dart' as sentry;

/// Creates Sentry transactions through a consumer-initialized, borrowed Hub.
final class SentryTracer extends Tracer {
  /// Creates an adapter borrowing [hub].
  SentryTracer({
    required sentry.Hub hub,
    Redactor redactor = const Redactor(),
    TraceIdGenerator? fallbackIds,
  }) : _hub = hub,
       _redactor = redactor,
       _fallbackIds = fallbackIds ?? SecureTraceIdGenerator();

  final sentry.Hub _hub;
  final Redactor _redactor;
  final TraceIdGenerator _fallbackIds;

  @override
  Span startSpan(
    String name, {
    TraceContext? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    final safeName = '${_redactor.sanitize(name)}';
    final operation = 'dartitect.${kind.name}';
    final transactionContext = sentry.SentryTransactionContext(
      safeName,
      operation,
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
    for (final entry in _redactor.sanitizeAttributes(attributes).entries) {
      delegate.setData(entry.key, entry.value);
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
    return _SentrySpan(delegate, context, _redactor);
  }

  static bool _validId(String value, int length) =>
      value.length == length &&
      !RegExp(r'^0+$').hasMatch(value) &&
      RegExp(
        '^[0-9a-f]{$length}'
        r'$',
      ).hasMatch(value);
}

final class _SentrySpan extends Span {
  _SentrySpan(this._delegate, this.context, this._redactor);

  final sentry.ISentrySpan _delegate;
  final Redactor _redactor;
  var _eventIndex = 0;

  @override
  final TraceContext context;

  @override
  bool get isEnded => _delegate.finished;

  @override
  void setAttribute(String key, Object? value) =>
      _delegate.setData(key, _redactor.sanitize(value, key: key));

  @override
  void addEvent(
    String name, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    if (isEnded) return;
    final prefix = 'event.${_eventIndex++}';
    _delegate
      ..setData('$prefix.name', '${_redactor.sanitize(name)}')
      ..setData('$prefix.attributes', _redactor.sanitizeAttributes(attributes));
  }

  @override
  Future<void> end({
    SpanStatus status = SpanStatus.unset,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (isEnded) return;
    if (error != null) _delegate.throwable = _redactor.sanitizeError(error);
    await _delegate.finish(status: _status(status));
  }

  static sentry.SpanStatus? _status(SpanStatus status) => switch (status) {
    SpanStatus.unset => null,
    SpanStatus.ok => const sentry.SpanStatus.ok(),
    SpanStatus.error => const sentry.SpanStatus.internalError(),
    SpanStatus.cancelled => const sentry.SpanStatus.cancelled(),
  };
}
