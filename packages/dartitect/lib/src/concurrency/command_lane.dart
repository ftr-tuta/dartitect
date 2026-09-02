import 'dart:async';
import 'dart:collection';

import '../result.dart';
import 'cancellation.dart';

/// Supported scheduling policy for one command lane.
enum CommandConcurrencyKind {
  /// Reject a call while another call is running.
  reject,

  /// Return the same future while a no-argument call is running.
  join,

  /// Drop a call while another call is running.
  drop,

  /// Execute calls in FIFO order with a bounded queue.
  sequential,

  /// Cancel the previous generation and run only the latest call.
  restartLatest,

  /// Run up to a bounded number of calls at once.
  concurrent,

  /// Apply a nested policy per key with bounded active keys.
  keyed,
}

/// Immutable concurrency policy and bounds.
final class CommandConcurrency {
  /// Rejects reentrancy and is the default policy.
  const CommandConcurrency.reject()
    : kind = CommandConcurrencyKind.reject,
      maxQueue = 0,
      maxConcurrent = 1,
      perKey = null;

  /// Joins the currently running no-argument execution.
  const CommandConcurrency.join()
    : kind = CommandConcurrencyKind.join,
      maxQueue = 0,
      maxConcurrent = 1,
      perKey = null;

  /// Drops calls made while an execution is running.
  const CommandConcurrency.drop()
    : kind = CommandConcurrencyKind.drop,
      maxQueue = 0,
      maxConcurrent = 1,
      perKey = null;

  /// Runs FIFO with a queue bounded by [maxQueue].
  const CommandConcurrency.sequential({this.maxQueue = 64})
    : kind = CommandConcurrencyKind.sequential,
      maxConcurrent = 1,
      perKey = null;

  /// Cancels the previous generation and discards its stale completion.
  const CommandConcurrency.restartLatest()
    : kind = CommandConcurrencyKind.restartLatest,
      maxQueue = 0,
      maxConcurrent = 1,
      perKey = null;

  /// Runs at most [maxConcurrent] executions simultaneously.
  const CommandConcurrency.concurrent({this.maxConcurrent = 4})
    : kind = CommandConcurrencyKind.concurrent,
      maxQueue = 0,
      perKey = null;

  /// Runs [perKey] independently for up to [maxConcurrent] active keys.
  const CommandConcurrency.keyed({
    this.perKey = const CommandConcurrency.sequential(),
    this.maxConcurrent = 4,
  }) : kind = CommandConcurrencyKind.keyed,
       maxQueue = 0;

  /// Policy category.
  final CommandConcurrencyKind kind;

  /// Maximum waiting entries for sequential execution.
  final int maxQueue;

  /// Maximum running calls or active keyed lanes.
  final int maxConcurrent;

  /// Nested policy for a keyed lane.
  final CommandConcurrency? perKey;
}

/// Explicit reason for rejecting a command call.
enum CommandLaneRejectionReason {
  /// The lane is already busy.
  busy,

  /// The bounded sequential queue is full.
  queueFull,

  /// The concurrent execution limit is reached.
  concurrentLimit,

  /// The keyed active-lane limit is reached.
  keyLimit,

  /// An unexpected crash stopped this lane.
  laneStopped,

  /// The lane has been disposed.
  disposed,
}

/// Result of command scheduling and typed execution.
sealed class CommandOutcome<T, F extends Object> {
  const CommandOutcome();
}

/// Successful command outcome.
final class CommandSucceeded<T, F extends Object> extends CommandOutcome<T, F> {
  /// Creates a success containing [value].
  const CommandSucceeded(this.value);

  /// Successful value.
  final T value;
}

/// Expected typed command failure.
final class CommandFailed<T, F extends Object> extends CommandOutcome<T, F> {
  /// Creates a failure preserving [stackTrace].
  const CommandFailed(this.failure, this.stackTrace);

  /// Expected failure.
  final F failure;

  /// Stack trace recorded by [Err].
  final StackTrace stackTrace;
}

/// Explicit command rejection before execution starts.
final class CommandRejected<T, F extends Object> extends CommandOutcome<T, F> {
  /// Creates a rejection for [reason].
  const CommandRejected(this.reason);

  /// Rejection reason.
  final CommandLaneRejectionReason reason;
}

