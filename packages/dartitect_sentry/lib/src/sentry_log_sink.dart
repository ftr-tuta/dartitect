import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:sentry/sentry.dart';

/// Sends sanitized Dartitect logs through a consumer-initialized Sentry [Hub].
///
/// Debug through warning logs become breadcrumbs. Error and fatal logs become
/// events. This adapter never initializes or closes Sentry.
final class SentryLogSink extends LogSink {
  /// Creates an adapter borrowing [hub].
  SentryLogSink({required Hub hub, Redactor redactor = const Redactor()})
    : _hub = hub,
      _redactor = redactor;

  final Hub _hub;
  final Redactor _redactor;

  @override
  Future<void> emit(LogEvent event) async {
    final message = '${_redactor.sanitize(event.message)}';
    final attributes = _redactor.sanitizeAttributes(event.context.attributes);
    if (event.level.index < LogLevel.error.index) {
      await _hub.addBreadcrumb(
        Breadcrumb(
          message: message,
          timestamp: event.timestamp,
          category: 'dartitect',
          level: _level(event.level),
          data: <String, dynamic>{
            ...attributes,
            if (event.context.traceContext case final trace?)
              'trace_id': trace.traceId,
          },
        ),
      );
      return;
    }
    await _hub.captureEvent(
      SentryEvent(
        timestamp: event.timestamp,
        throwable: event.error == null
            ? null
            : _redactor.sanitizeError(event.error!),
        message: SentryMessage(message),
        level: _level(event.level),
        logger: 'dartitect',
        tags: <String, String>{
          if (event.context.traceContext case final trace?) ...<String, String>{
            'dartitect.trace_id': trace.traceId,
            'dartitect.span_id': trace.spanId,
          },
        },
      ),
      stackTrace: event.stackTrace == null
          ? null
          : _redactor.sanitizeStackTrace(event.stackTrace!),
    );
  }

  static SentryLevel _level(LogLevel level) => switch (level) {
    LogLevel.trace || LogLevel.debug => SentryLevel.debug,
    LogLevel.info => SentryLevel.info,
    LogLevel.warning => SentryLevel.warning,
    LogLevel.error => SentryLevel.error,
    LogLevel.fatal => SentryLevel.fatal,
  };
}
