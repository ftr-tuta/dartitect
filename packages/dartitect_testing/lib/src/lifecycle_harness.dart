import 'dart:async';

/// Captures the outcome of one lifecycle phase.
final class LifecyclePhaseFailure {
  /// Creates a phase failure.
  const LifecyclePhaseFailure(this.phase, this.error, this.stackTrace);

  /// `create`, `start`, `execute`, or `dispose`.
  final String phase;

  /// Original error.
  final Object error;

  /// Original stack trace.
  final StackTrace stackTrace;
}

/// Framework-neutral result of [LifecycleHarness.run].
final class LifecycleRun<T> {
  /// Creates a lifecycle run result.
  const LifecycleRun({
    this.value,
    this.failure,
    required this.disposeAttempted,
  });

  /// Value returned by the execute phase, when successful.
  final T? value;

  /// First lifecycle failure, preserving its phase.
  final LifecyclePhaseFailure? failure;

  /// Whether a created resource reached the dispose phase.
  final bool disposeAttempted;

  /// Whether all phases succeeded.
  bool get succeeded => failure == null;
}

/// Runs explicit create/start/execute/dispose phases for unit tests.
final class LifecycleHarness<R extends Object> {
  /// Creates a harness around a resource factory.
  const LifecycleHarness({
    required this.create,
    this.start,
    required this.dispose,
  });

  /// Creates the resource under test.
  final FutureOr<R> Function() create;

  /// Optional non-blocking lifecycle start phase.
  final FutureOr<void> Function(R resource)? start;

  /// Required cleanup phase.
  final FutureOr<void> Function(R resource) dispose;

  /// Runs a body and always attempts cleanup after successful creation.
  Future<LifecycleRun<T>> run<T>(FutureOr<T> Function(R resource) body) async {
    R resource;
    try {
      resource = await create();
    } catch (error, stackTrace) {
      return LifecycleRun<T>(
        failure: LifecyclePhaseFailure('create', error, stackTrace),
        disposeAttempted: false,
      );
    }

    LifecyclePhaseFailure? failure;
    T? value;
    try {
      final startPhase = start;
      if (startPhase != null) {
        try {
          await startPhase(resource);
        } catch (error, stackTrace) {
          failure = LifecyclePhaseFailure('start', error, stackTrace);
        }
      }
      if (failure == null) {
        try {
          value = await body(resource);
        } catch (error, stackTrace) {
          failure = LifecyclePhaseFailure('execute', error, stackTrace);
        }
      }
    } finally {
      try {
        await dispose(resource);
      } catch (error, stackTrace) {
        failure ??= LifecyclePhaseFailure('dispose', error, stackTrace);
      }
    }

    return LifecycleRun<T>(
      value: value,
      failure: failure,
      disposeAttempted: true,
    );
  }
}