/// A call intentionally dropped by policy.
final class CommandDropped<T, F extends Object> extends CommandOutcome<T, F> {
  /// Creates a dropped control outcome.
  const CommandDropped();
}

/// A running generation cooperatively cancelled or superseded.
final class CommandCancelled<T, F extends Object> extends CommandOutcome<T, F> {
  /// Creates a cancellation outcome with an optional [reason].
  const CommandCancelled(this.reason);

  /// Cancellation or supersession reason.
  final Object? reason;
}

/// Unexpected terminal crash associated with one accepted execution.
final class CommandLaneCrash {
  /// Creates a crash record preserving the original stack.
  const CommandLaneCrash({
    required this.executionId,
    required this.error,
    required this.stackTrace,
  });

  /// Monotonic lane-local accepted execution identity.
  final int executionId;

  /// Original unexpected error.
  final Object error;

  /// Original stack trace.
  final StackTrace stackTrace;
}

/// Receives unexpected command crashes before they are rethrown.
abstract interface class CommandCrashReporter {
  /// Reports [error] and its original [stackTrace].
  void report(Object error, StackTrace stackTrace);
}

/// Reporter that deliberately ignores unexpected crashes.
final class NoOpCommandCrashReporter implements CommandCrashReporter {
  /// Creates a no-op reporter.
  const NoOpCommandCrashReporter();

  @override
  void report(Object error, StackTrace stackTrace) {}
}

/// A no-argument command lane with typed failures and bounded concurrency.
final class CommandLane<T, F extends Object> {
  /// Creates a lane for [action].
  CommandLane({
    required Future<Result<T, F>> Function(CancellationSignal signal) action,
    this.concurrency = const CommandConcurrency.reject(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    void Function()? onChanged,
  }) : _action = action,
       _reporter = reporter,
       _onChanged = onChanged {
    _validateCommandConcurrency(concurrency);
    if (concurrency.kind == CommandConcurrencyKind.keyed) {
      throw ArgumentError.value(
        concurrency,
        'concurrency',
        'Use KeyedCommandLane for a keyed policy.',
      );
    }
  }

  /// Scheduling policy for this lane.
  final CommandConcurrency concurrency;

  final Future<Result<T, F>> Function(CancellationSignal signal) _action;
  final CommandCrashReporter _reporter;
  final void Function()? _onChanged;
  final List<_CommandEntry<T, F>> _running = <_CommandEntry<T, F>>[];
  final ListQueue<_CommandEntry<T, F>> _queue =
      ListQueue<_CommandEntry<T, F>>();
  CommandOutcome<T, F>? _lastOutcome;
  int? _lastOutcomeExecutionId;
  CommandLaneCrash? _lastCrash;
  int? _latestAcceptedExecutionId;
  var _stopped = false;
  var _disposed = false;
  var _generation = 0;
  Future<void>? _disposeFuture;

  /// Last accepted terminal outcome allowed by stale-publication policy.
  CommandOutcome<T, F>? get lastOutcome => _lastOutcome;

  /// Execution identity associated with [lastOutcome].
  int? get lastOutcomeExecutionId => _lastOutcomeExecutionId;

  /// Most recent unexpected crash allowed by stale-publication policy.
  CommandLaneCrash? get lastCrash => _lastCrash;

  /// Latest call accepted as a distinct execution, including queued calls.
  int? get latestAcceptedExecutionId => _latestAcceptedExecutionId;

  /// Number of actions that have started and not yet settled.
  int get runningCount => _running.length;

  /// Number of calls waiting in the bounded sequential queue.
  int get queuedCount => _queue.length;

  /// Whether an unexpected crash stopped this lane.
  bool get isStopped => _stopped;

  /// Whether disposal has begun.
  bool get isDisposed => _disposed;

  /// Schedules one execution according to [concurrency].
  Future<CommandOutcome<T, F>> execute() {
    if (_disposed) return _rejected(CommandLaneRejectionReason.disposed);
    if (_stopped) return _rejected(CommandLaneRejectionReason.laneStopped);
    switch (concurrency.kind) {
      case CommandConcurrencyKind.reject:
        if (_running.isNotEmpty) {
          return _rejected(CommandLaneRejectionReason.busy);
        }
      case CommandConcurrencyKind.join:
        if (_running.isNotEmpty) return _running.first.future;
      case CommandConcurrencyKind.drop:
        if (_running.isNotEmpty) {
          return Future<CommandOutcome<T, F>>.value(CommandDropped<T, F>());
        }
      case CommandConcurrencyKind.sequential:
        if (_running.isNotEmpty) {
          if (_queue.length >= concurrency.maxQueue) {
            return _rejected(CommandLaneRejectionReason.queueFull);
          }
          final queued = _CommandEntry<T, F>(++_generation);
          _latestAcceptedExecutionId = queued.generation;
          _queue.add(queued);
          _changed();
          return queued.future;
        }
      case CommandConcurrencyKind.restartLatest:
        final entry = _CommandEntry<T, F>(++_generation);
        _latestAcceptedExecutionId = entry.generation;
        for (final running in _running.toList(growable: false)) {
          _cancelEntry(running, 'Superseded by restartLatest');
        }
        _start(entry);
        return entry.future;
      case CommandConcurrencyKind.concurrent:
        if (_running.length >= concurrency.maxConcurrent) {
          return _rejected(CommandLaneRejectionReason.concurrentLimit);
        }
      case CommandConcurrencyKind.keyed:
        throw StateError('Keyed policy was rejected by the constructor.');
    }
    final entry = _CommandEntry<T, F>(++_generation);
    _latestAcceptedExecutionId = entry.generation;
    _start(entry);
    return entry.future;
  }

  /// Explicitly reopens a lane after its crashed action has settled.
  void resume() {
    if (_disposed) throw StateError('CommandLane is disposed.');
    if (!_stopped) return;
    if (_running.isNotEmpty) {
      throw StateError('Cannot resume before the crashed action settles.');
    }
    _stopped = false;
    _generation += 1;
    _changed();
  }

  /// Requests cooperative cancellation of every running execution.
  int cancel([Object reason = 'CommandLane cancelled']) {
    if (_disposed) return 0;
    final running = _running.toList(growable: false);
    for (final entry in running) {
      _cancelEntry(entry, reason);
    }
    return running.length;
  }

  /// Clears retained terminal state while no work is running or queued.
  bool resetTerminal() {
    if (_disposed || _stopped || _running.isNotEmpty || _queue.isNotEmpty) {
      return false;
    }
    _lastOutcome = null;
    _lastOutcomeExecutionId = null;
    _lastCrash = null;
    _changed();
    return true;
  }

  /// Cancels running work, rejects queued calls, and drains every action.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _changed();
    for (final queued in _queue) {
      _complete(
        queued,
        CommandRejected<T, F>(CommandLaneRejectionReason.disposed),
      );
    }
    _queue.clear();
    final running = _running.toList(growable: false);
    for (final entry in running) {
      _cancelEntry(entry, 'CommandLane disposed', publishTerminal: false);
    }
    await Future.wait<void>(running.map((entry) => entry.work));
    _changed();
  }

