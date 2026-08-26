import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:sentry/sentry.dart';

/// Reports sanitized errors through a consumer-initialized Sentry [Hub].
///
/// The Hub is borrowed: [dispose] is intentionally a no-op and never disables
/// a Sentry SDK initialized by the application.
final class SentryErrorReporter extends ErrorReporter {
  /// Creates an adapter borrowing [hub].
  SentryErrorReporter({required Hub hub, Redactor redactor = const Redactor()})
    : _hub = hub,
      _redactor = redactor;

  final Hub _hub;
  final Redactor _redactor;

  @override
  Future<void> report(ErrorEvent event) async {
    final error = _redactor.sanitizeError(event.error);
    final fingerprint = <String>[
      for (final value in event.fingerprint) '${_redactor.sanitize(value)}',
    ];
    final trace = event.context.traceContext;
    await _hub.captureEvent(
      SentryEvent(
        timestamp: event.timestamp,
        throwable: error,
        level: switch (event.severity) {
          ErrorSeverity.warning => SentryLevel.warning,
          ErrorSeverity.error => SentryLevel.error,
          ErrorSeverity.fatal => SentryLevel.fatal,
        },
        logger: 'dartitect',
        fingerprint: fingerprint.isEmpty ? null : fingerprint,
        tags: <String, String>{
          'dartitect.mechanism': event.mechanism.name,
          'dartitect.handled': '${event.handled}',
          if (trace != null) ...<String, String>{
            'dartitect.trace_id': trace.traceId,
            'dartitect.span_id': trace.spanId,
          },
        },
      ),
      stackTrace: _redactor.sanitizeStackTrace(event.stackTrace),
    );
  }
}
