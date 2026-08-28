import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';

/// Captured bootstrap and teardown evidence.
final class BootstrapHarnessResult<R> {
  /// Creates a harness result.
  const BootstrapHarnessResult({
    required this.attempt,
    required this.graphDisposeAttempted,
    required this.coordinatorDisposed,
  });

  /// Typed bootstrap attempt.
  final BootstrapAttempt<R> attempt;

  /// Whether a successful graph reached teardown.
  final bool graphDisposeAttempted;

  /// Whether coordinator teardown completed.
  final bool coordinatorDisposed;
}

/// Runs and tears down one [BootstrapCoordinator] attempt.
final class BootstrapContractHarness<R> {
  /// Creates an owning harness.
  const BootstrapContractHarness(this.coordinator);

  /// Coordinator owned for this scenario.
  final BootstrapCoordinator<R> coordinator;

  /// Runs once and drains every acquired graph.
  Future<BootstrapHarnessResult<R>> run() async {
    final attempt = await coordinator.run();
    var graphDisposeAttempted = false;
    try {
      if (attempt is BootstrapSucceeded<R>) {
        graphDisposeAttempted = true;
        await attempt.graph.disposeAsync();
      }
    } finally {
      await coordinator.disposeAsync();
    }
    return BootstrapHarnessResult<R>(
      attempt: attempt,
      graphDisposeAttempted: graphDisposeAttempted,
      coordinatorDisposed: true,
    );
  }
}