  void _start(_CommandEntry<T, F> entry) {
    _running.add(entry);
    _changed();
    entry._attach(_run(entry));
  }

  Future<void> _run(_CommandEntry<T, F> entry) async {
    try {
      entry.source.signal.throwIfCancelled();
      final result = await _action(entry.source.signal);
      if (entry.source.signal.isCancelled) {
        _complete(
          entry,
          CommandCancelled<T, F>(entry.source.signal.reason),
          updateLast: true,
        );
      } else {
        final outcome = switch (result) {
          Ok<dynamic>(:final value) => CommandSucceeded<T, F>(value as T),
          Err<Object>(:final failure, :final stackTrace) => CommandFailed<T, F>(
            failure as F,
            stackTrace,
          ),
        };
        _complete(entry, outcome, updateLast: true);
      }
    } on CancellationException catch (error) {
      _complete(entry, CommandCancelled<T, F>(error.reason), updateLast: true);
    } catch (error, stackTrace) {
      _stopped = true;
      if (_mayPublishTerminal(entry.generation)) {
        _lastCrash = CommandLaneCrash(
          executionId: entry.generation,
          error: error,
          stackTrace: stackTrace,
        );
        _lastOutcome = null;
        _lastOutcomeExecutionId = entry.generation;
      }
      _changed();
      _report(error, stackTrace);
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(error, stackTrace);
      }
      for (final queued in _queue) {
        _complete(
          queued,
          CommandRejected<T, F>(CommandLaneRejectionReason.laneStopped),
        );
      }
      _queue.clear();
    } finally {
      _running.remove(entry);
      _changed();
      _startNextSequential();
    }
  }

  void _startNextSequential() {
    if (_disposed ||
        _stopped ||
        concurrency.kind != CommandConcurrencyKind.sequential ||
        _running.isNotEmpty ||
        _queue.isEmpty) {
      return;
    }
    _start(_queue.removeFirst());
  }

  void _cancelEntry(
    _CommandEntry<T, F> entry,
    Object reason, {
    bool publishTerminal = true,
  }) {
    entry.source.cancel(reason);
    _complete(
      entry,
      CommandCancelled<T, F>(reason),
      updateLast: publishTerminal,
    );
    _changed();
  }

  void _complete(
    _CommandEntry<T, F> entry,
    CommandOutcome<T, F> outcome, {
    bool updateLast = false,
  }) {
    if (entry.completer.isCompleted) return;
    if (updateLast && _mayPublishTerminal(entry.generation)) {
      _lastOutcome = outcome;
      _lastOutcomeExecutionId = entry.generation;
      _lastCrash = null;
    }
    entry.completer.complete(outcome);
  }

  Future<CommandOutcome<T, F>> _rejected(CommandLaneRejectionReason reason) =>
      Future<CommandOutcome<T, F>>.value(CommandRejected<T, F>(reason));

  void _report(Object error, StackTrace stackTrace) {
    try {
      _reporter.report(error, stackTrace);
    } catch (_) {
      return;
    }
  }

  bool _mayPublishTerminal(int executionId) {
    if (concurrency.kind == CommandConcurrencyKind.restartLatest &&
        executionId != _latestAcceptedExecutionId) {
      return false;
    }
    return _lastOutcomeExecutionId == null ||
        executionId >= _lastOutcomeExecutionId!;
  }

  void _changed() {
    try {
      _onChanged?.call();
    } on Object {
      // State observation cannot alter scheduling behavior.
      return;
    }
  }
}

