import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

import 'command.dart';

/// No-argument command whose action receives typed progress and control.
final class ProgressCommand0<P, T, F extends Object>
    implements DartitectCommand<T, F>, Disposable {
  ProgressCommand0._(this._command, this._progress);

  /// Creates a typed-progress command while preserving [Command0] scheduling.
  factory ProgressCommand0(
    Future<Result<T, F>> Function(CommandExecutionContext<P> context) action, {
    CommandConcurrency concurrency = const CommandConcurrency.reject(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    ProgressReporter<P> progress = const NoOpProgressReporter<Never>(),
    DateTime? deadline,
    DateTime Function()? now,
    DartitectDiagnosticSubject? diagnostics,
  }) {
    final fenced = LatestExecutionProgressReporter<P>(reporter: progress);
    var executionId = 0;
    final command = Command0<T, F>.cancellable(
      (signal) async {
        final current = ++executionId;
        fenced.begin(current);
        try {
          return await action(
            CommandExecutionContext<P>(
              executionId: current,
              cancellation: signal,
              progress: fenced,
              deadline: deadline,
              now: now,
            ),
          );
        } finally {
          fenced.finish(current);
        }
      },
      concurrency: concurrency,
      reporter: reporter,
      diagnostics: diagnostics,
    );
    return ProgressCommand0<P, T, F>._(command, fenced);
  }

  final Command0<T, F> _command;
  final LatestExecutionProgressReporter<P> _progress;

  /// Current exhaustive command state.
  CommandState<T, F> get state => _command.state;

  @override
  CommandState<T, F> get value => state;

  /// Whether at least one accepted execution is active.
  bool get isRunning => _command.isRunning;

  /// Whether terminal command disposal has begun.
  bool get isDisposed => _command.isDisposed;

  /// Number of progress events rejected by the latest-execution fence.
  int get droppedProgressCount => _progress.droppedEventCount;

  /// Executes according to [Command0]'s bounded scheduling policy.
  Future<CommandExecution<T, F>> execute() => _command.execute();

  /// Executes the same action again through the same policy.
  Future<CommandExecution<T, F>> retry() => _command.retry();

  /// Requests cooperative cancellation of active work.
  bool cancel([Object reason = 'Progress command cancelled']) =>
      _command.cancel(reason);

  /// Clears a retained terminal while idle.
  bool reset() => _command.reset();

  /// Reopens a lane stopped by an unexpected crash.
  void resume() => _command.resume();

  @override
  void addListener(VoidCallback listener) => _command.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _command.removeListener(listener);

  @override
  void dispose() {
    _progress.dispose();
    _command.dispose();
  }

  @override
  Future<void> disposeAsync() async {
    _progress.dispose();
    await _command.disposeAsync();
  }
}

/// One-argument command whose action receives typed progress and control.
final class ProgressCommand1<A, P, T, F extends Object>
    implements DartitectCommand<T, F>, Disposable {
  ProgressCommand1._(this._command, this._progress);

  /// Creates a typed-progress command while preserving [Command1] scheduling.
  factory ProgressCommand1(
    Future<Result<T, F>> Function(
      A argument,
      CommandExecutionContext<P> context,
    )
    action, {
    CommandConcurrency concurrency = const CommandConcurrency.reject(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    ProgressReporter<P> progress = const NoOpProgressReporter<Never>(),
    DateTime? deadline,
    DateTime Function()? now,
    DartitectDiagnosticSubject? diagnostics,
  }) {
    final fenced = LatestExecutionProgressReporter<P>(reporter: progress);
    var executionId = 0;
    final command = Command1<A, T, F>.cancellable(
      (argument, signal) async {
        final current = ++executionId;
        fenced.begin(current);
        try {
          return await action(
            argument,
            CommandExecutionContext<P>(
              executionId: current,
              cancellation: signal,
              progress: fenced,
              deadline: deadline,
              now: now,
            ),
          );
        } finally {
          fenced.finish(current);
        }
      },
      concurrency: concurrency,
      reporter: reporter,
      diagnostics: diagnostics,
    );
    return ProgressCommand1<A, P, T, F>._(command, fenced);
  }

  final Command1<A, T, F> _command;
  final LatestExecutionProgressReporter<P> _progress;

  /// Current exhaustive command state.
  CommandState<T, F> get state => _command.state;

  @override
  CommandState<T, F> get value => state;

  /// Whether at least one accepted execution is active.
  bool get isRunning => _command.isRunning;

  /// Whether terminal command disposal has begun.
  bool get isDisposed => _command.isDisposed;

  /// Number of progress events rejected by the latest-execution fence.
  int get droppedProgressCount => _progress.droppedEventCount;

  /// Executes [argument] through the configured bounded policy.
  Future<CommandExecution<T, F>> execute(A argument) =>
      _command.execute(argument);

  /// Requests cooperative cancellation of active work.
  bool cancel([Object reason = 'Progress command cancelled']) =>
      _command.cancel(reason);

  /// Clears a retained terminal while idle.
  bool reset() => _command.reset();

  /// Reopens a lane stopped by an unexpected crash.
  void resume() => _command.resume();

  @override
  void addListener(VoidCallback listener) => _command.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _command.removeListener(listener);

  @override
  void dispose() {
    _progress.dispose();
    _command.dispose();
  }

  @override
  Future<void> disposeAsync() async {
    _progress.dispose();
    await _command.disposeAsync();
  }
}

/// Keyed command whose action receives typed progress and control.
final class KeyedProgressCommand1<K, A, P, T, F extends Object>
    implements DartitectCommand<T, F>, Disposable {
  KeyedProgressCommand1._(this._command, this._progress);

  /// Creates a typed-progress keyed command with bounded keys and concurrency.
  factory KeyedProgressCommand1(
    Future<Result<T, F>> Function(
      K key,
      A argument,
      CommandExecutionContext<P> context,
    )
    action, {
    CommandConcurrency concurrency = const CommandConcurrency.keyed(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    ProgressReporter<P> progress = const NoOpProgressReporter<Never>(),
    DateTime? deadline,
    DateTime Function()? now,
    DartitectDiagnosticSubject? diagnostics,
  }) {
    final fenced = LatestExecutionProgressReporter<P>(reporter: progress);
    var executionId = 0;
    final command = KeyedCommand1<K, A, T, F>(
      (key, argument, signal) async {
        final current = ++executionId;
        fenced.begin(current);
        try {
          return await action(
            key,
            argument,
            CommandExecutionContext<P>(
              executionId: current,
              cancellation: signal,
              progress: fenced,
              deadline: deadline,
              now: now,
            ),
          );
        } finally {
          fenced.finish(current);
        }
      },
      concurrency: concurrency,
      reporter: reporter,
      diagnostics: diagnostics,
    );
    return KeyedProgressCommand1<K, A, P, T, F>._(command, fenced);
  }

  final KeyedCommand1<K, A, T, F> _command;
  final LatestExecutionProgressReporter<P> _progress;

  /// Current exhaustive command state.
  CommandState<T, F> get state => _command.state;

  @override
  CommandState<T, F> get value => state;

  /// Whether at least one accepted execution is active.
  bool get isRunning => _command.isRunning;

  /// Whether terminal command disposal has begun.
  bool get isDisposed => _command.isDisposed;

  /// Number of progress events rejected by the latest-execution fence.
  int get droppedProgressCount => _progress.droppedEventCount;

  /// Number of keys with active work; key values are never exposed.
  int get activeKeyCount => _command.activeKeyCount;

  /// Executes [argument] within [key]'s bounded lane.
  Future<CommandExecution<T, F>> execute(K key, A argument) =>
      _command.execute(key, argument);

  /// Requests cancellation for one key.
  bool cancelKey(K key, [Object reason = 'Keyed progress command cancelled']) =>
      _command.cancelKey(key, reason);

  /// Requests cancellation for every active key.
  int cancelAll([Object reason = 'Keyed progress command cancelled']) =>
      _command.cancelAll(reason);

  /// Reopens [key] after an unexpected crash.
  void resume(K key) => _command.resume(key);

  /// Clears a retained terminal while idle.
  bool reset() => _command.reset();

  @override
  void addListener(VoidCallback listener) => _command.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _command.removeListener(listener);

  @override
  void dispose() {
    _progress.dispose();
    _command.dispose();
  }

  @override
  Future<void> disposeAsync() async {
    _progress.dispose();
    await _command.disposeAsync();
  }
}