/// Captured retry result, crash, and attempt count.
final class RetryHarnessResult<T, F extends Object> {
  /// Creates a retry harness result.
  const RetryHarnessResult({
    required this.attemptCount,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// Successful or expected-failure result.
  final Result<T, F>? result;

  /// Unexpected crash or cancellation.
  final Object? error;

  /// Original unexpected stack.
  final StackTrace? stackTrace;

  /// Number of operation invocations.
  final int attemptCount;
}

/// Executes a resilience policy without a test-runner dependency.
final class RetryContractHarness<T, F extends Object> {
  /// Creates a retry harness.
  const RetryContractHarness({
    required this.executor,
    required this.policy,
    required this.operation,
  });

  /// Executor under test.
  final RetryExecutor executor;

  /// Explicit expected-failure policy.
  final RetryPolicy<F> policy;

  /// Consumer operation.
  final Future<Result<T, F>> Function(
    int attempt,
    CancellationSignal cancellation,
  )
  operation;

  /// Executes once and captures unexpected failures separately.
  Future<RetryHarnessResult<T, F>> run() async {
    final cancellation = CancellationSource();
    var attempts = 0;
    try {
      final result = await executor.execute<T, F>(
        operation: (attempt, signal) {
          attempts += 1;
          return operation(attempt, signal);
        },
        policy: policy,
        cancellation: cancellation.signal,
      );
      return RetryHarnessResult<T, F>(result: result, attemptCount: attempts);
    } catch (error, stackTrace) {
      return RetryHarnessResult<T, F>(
        error: error,
        stackTrace: stackTrace,
        attemptCount: attempts,
      );
    } finally {
      cancellation.dispose();
    }
  }
}

/// Captured job terminal and post-disposal counts.
final class JobHarnessResult<R, F extends Object> {
  /// Creates a job harness result.
  const JobHarnessResult({
    required this.activeAfterDispose,
    required this.rememberedAfterDispose,
    this.terminal,
    this.error,
    this.stackTrace,
  });

  /// Terminal job acknowledgement.
  final JobAck<R, F>? terminal;

  /// Unexpected job crash.
  final Object? error;

  /// Original crash stack.
  final StackTrace? stackTrace;

  /// Active executions after teardown.
  final int activeAfterDispose;

  /// Retained deduplication entries after teardown.
  final int rememberedAfterDispose;
}

/// Dispatches one job and always drains its dispatcher.
final class JobContractHarness<P, R, F extends Object, Q> {
  /// Creates an owning harness.
  const JobContractHarness(this.dispatcher);

  /// Dispatcher owned by this scenario.
  final JobDispatcher<P, R, F, Q> dispatcher;

  /// Runs one [envelope].
  Future<JobHarnessResult<R, F>> run(JobEnvelope<P> envelope) async {
    JobAck<R, F>? terminal;
    Object? error;
    StackTrace? stackTrace;
    try {
      terminal = await dispatcher.handle(envelope);
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    } finally {
      await dispatcher.disposeAsync();
    }
    return JobHarnessResult<R, F>(
      terminal: terminal,
      error: error,
      stackTrace: stackTrace,
      activeAfterDispose: dispatcher.activeCount,
      rememberedAfterDispose: dispatcher.rememberedCount,
    );
  }
}

/// Captured transfer outcome and post-disposal run state.
final class TransferHarnessResult<F extends Object> {
  /// Creates a transfer harness result.
  const TransferHarnessResult({
    required this.runningAfterDispose,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// Successful report or expected transport failure.
  final Result<TransferReport, F>? result;

  /// Unexpected protocol, cancellation, or provider crash.
  final Object? error;

  /// Original crash stack.
  final StackTrace? stackTrace;

  /// Whether work remains after teardown.
  final bool runningAfterDispose;
}

/// Starts one transfer and always drains the engine.
final class TransferContractHarness<F extends Object> {
  /// Creates an owning harness.
  const TransferContractHarness(this.engine);

  /// Engine owned by this scenario.
  final TransferEngine<F> engine;

  /// Runs one transfer identity.
  Future<TransferHarnessResult<F>> run(String transferId) async {
    Result<TransferReport, F>? result;
    Object? error;
    StackTrace? stackTrace;
    try {
      result = await engine.start(transferId).done;
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    } finally {
      await engine.disposeAsync();
    }
    return TransferHarnessResult<F>(
      result: result,
      error: error,
      stackTrace: stackTrace,
      runningAfterDispose: engine.isRunning,
    );
  }
}

/// Framework-neutral history semantics result.
final class LocalHistoryHarnessResult<T> {
  /// Creates a history result.
  const LocalHistoryHarnessResult({
    required this.afterUndo,
    required this.afterRedo,
    required this.redoDiscarded,
    required this.disposed,
  });

  /// Current value after undo.
  final T afterUndo;

  /// Current value after redo.
  final T afterRedo;

  /// Whether a new edit after undo discarded redo.
  final bool redoDiscarded;

  /// Whether terminal cleanup completed.
  final bool disposed;
}

/// Exercises undo, redo, branch replacement, and terminal disposal.
final class LocalHistoryContractHarness<T> {
  /// Creates a harness with three distinct consumer values.
  const LocalHistoryContractHarness({
    required this.history,
    required this.firstEdit,
    required this.branchEdit,
  });

  /// History owned by this scenario.
  final BoundedLocalHistory<T> history;

  /// First value recorded after the initial state.
  final T firstEdit;

  /// New branch value recorded after an undo.
  final T branchEdit;

  /// Runs the fixed local-history contract.
  LocalHistoryHarnessResult<T> run() {
    history.edit(firstEdit);
    history.undo();
    final afterUndo = history.value;
    history.redo();
    final afterRedo = history.value;
    history.undo();
    history.edit(branchEdit);
    final redoDiscarded = !history.canRedo;
    history.dispose();
    return LocalHistoryHarnessResult<T>(
      afterUndo: afterUndo,
      afterRedo: afterRedo,
      redoDiscarded: redoDiscarded,
      disposed: history.retainedEntryCount == 0,
    );
  }
}

/// Callback-based restoration validation without importing Flutter.
final class RestorationContractHarness<T, E> {
  /// Creates a codec boundary harness.
  const RestorationContractHarness({
    required this.encode,
    required this.decode,
    required this.invalidEnvelope,
  });

  /// Consumer/framework adapter encoding callback.
  final E Function(T value) encode;

  /// Consumer/framework adapter decoding callback.
  final T Function(E envelope) decode;

  /// Known-invalid envelope supplied by the test fixture.
  final E invalidEnvelope;

  /// Verifies round-trip and typed invalid-envelope rejection.
  RestorationHarnessResult<T, E> run(T value) {
    final envelope = encode(value);
    final decoded = decode(envelope);
    Object? invalidError;
    StackTrace? invalidStackTrace;
    try {
      decode(invalidEnvelope);
    } catch (error, stackTrace) {
      invalidError = error;
      invalidStackTrace = stackTrace;
    }
    return RestorationHarnessResult<T, E>(
      envelope: envelope,
      decoded: decoded,
      invalidError: invalidError,
      invalidStackTrace: invalidStackTrace,
    );
  }
}

/// Restoration round-trip evidence.
final class RestorationHarnessResult<T, E> {
  /// Creates a restoration result.
  const RestorationHarnessResult({
    required this.envelope,
    required this.decoded,
    required this.invalidError,
    required this.invalidStackTrace,
  });

  /// Encoded consumer envelope.
  final E envelope;

  /// Round-tripped value.
  final T decoded;

  /// Typed rejection for the known-invalid envelope.
  final Object? invalidError;

  /// Original invalid-envelope stack.
  final StackTrace? invalidStackTrace;
}

/// Framework-neutral audit of a diagnostics RPC surface.
final class ReadOnlyDiagnosticsContractHarness {
  /// Creates a harness for advertised extension method names.
  const ReadOnlyDiagnosticsContractHarness(this.methods);

  /// Advertised service extensions.
  final Iterable<String> methods;

  /// Returns forbidden method names; an empty result proves read-only shape.
  List<String> forbiddenMethods() {
    const allowed = <String>{
      'ext.dartitect.capabilities',
      'ext.dartitect.snapshot',
      'ext.dartitect.events',
    };
    final forbidden =
        methods.where((method) => !allowed.contains(method)).toList()..sort();
    return List<String>.unmodifiable(forbidden);
  }
}