/// A typed argument lane isolated per key with a global active-key bound.
final class KeyedCommandLane<K, A, T, F extends Object> {
  /// Creates a keyed lane.
  KeyedCommandLane({
    required Future<Result<T, F>> Function(
      K key,
      A argument,
      CancellationSignal signal,
    )
    action,
    this.concurrency = const CommandConcurrency.keyed(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    void Function()? onChanged,
  }) : _action = action,
       _reporter = reporter,
       _onChanged = onChanged {
    _validateCommandConcurrency(concurrency);
    if (concurrency.kind != CommandConcurrencyKind.keyed ||
        concurrency.perKey?.kind == CommandConcurrencyKind.keyed) {
      throw ArgumentError.value(
        concurrency,
        'concurrency',
        'A KeyedCommandLane requires one non-keyed per-key policy.',
      );
    }
  }

  /// Keyed policy containing per-key scheduling and active-key limit.
  final CommandConcurrency concurrency;

  final Future<Result<T, F>> Function(
    K key,
    A argument,
    CancellationSignal signal,
  )
  _action;
  final CommandCrashReporter _reporter;
  final void Function()? _onChanged;
  final Map<K, _KeyState<K, A, T, F>> _states = <K, _KeyState<K, A, T, F>>{};
  CommandOutcome<T, F>? _lastOutcome;
  int? _lastOutcomeExecutionId;
  CommandLaneCrash? _lastCrash;
  int? _latestAcceptedExecutionId;
  var _generation = 0;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Keys with at least one action currently running.
  int get activeKeyCount =>
      _states.values.where((state) => state.running.isNotEmpty).length;

  /// Total running actions across keys.
  int get runningCount => _states.values.fold<int>(
    0,
    (count, state) => count + state.running.length,
  );

  /// Total queued actions across keys.
  int get queuedCount =>
      _states.values.fold<int>(0, (count, state) => count + state.queue.length);

  /// Number of keys stopped by an unexpected crash.
  int get stoppedKeyCount =>
      _states.values.where((state) => state.stopped).length;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Last accepted terminal outcome across keys.
  CommandOutcome<T, F>? get lastOutcome => _lastOutcome;

  /// Execution identity associated with [lastOutcome].
  int? get lastOutcomeExecutionId => _lastOutcomeExecutionId;

  /// Most recent unexpected accepted crash across keys.
  CommandLaneCrash? get lastCrash => _lastCrash;

  /// Latest distinct execution accepted across keys.
  int? get latestAcceptedExecutionId => _latestAcceptedExecutionId;

  /// Schedules [argument] within the lane selected by [key].
  Future<CommandOutcome<T, F>> execute(K key, A argument) {
    if (_disposed) return _rejected(CommandLaneRejectionReason.disposed);
    var state = _states[key];
    if (state == null) {
      if (activeKeyCount >= concurrency.maxConcurrent) {
        return _rejected(CommandLaneRejectionReason.keyLimit);
      }
      state = _KeyState<K, A, T, F>(key);
      _states[key] = state;
    }
    if (state.stopped) {
      return _rejected(CommandLaneRejectionReason.laneStopped);
    }
    final policy = concurrency.perKey!;
    switch (policy.kind) {
      case CommandConcurrencyKind.reject:
        if (state.running.isNotEmpty) {
          return _rejected(CommandLaneRejectionReason.busy);
        }
      case CommandConcurrencyKind.join:
        if (state.running.isNotEmpty) {
          final running = state.running.first;
          return running.argument == argument
              ? running.future
              : _rejected(CommandLaneRejectionReason.busy);
        }
      case CommandConcurrencyKind.drop:
        if (state.running.isNotEmpty) {
          return Future<CommandOutcome<T, F>>.value(CommandDropped<T, F>());
        }
      case CommandConcurrencyKind.sequential:
        if (state.running.isNotEmpty) {
          if (state.queue.length >= policy.maxQueue) {
            return _rejected(CommandLaneRejectionReason.queueFull);
          }
          final entry = _KeyedCommandEntry<K, A, T, F>(
            ++_generation,
            key,
            argument,
          );
          _latestAcceptedExecutionId = entry.generation;
          state.latestAcceptedExecutionId = entry.generation;
          state.queue.add(entry);
          _changed();
          return entry.future;
        }
      case CommandConcurrencyKind.restartLatest:
        final entry = _KeyedCommandEntry<K, A, T, F>(
          ++_generation,
          key,
          argument,
        );
        _latestAcceptedExecutionId = entry.generation;
        state.latestAcceptedExecutionId = entry.generation;
        for (final running in state.running.toList(growable: false)) {
          _cancelEntry(running, 'Superseded by keyed restartLatest');
        }
        _start(state, entry);
        return entry.future;
      case CommandConcurrencyKind.concurrent:
        if (state.running.length >= policy.maxConcurrent) {
          return _rejected(CommandLaneRejectionReason.concurrentLimit);
        }
      case CommandConcurrencyKind.keyed:
        throw StateError('Nested keyed concurrency is invalid.');
    }
    final entry = _KeyedCommandEntry<K, A, T, F>(++_generation, key, argument);
    _latestAcceptedExecutionId = entry.generation;
    state.latestAcceptedExecutionId = entry.generation;
    _start(state, entry);
    return entry.future;
  }

  /// Explicitly reopens [key] after its crashed work has settled.
  void resume(K key) {
    if (_disposed) throw StateError('KeyedCommandLane is disposed.');
    final state = _states[key];
    if (state == null || !state.stopped) return;
    if (state.running.isNotEmpty) {
      throw StateError('Cannot resume before crashed work settles.');
    }
    state.stopped = false;
    _states.remove(key);
    _changed();
  }

  /// Requests cooperative cancellation of running work for [key].
  int cancelKey(K key, [Object reason = 'KeyedCommandLane key cancelled']) {
    if (_disposed) return 0;
    final state = _states[key];
    if (state == null) return 0;
    final running = state.running.toList(growable: false);
    for (final entry in running) {
      _cancelEntry(entry, reason);
    }
    return running.length;
  }

  /// Requests cooperative cancellation across every active key.
  int cancelAll([Object reason = 'KeyedCommandLane cancelled']) {
    if (_disposed) return 0;
    final running = <_KeyedCommandEntry<K, A, T, F>>[
      for (final state in _states.values) ...state.running,
    ];
    for (final entry in running) {
      _cancelEntry(entry, reason);
    }
    return running.length;
  }

  /// Clears aggregate terminal state while every key is idle.
  bool resetTerminal() {
    if (_disposed ||
        stoppedKeyCount != 0 ||
        runningCount != 0 ||
        queuedCount != 0) {
      return false;
    }
    _lastOutcome = null;
    _lastOutcomeExecutionId = null;
    _lastCrash = null;
    _changed();
    return true;
  }

  /// Cancels and drains all keyed work.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _changed();
    final running = <_KeyedCommandEntry<K, A, T, F>>[];
    for (final state in _states.values) {
      for (final queued in state.queue) {
        _complete(
          queued,
          CommandRejected<T, F>(CommandLaneRejectionReason.disposed),
        );
      }
      state.queue.clear();
      running.addAll(state.running);
    }
    for (final entry in running) {
      _cancelEntry(entry, 'KeyedCommandLane disposed', publishTerminal: false);
    }
    await Future.wait<void>(running.map((entry) => entry.work));
    _states.clear();
    _changed();
  }

