import 'dart:async';

/// Framework-neutral result of one Command contract exercise.
final class CommandHarnessResult<O> {
  /// Creates a recorded command run.
  const CommandHarnessResult({
    required this.notificationCount,
    required this.disposeAttempted,
    this.outcome,
    this.error,
    this.stackTrace,
  });

  /// Terminal command outcome when execution returned normally.
  final O? outcome;

  /// Unexpected execution error.
  final Object? error;

  /// Original unexpected stack.
  final StackTrace? stackTrace;

  /// Notifications observed before listener removal.
  final int notificationCount;

  /// Whether cleanup was attempted.
  final bool disposeAttempted;
}

/// Adapts any listenable Command without importing Flutter into testing.
final class CommandContractHarness<O> {
  /// Creates a harness from the Command's public callbacks.
  const CommandContractHarness({
    required this.execute,
    required this.addListener,
    required this.removeListener,
    required this.dispose,
  });

  /// Executes the command.
  final Future<O> Function() execute;

  /// Adds one notification listener.
  final void Function(void Function() listener) addListener;

  /// Removes the exact listener.
  final void Function(void Function() listener) removeListener;

  /// Disposes the command.
  final FutureOr<void> Function() dispose;

  /// Executes once, captures crashes, removes the listener, and disposes.
  Future<CommandHarnessResult<O>> run() async {
    var notifications = 0;
    void listener() => notifications += 1;
    addListener(listener);
    O? outcome;
    Object? error;
    StackTrace? stackTrace;
    try {
      outcome = await execute();
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    } finally {
      removeListener(listener);
      await dispose();
    }
    return CommandHarnessResult<O>(
      outcome: outcome,
      error: error,
      stackTrace: stackTrace,
      notificationCount: notifications,
      disposeAttempted: true,
    );
  }
}
