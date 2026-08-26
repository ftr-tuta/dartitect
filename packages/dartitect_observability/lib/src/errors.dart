import 'dart:async';

import 'context.dart';

/// Severity of an error report.
enum ErrorSeverity {
  /// Recoverable condition worth operator attention.
  warning,

  /// Failed operation or unexpected application error.
  error,

  /// Process-level failure after which safe continuation is unlikely.
  fatal,
}

/// Boundary that observed an error.
enum ErrorMechanism {
  /// Explicit capture by application code.
  manual,

  /// Capture around an asynchronous command.
  command,

  /// Flutter framework error callback.
  flutterFramework,

  /// Platform dispatcher error callback.
  platformDispatcher,

  /// Uncaught guarded-zone error.
  zone,

  /// Dio client boundary.
  dio,

  /// ObjectBox persistence boundary.
  objectBox,
}

/// Sanitized error report delivered to an [ErrorReporter].
final class ErrorEvent {
  /// Creates an error event.
  ErrorEvent({
    required this.timestamp,
    required this.error,
    required this.stackTrace,
    this.severity = ErrorSeverity.error,
    this.mechanism = ErrorMechanism.manual,
    this.handled = true,
    List<String> fingerprint = const <String>[],
    ObservabilityContext? context,
  }) : fingerprint = List<String>.unmodifiable(fingerprint),
       context = context ?? ObservabilityContext();

  /// UTC event time.
  final DateTime timestamp;

  /// Sanitized error representation.
  final Object error;

  /// Original stack trace. Reporters must avoid serializing local paths as tags.
  final StackTrace stackTrace;

  /// Error severity.
  final ErrorSeverity severity;

  /// Capture boundary.
  final ErrorMechanism mechanism;

  /// Whether application code handled the failure.
  final bool handled;

  /// Stable, sanitized grouping hints.
  final List<String> fingerprint;

  /// Sanitized correlation and metadata.
  final ObservabilityContext context;
}

/// Destination for explicit unexpected-error reporting.
abstract class ErrorReporter {
  /// Allows constant stateless reporters.
  const ErrorReporter();

  /// Reports one sanitized event.
  FutureOr<void> report(ErrorEvent event);

  /// Drains pending destination work.
  FutureOr<void> flush() {}

  /// Releases destination-owned resources.
  FutureOr<void> dispose() {}
}

/// Reporter that keeps remote reporting disabled.
final class NoOpErrorReporter extends ErrorReporter {
  /// Creates a no-op reporter.
  const NoOpErrorReporter();

  @override
  void report(ErrorEvent event) {}
}

/// Callback-backed reporter useful at composition and test boundaries.
final class CallbackErrorReporter extends ErrorReporter {
  /// Creates a callback reporter.
  const CallbackErrorReporter(this.onReport, {this.onFlush, this.onDispose});

  /// Report callback.
  final FutureOr<void> Function(ErrorEvent event) onReport;

  /// Optional flush callback.
  final FutureOr<void> Function()? onFlush;

  /// Optional disposal callback.
  final FutureOr<void> Function()? onDispose;

  @override
  FutureOr<void> report(ErrorEvent event) => onReport(event);

  @override
  FutureOr<void> flush() => onFlush?.call();

  @override
  FutureOr<void> dispose() => onDispose?.call();
}