  void _start(
    _KeyState<K, A, T, F> state,
    _KeyedCommandEntry<K, A, T, F> entry,
  ) {
    state.running.add(entry);
    _changed();
    entry._attach(_run(state, entry));
  }

  Future<void> _run(
    _KeyState<K, A, T, F> state,
    _KeyedCommandEntry<K, A, T, F> entry,
  ) async {
    try {
      entry.source.signal.throwIfCancelled();
      final result = await _action(
        entry.key,
        entry.argument,
        entry.source.signal,
      );
      if (entry.source.signal.isCancelled) {
        _complete(
          entry,
          CommandCancelled<T, F>(entry.source.signal.reason),
          updateLast: true,
        );
      } else {
        final outcome = switch (result) {
          Ok<dynamic>(:final value) => CommandSucceeded<T, F>(value as T),
          Err<Object>(:final failure, :final stackTrace) => CommandFailed<T, F>(
            failure as F,
            stackTrace,
          ),
        };
        _complete(entry, outcome, updateLast: true);
      }
    } on CancellationException catch (error) {
      _complete(entry, CommandCancelled<T, F>(error.reason), updateLast: true);
    } catch (error, stackTrace) {
      state.stopped = true;
      if (_mayPublishTerminal(entry.generation, state)) {
        _lastCrash = CommandLaneCrash(
          executionId: entry.generation,
          error: error,
          stackTrace: stackTrace,
        );
        _lastOutcome = null;
        _lastOutcomeExecutionId = entry.generation;
      }
      _changed();
      _report(error, stackTrace);
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(error, stackTrace);
      }
      for (final queued in state.queue) {
        _complete(
          queued,
          CommandRejected<T, F>(CommandLaneRejectionReason.laneStopped),
        );
      }
      state.queue.clear();
      for (final sibling in state.running.toList(growable: false)) {
        if (!identical(sibling, entry)) {
          _cancelEntry(
            sibling,
            'Key lane stopped after crash',
            publishTerminal: false,
          );
        }
      }
    } finally {
      state.running.remove(entry);
      _changed();
      _startNext(state);
      if (!state.stopped && state.running.isEmpty && state.queue.isEmpty) {
        _states.remove(state.key);
      }
    }
  }

  void _startNext(_KeyState<K, A, T, F> state) {
    if (_disposed ||
        state.stopped ||
        concurrency.perKey!.kind != CommandConcurrencyKind.sequential ||
        state.running.isNotEmpty ||
        state.queue.isEmpty) {
      return;
    }
    _start(state, state.queue.removeFirst());
  }

  void _cancelEntry(
    _KeyedCommandEntry<K, A, T, F> entry,
    Object reason, {
    bool publishTerminal = true,
  }) {
    entry.source.cancel(reason);
    _complete(
      entry,
      CommandCancelled<T, F>(reason),
      updateLast: publishTerminal,
    );
    _changed();
  }

  void _complete(
    _KeyedCommandEntry<K, A, T, F> entry,
    CommandOutcome<T, F> outcome, {
    bool updateLast = false,
  }) {
    if (entry.completer.isCompleted) return;
    final state = _states[entry.key];
    if (updateLast && _mayPublishTerminal(entry.generation, state)) {
      _lastOutcome = outcome;
      _lastOutcomeExecutionId = entry.generation;
      _lastCrash = null;
    }
    entry.completer.complete(outcome);
  }

  Future<CommandOutcome<T, F>> _rejected(CommandLaneRejectionReason reason) =>
      Future<CommandOutcome<T, F>>.value(CommandRejected<T, F>(reason));

  void _report(Object error, StackTrace stackTrace) {
    try {
      _reporter.report(error, stackTrace);
    } catch (_) {
      return;
    }
  }

  bool _mayPublishTerminal(int executionId, _KeyState<K, A, T, F>? state) {
    if (state != null &&
        concurrency.perKey!.kind == CommandConcurrencyKind.restartLatest &&
        executionId != state.latestAcceptedExecutionId) {
      return false;
    }
    return _lastOutcomeExecutionId == null ||
        executionId >= _lastOutcomeExecutionId!;
  }

  void _changed() {
    try {
      _onChanged?.call();
    } on Object {
      // State observation cannot alter scheduling behavior.
      return;
    }
  }
}

