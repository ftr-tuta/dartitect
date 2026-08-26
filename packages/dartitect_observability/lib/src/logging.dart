import 'dart:async';
import 'dart:developer' as developer;

import 'package:dartitect/dartitect.dart';

import 'context.dart';

/// Ordered severity for local and remote logs.
enum LogLevel {
  /// Fine-grained execution detail.
  trace,

  /// Diagnostic development detail.
  debug,

  /// Normal lifecycle or business information.
  info,

  /// Recoverable condition worth attention.
  warning,

  /// Failed operation.
  error,

  /// Process-level failure.
  fatal,
}

/// Validated, low-cardinality event identity.
final class ObservabilityEventName extends ValueEquality {
  /// Defines a dotted lowercase event name such as `sync.run.started`.
  factory ObservabilityEventName(String value) {
    if (!_pattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'must be 2-80 lowercase dotted static segments',
      );
    }
    return ObservabilityEventName._(value);
  }

  const ObservabilityEventName._(this.value);

  /// Stable event identity.
  final String value;

  @override
  Iterable<Object?> get equalityFields => <Object?>[value];

  @override
  String toString() => value;

  static final RegExp _pattern = RegExp(
    r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$',
  );
}

/// Lazily builds a message only after runtime sampling succeeds.
typedef LazyLogMessage = String Function();

/// Named input event accepted by [DartitectLogger.event].
final class ObservabilityLogEvent {
  /// Creates one named, lazy event.
  ObservabilityLogEvent({
    required this.name,
    required this.level,
    required this.message,
    this.context,
    this.error,
    this.stackTrace,
  });

  /// Stable low-cardinality identity.
  final ObservabilityEventName name;

  /// Severity.
  final LogLevel level;

  /// Deferred human-readable message.
  final LazyLogMessage message;

  /// Optional structured context.
  final ObservabilityContext? context;

  /// Optional unexpected/handled error.
  final Object? error;

  /// Optional original stack.
  final StackTrace? stackTrace;
}

/// Immutable log record delivered to a [LogSink].
final class LogEvent {
  /// Creates a log event.
  LogEvent({
    required this.timestamp,
    required this.name,
    required this.level,
    required this.message,
    ObservabilityContext? context,
    this.error,
    this.stackTrace,
  }) : context = context ?? ObservabilityContext();

  /// UTC event time.
  final DateTime timestamp;

  /// Stable low-cardinality event identity.
  final ObservabilityEventName name;

  /// Event severity.
  final LogLevel level;

  /// Sanitized human-readable message.
  final String message;

  /// Sanitized correlation and metadata.
  final ObservabilityContext context;

  /// Sanitized error representation, when applicable.
  final Object? error;

  /// Original stack trace. Sinks must not serialize local absolute paths.
  final StackTrace? stackTrace;
}

/// Destination for sanitized log events.
abstract class LogSink {
  /// Allows constant stateless sinks.
  const LogSink();

  /// Accepts one sanitized event.
  FutureOr<void> emit(LogEvent event);

  /// Drains pending destination work.
  FutureOr<void> flush() {}

  /// Releases destination-owned resources.
  FutureOr<void> dispose() {}
}

/// Per-sink routing decision evaluated after global sampling.
abstract interface class LogSinkFilter {
  /// Whether [event] may be dispatched to one sink.
  bool allows(LogEvent event);
}

/// Callback-backed per-sink filter.
final class CallbackLogSinkFilter implements LogSinkFilter {
  /// Creates a sink filter.
  const CallbackLogSinkFilter(this.callback);

  /// Filter callback.
  final bool Function(LogEvent event) callback;

  @override
  bool allows(LogEvent event) => callback(event);
}

/// Callback-backed sink useful at composition and test boundaries.
final class CallbackLogSink extends LogSink {
  /// Creates a callback sink.
  const CallbackLogSink(this.onEvent, {this.onFlush, this.onDispose});

  /// Event callback.
  final FutureOr<void> Function(LogEvent event) onEvent;

  /// Optional flush callback.
  final FutureOr<void> Function()? onFlush;

  /// Optional disposal callback.
  final FutureOr<void> Function()? onDispose;

  @override
  FutureOr<void> emit(LogEvent event) => onEvent(event);

  @override
  FutureOr<void> flush() => onFlush?.call();

  @override
  FutureOr<void> dispose() => onDispose?.call();
}

/// Local sink backed by `dart:developer`.
final class DeveloperLogSink extends LogSink {
  /// Creates a local sink with a stable logger name.
  const DeveloperLogSink({this.name = 'dartitect'});

  /// `dart:developer` logger name.
  final String name;

  @override
  void emit(LogEvent event) {
    developer.log(
      event.message,
      name: name,
      level: _developerLevel(event.level),
      error: event.error,
      stackTrace: event.stackTrace,
      time: event.timestamp,
    );
  }

  static int _developerLevel(LogLevel level) => switch (level) {
    LogLevel.trace => 300,
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
    LogLevel.fatal => 1200,
  };
}

/// Privacy-aware logger exposed by an observability runtime.
abstract class DartitectLogger {
  /// Allows runtime-owned logger implementations.
  const DartitectLogger();

  /// Emits a statically named event with a lazy message.
  void event(ObservabilityLogEvent event) => log(
    event.level,
    event.message(),
    context: event.context,
    error: event.error,
    stackTrace: event.stackTrace,
  );

  /// Enqueues one event without waiting for sinks.
  void log(
    LogLevel level,
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  });

  /// Logs at trace severity.
  void trace(String message, {ObservabilityContext? context}) =>
      log(LogLevel.trace, message, context: context);

  /// Logs at debug severity.
  void debug(String message, {ObservabilityContext? context}) =>
      log(LogLevel.debug, message, context: context);

  /// Logs at informational severity.
  void info(String message, {ObservabilityContext? context}) =>
      log(LogLevel.info, message, context: context);

  /// Logs at warning severity.
  void warning(String message, {ObservabilityContext? context}) =>
      log(LogLevel.warning, message, context: context);

  /// Logs an expected or handled error.
  void error(
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.error,
    message,
    context: context,
    error: error,
    stackTrace: stackTrace,
  );

  /// Logs a fatal process-level failure.
  void fatal(
    String message, {
    ObservabilityContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    LogLevel.fatal,
    message,
    context: context,
    error: error,
    stackTrace: stackTrace,
  );
}
