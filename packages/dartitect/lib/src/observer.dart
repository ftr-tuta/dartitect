/// Architecture events emitted by runtime primitives.
enum ArchitectureEventKind {
  /// An owned resource was registered.
  resourceAcquired,

  /// Cleanup of an owned resource started.
  resourceReleaseStarted,

  /// Cleanup of an owned resource completed.
  resourceReleased,

  /// Cleanup of an owned resource failed.
  resourceReleaseFailed,

  /// A runtime-like owner started shutting down.
  runtimeDisposing,

  /// A runtime-like owner finished shutting down.
  runtimeDisposed,

  /// An asynchronous command started.
  commandStarted,

  /// An asynchronous command completed successfully.
  commandSucceeded,

  /// An asynchronous command failed.
  commandFailed,

  /// An asynchronous command threw an unexpected exception.
  commandCrashed,

  /// An asynchronous command execution was rejected.
  commandRejected,

  /// An operation was attempted after its owner had begun shutdown.
  operationAfterDispose,
}

/// A deliberately small and secret-free architecture event.
final class ArchitectureEvent {
  /// Creates an architecture event.
  const ArchitectureEvent(
    this.kind, {
    required this.source,
    this.label,
    this.error,
    this.stackTrace,
  });

  /// Event category with stable semantics.
  final ArchitectureEventKind kind;

  /// Primitive that emitted the event, such as `ResourceOwner`.
  final String source;

  /// Optional consumer-provided diagnostic label.
  final String? label;

  /// Cleanup or operation error when the event reports a failure.
  final Object? error;

  /// Original stack trace for [error].
  final StackTrace? stackTrace;
}

/// Receives synchronous, optional architecture diagnostics.
///
/// Implementations must return quickly and should redact secrets before
/// forwarding events to a logger. Runtime behavior never depends on an
/// observer succeeding.
abstract interface class ArchitectureObserver {
  /// Receives [event].
  void onEvent(ArchitectureEvent event);
}

/// An observer that intentionally ignores every event.
final class NoOpArchitectureObserver implements ArchitectureObserver {
  /// Creates a no-op observer.
  const NoOpArchitectureObserver();

  @override
  void onEvent(ArchitectureEvent event) {}
}