void _validateCommandConcurrency(CommandConcurrency concurrency) {
  switch (concurrency.kind) {
    case CommandConcurrencyKind.sequential:
      if (concurrency.maxQueue <= 0) {
        throw ArgumentError.value(
          concurrency.maxQueue,
          'concurrency.maxQueue',
          'Must be positive for sequential scheduling.',
        );
      }
      return;
    case CommandConcurrencyKind.concurrent:
      if (concurrency.maxConcurrent <= 0) {
        throw ArgumentError.value(
          concurrency.maxConcurrent,
          'concurrency.maxConcurrent',
          'Must be positive for concurrent scheduling.',
        );
      }
      return;
    case CommandConcurrencyKind.keyed:
      if (concurrency.maxConcurrent <= 0) {
        throw ArgumentError.value(
          concurrency.maxConcurrent,
          'concurrency.maxConcurrent',
          'Must be positive for keyed scheduling.',
        );
      }
      final perKey = concurrency.perKey;
      if (perKey == null || perKey.kind == CommandConcurrencyKind.keyed) {
        throw ArgumentError.value(
          perKey,
          'concurrency.perKey',
          'Must be one non-keyed policy.',
        );
      }
      _validateCommandConcurrency(perKey);
      return;
    case CommandConcurrencyKind.reject ||
        CommandConcurrencyKind.join ||
        CommandConcurrencyKind.drop ||
        CommandConcurrencyKind.restartLatest:
      return;
  }
}

final class _CommandEntry<T, F extends Object> {
  _CommandEntry(this.generation);

  final int generation;
  final CancellationSource source = CancellationSource();
  final Completer<CommandOutcome<T, F>> completer =
      Completer<CommandOutcome<T, F>>();
  late final Future<CommandOutcome<T, F>> future = completer.future;
  final Completer<void> _work = Completer<void>.sync();
  Future<void> get work => _work.future;

  void _attach(Future<void> operation) {
    unawaited(
      operation.then<void>(
        (_) => _work.complete(),
        onError: (Object error, StackTrace stackTrace) =>
            _work.completeError(error, stackTrace),
      ),
    );
  }
}

final class _KeyedCommandEntry<K, A, T, F extends Object> {
  _KeyedCommandEntry(this.generation, this.key, this.argument);

  final int generation;
  final K key;
  final A argument;
  final CancellationSource source = CancellationSource();
  final Completer<CommandOutcome<T, F>> completer =
      Completer<CommandOutcome<T, F>>();
  late final Future<CommandOutcome<T, F>> future = completer.future;
  final Completer<void> _work = Completer<void>.sync();
  Future<void> get work => _work.future;

  void _attach(Future<void> operation) {
    unawaited(
      operation.then<void>(
        (_) => _work.complete(),
        onError: (Object error, StackTrace stackTrace) =>
            _work.completeError(error, stackTrace),
      ),
    );
  }
}

final class _KeyState<K, A, T, F extends Object> {
  _KeyState(this.key);

  final K key;
  final List<_KeyedCommandEntry<K, A, T, F>> running =
      <_KeyedCommandEntry<K, A, T, F>>[];
  final ListQueue<_KeyedCommandEntry<K, A, T, F>> queue =
      ListQueue<_KeyedCommandEntry<K, A, T, F>>();
  int? latestAcceptedExecutionId;
  var stopped = false;
}
