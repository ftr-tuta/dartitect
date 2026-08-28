import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

/// Current ability of a command to admit a new distinct execution.
enum CommandAdmissionStatus {
  /// At least one new execution can be accepted.
  accepting,

  /// A reject/join/drop lane already has running work.
  busy,

  /// A bounded sequential queue is full.
  queueFull,

  /// A bounded concurrent lane is at capacity.
  concurrentLimit,

  /// A keyed command is at its active-key bound.
  keyLimit,

  /// An unexpected crash stopped the affected lane pending explicit resume.
  stopped,

  /// Terminal disposal has begun.
  disposed,
}

/// Observable aggregate state shared by every Flutter command.
sealed class CommandState<T, F extends Object> extends ValueEquality {
  const CommandState({
    required this.runningCount,
    required this.queuedCount,
    required this.admissionStatus,
    required this.latestAcceptedExecutionId,
    required this.terminalExecutionId,
  });

  /// Accepted executions that started and have not drained.
  final int runningCount;

  /// Accepted calls waiting in bounded FIFO queues.
  final int queuedCount;

  /// Current aggregate admission status.
  final CommandAdmissionStatus admissionStatus;

  /// Latest distinct accepted execution, including queued work.
  final int? latestAcceptedExecutionId;

  /// Execution associated with the retained terminal, when present.
  final int? terminalExecutionId;

  /// Whether any accepted execution is still running.
  bool get isRunning => runningCount > 0;

  /// Common equality fields retained by every exhaustive state variant.
  Iterable<Object?> get stateEqualityFields => <Object?>[
    runningCount,
    queuedCount,
    admissionStatus,
    latestAcceptedExecutionId,
    terminalExecutionId,
  ];
}

/// No terminal is retained and no command execution is active.
final class CommandIdleState<T, F extends Object> extends CommandState<T, F> {
  /// Creates idle state.
  const CommandIdleState({
    super.runningCount = 0,
    super.queuedCount = 0,
    super.admissionStatus = CommandAdmissionStatus.accepting,
    super.latestAcceptedExecutionId,
  }) : super(terminalExecutionId: null);

  @override
  Iterable<Object?> get equalityFields => stateEqualityFields;
}

/// Work is active but no accepted terminal is retained.
final class CommandRunningState<T, F extends Object>
    extends CommandState<T, F> {
  /// Creates running state.
  const CommandRunningState({
    super.runningCount = 1,
    super.queuedCount = 0,
    super.admissionStatus = CommandAdmissionStatus.busy,
    super.latestAcceptedExecutionId,
  }) : super(terminalExecutionId: null);

  @override
  Iterable<Object?> get equalityFields => stateEqualityFields;
}

/// The retained accepted execution succeeded.
final class CommandSuccessState<T, F extends Object>
    extends CommandState<T, F> {
  /// Creates success state containing [value].
  const CommandSuccessState(
    this.value, {
    this.executionId = 0,
    super.runningCount = 0,
    super.queuedCount = 0,
    super.admissionStatus = CommandAdmissionStatus.accepting,
    super.latestAcceptedExecutionId,
  }) : super(terminalExecutionId: executionId);

  /// Successful value.
  final T value;

  /// Accepted execution that produced [value].
  final int executionId;

  @override
  Iterable<Object?> get equalityFields => <Object?>[
    ...stateEqualityFields,
    value,
  ];
}

/// The retained accepted execution produced an expected typed failure.
final class CommandFailureState<T, F extends Object>
    extends CommandState<T, F> {
  /// Creates expected-failure state.
  const CommandFailureState(
    this.failure,
    this.stackTrace, {
    this.executionId = 0,
    super.runningCount = 0,
    super.queuedCount = 0,
    super.admissionStatus = CommandAdmissionStatus.accepting,
    super.latestAcceptedExecutionId,
  }) : super(terminalExecutionId: executionId);

  /// Expected failure.
  final F failure;

  /// Stack captured at the expected-failure boundary.
  final StackTrace stackTrace;

  /// Accepted execution that produced [failure].
  final int executionId;

  @override
  Iterable<Object?> get equalityFields => <Object?>[
    ...stateEqualityFields,
    failure,
    stackTrace,
  ];
}

/// The retained accepted execution crashed unexpectedly.
final class CommandCrashState<T, F extends Object> extends CommandState<T, F> {
  /// Creates crash state preserving the original stack.
  const CommandCrashState(
    this.error,
    this.stackTrace, {
    this.executionId = 0,
    super.runningCount = 0,
    super.queuedCount = 0,
    super.admissionStatus = CommandAdmissionStatus.stopped,
    super.latestAcceptedExecutionId,
  }) : super(terminalExecutionId: executionId);

  /// Unexpected error.
  final Object error;

  /// Original stack trace.
  final StackTrace stackTrace;

  /// Accepted execution that crashed.
  final int executionId;

  @override
  Iterable<Object?> get equalityFields => <Object?>[
    ...stateEqualityFields,
    error,
    stackTrace,
  ];
}

/// The retained accepted execution was cooperatively cancelled.
final class CommandCancelledState<T, F extends Object>
    extends CommandState<T, F> {
  /// Creates cancellation state.
  const CommandCancelledState(
    this.reason, {
    this.executionId = 0,
    super.runningCount = 0,
    super.queuedCount = 0,
    super.admissionStatus = CommandAdmissionStatus.accepting,
    super.latestAcceptedExecutionId,
  }) : super(terminalExecutionId: executionId);

  /// Static or owner-supplied cancellation reason.
  final Object? reason;

  /// Accepted execution that was cancelled.
  final int executionId;

  @override
  Iterable<Object?> get equalityFields => <Object?>[
    ...stateEqualityFields,
    reason,
  ];
}

/// Stable reason why a command call did not start.
enum CommandRejectionReason {
  /// The selected reject/join lane is busy for this call.
  busy,

  /// The bounded sequential queue is full.
  queueFull,

  /// The bounded concurrent limit is reached.
  concurrentLimit,

  /// The bounded active-key limit is reached.
  keyLimit,

  /// An unexpected crash stopped the affected lane.
  laneStopped,

  /// The command has been disposed.
  disposed,
}

/// Explicit control/result outcome of one command call.
sealed class CommandExecution<T, F extends Object> {
  const CommandExecution();
}

/// An accepted call completed successfully.
final class CommandExecutionSucceeded<T, F extends Object>
    extends CommandExecution<T, F> {
  /// Creates success outcome.
  const CommandExecutionSucceeded(this.value, {this.executionId = 0});

  /// Successful value.
  final T value;

  /// Accepted execution identity.
  final int executionId;
}

/// An accepted call completed with an expected typed failure.
final class CommandExecutionFailed<T, F extends Object>
    extends CommandExecution<T, F> {
  /// Creates expected-failure outcome.
  const CommandExecutionFailed(
    this.failure,
    this.stackTrace, {
    this.executionId = 0,
  });

  /// Expected failure.
  final F failure;

  /// Failure stack.
  final StackTrace stackTrace;

  /// Accepted execution identity.
  final int executionId;
}

/// A call was rejected before execution.
final class CommandExecutionRejected<T, F extends Object>
    extends CommandExecution<T, F> {
  /// Creates rejected outcome.
  const CommandExecutionRejected(this.reason);

  /// Stable rejection reason.
  final CommandRejectionReason reason;
}

/// A call was intentionally dropped without starting or queueing.
final class CommandExecutionDropped<T, F extends Object>
    extends CommandExecution<T, F> {
  /// Creates a dropped control outcome.
  const CommandExecutionDropped();
}

/// An accepted execution was cooperatively cancelled or superseded.
final class CommandExecutionCancelled<T, F extends Object>
    extends CommandExecution<T, F> {
  /// Creates cancellation outcome.
  const CommandExecutionCancelled(this.reason, {this.executionId = 0});

  /// Optional owner-supplied reason.
  final Object? reason;

  /// Accepted execution identity.
  final int executionId;
}

mixin _CommandBinding<T, F extends Object> on ChangeNotifier
    implements Disposable, AsyncDisposable {
  CommandState<T, F> _state = CommandIdleState<T, F>();
  final Map<Future<CommandOutcome<T, F>>, Future<CommandExecution<T, F>>>
  _mapped = Map.identity();
  Future<void>? _disposal;
  var _disposed = false;
  var _notifierDisposed = false;
  DartitectDiagnosticSubject? _diagnostics;

  int get laneRunningCount;
  int get laneQueuedCount;
  bool get laneStopped;
  CommandConcurrency get laneConcurrency;
  CommandOutcome<T, F>? get laneLastOutcome;
  int? get laneLastOutcomeExecutionId;
  CommandLaneCrash? get laneLastCrash;
  int? get laneLatestAcceptedExecutionId;
  int get laneActiveKeyCount => 0;
  Future<void> closeLane();

  void initializeDiagnostics(DartitectDiagnosticSubject? diagnostics) {
    if (diagnostics != null &&
        diagnostics.kind != DartitectDiagnosticSubjectKind.command) {
      throw ArgumentError.value(
        diagnostics.kind,
        'diagnostics',
        'Commands require a command diagnostic subject.',
      );
    }
    _diagnostics = diagnostics;
  }

  /// Current exhaustive operation state.
  CommandState<T, F> get state => _state;

  /// Whether one or more accepted executions are still running.
  bool get isRunning => laneRunningCount > 0;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  void syncState() {
    if (_disposed) return;
    final runningCount = laneRunningCount;
    final queuedCount = laneQueuedCount;
    final admission = _admissionStatus();
    final latest = laneLatestAcceptedExecutionId;
    final terminalId = laneLastOutcomeExecutionId;
    final crash = laneLastCrash;
    final outcome = laneLastOutcome;
    final CommandState<T, F> next;
    if (crash != null && crash.executionId == terminalId) {
      next = CommandCrashState<T, F>(
        crash.error,
        crash.stackTrace,
        executionId: crash.executionId,
        runningCount: runningCount,
        queuedCount: queuedCount,
        admissionStatus: admission,
        latestAcceptedExecutionId: latest,
      );
    } else if (outcome case CommandSucceeded<T, F>(:final value)) {
      next = CommandSuccessState<T, F>(
        value,
        executionId: terminalId ?? 0,
        runningCount: runningCount,
        queuedCount: queuedCount,
        admissionStatus: admission,
        latestAcceptedExecutionId: latest,
      );
    } else if (outcome case CommandFailed<T, F>(
      :final failure,
      :final stackTrace,
    )) {
      next = CommandFailureState<T, F>(
        failure,
        stackTrace,
        executionId: terminalId ?? 0,
        runningCount: runningCount,
        queuedCount: queuedCount,
        admissionStatus: admission,
        latestAcceptedExecutionId: latest,
      );
    } else if (outcome case CommandCancelled<T, F>(:final reason)) {
      next = CommandCancelledState<T, F>(
        reason,
        executionId: terminalId ?? 0,
        runningCount: runningCount,
        queuedCount: queuedCount,
        admissionStatus: admission,
        latestAcceptedExecutionId: latest,
      );
    } else if (runningCount > 0 || queuedCount > 0) {
      next = CommandRunningState<T, F>(
        runningCount: runningCount,
        queuedCount: queuedCount,
        admissionStatus: admission,
        latestAcceptedExecutionId: latest,
      );
    } else {
      next = CommandIdleState<T, F>(
        admissionStatus: admission,
        latestAcceptedExecutionId: latest,
      );
    }
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  Future<CommandExecution<T, F>> mapOutcome(
    Future<CommandOutcome<T, F>> source,
  ) {
    final existing = _mapped[source];
    if (existing != null) return existing;
    final executionId = laneLatestAcceptedExecutionId;
    final mapped = source.then(
      (outcome) {
        final phase = switch (outcome) {
          CommandSucceeded<T, F>() => DartitectDiagnosticPhase.succeeded,
          CommandFailed<T, F>() => DartitectDiagnosticPhase.failed,
          CommandCancelled<T, F>() => DartitectDiagnosticPhase.cancelled,
          CommandRejected<T, F>() || CommandDropped<T, F>() => null,
        };
        if (phase != null) {
          _diagnostics?.emit(phase, revision: executionId ?? 0);
        }
        return switch (outcome) {
          CommandSucceeded<T, F>(:final value) =>
            CommandExecutionSucceeded<T, F>(
              value,
              executionId: executionId ?? 0,
            ),
          CommandFailed<T, F>(:final failure, :final stackTrace) =>
            CommandExecutionFailed<T, F>(
              failure,
              stackTrace,
              executionId: executionId ?? 0,
            ),
          CommandRejected<T, F>(:final reason) =>
            CommandExecutionRejected<T, F>(_rejection(reason)),
          CommandDropped<T, F>() => CommandExecutionDropped<T, F>(),
          CommandCancelled<T, F>(:final reason) =>
            CommandExecutionCancelled<T, F>(
              reason,
              executionId: executionId ?? 0,
            ),
        };
      },
      onError: (Object error, StackTrace stackTrace) {
        _diagnostics?.emit(
          DartitectDiagnosticPhase.crashed,
          revision: executionId ?? 0,
        );
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _mapped[source] = mapped;
    unawaited(
      mapped.then<void>(
        (_) {
          unawaited(
            _mapped
                .remove(source)
                ?.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
          );
        },
        onError: (Object _, StackTrace __) {
          unawaited(
            _mapped
                .remove(source)
                ?.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
          );
        },
      ),
    );
    return mapped;
  }

  CommandAdmissionStatus _admissionStatus() {
    if (_disposed) return CommandAdmissionStatus.disposed;
    if (laneStopped) return CommandAdmissionStatus.stopped;
    final concurrency = laneConcurrency;
    if (concurrency.kind == CommandConcurrencyKind.keyed) {
      if (laneActiveKeyCount >= concurrency.maxConcurrent) {
        return CommandAdmissionStatus.keyLimit;
      }
      return CommandAdmissionStatus.accepting;
    }
    return switch (concurrency.kind) {
      CommandConcurrencyKind.reject ||
      CommandConcurrencyKind.join ||
      CommandConcurrencyKind.drop =>
        laneRunningCount > 0
            ? CommandAdmissionStatus.busy
            : CommandAdmissionStatus.accepting,
      CommandConcurrencyKind.sequential =>
        laneRunningCount > 0 && laneQueuedCount >= concurrency.maxQueue
            ? CommandAdmissionStatus.queueFull
            : CommandAdmissionStatus.accepting,
      CommandConcurrencyKind.restartLatest => CommandAdmissionStatus.accepting,
      CommandConcurrencyKind.concurrent =>
        laneRunningCount >= concurrency.maxConcurrent
            ? CommandAdmissionStatus.concurrentLimit
            : CommandAdmissionStatus.accepting,
      CommandConcurrencyKind.keyed => CommandAdmissionStatus.accepting,
    };
  }

  Future<void> _beginDisposal() {
    final existing = _disposal;
    if (existing != null) return existing;
    final completer = Completer<void>();
    _disposal = completer.future;
    _disposed = true;
    _mapped.clear();
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    unawaited(() async {
      try {
        await closeLane();
        _diagnostics?.emit(DartitectDiagnosticPhase.disposed);
        completer.complete();
      } catch (error, stackTrace) {
        _diagnostics?.emit(DartitectDiagnosticPhase.crashed);
        _diagnostics?.emit(DartitectDiagnosticPhase.disposed);
        completer.completeError(error, stackTrace);
      }
    }());
    return completer.future;
  }

  @override
  Future<void> disposeAsync() => _beginDisposal();

  @override
  void dispose() {
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    unawaited(_beginDisposal());
  }
}

/// Policy-aware no-argument ViewModel action.
final class Command0<T, F extends Object> extends ChangeNotifier
    with _CommandBinding<T, F> {
  /// Creates a command whose action does not observe cancellation.
  Command0(
    Future<Result<T, F>> Function() action, {
    this.concurrency = const CommandConcurrency.reject(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    DartitectDiagnosticSubject? diagnostics,
  }) : _action = ((_) => action()) {
    initializeDiagnostics(diagnostics);
    _createLane(reporter);
  }

  /// Creates a command whose action observes cooperative cancellation.
  Command0.cancellable(
    Future<Result<T, F>> Function(CancellationSignal signal) action, {
    this.concurrency = const CommandConcurrency.reject(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    DartitectDiagnosticSubject? diagnostics,
  }) : _action = action {
    initializeDiagnostics(diagnostics);
    _createLane(reporter);
  }

  final Future<Result<T, F>> Function(CancellationSignal signal) _action;
  late final CommandLane<T, F> _lane;

  /// Selected bounded scheduling policy.
  final CommandConcurrency concurrency;

  void _createLane(CommandCrashReporter reporter) {
    _lane = CommandLane<T, F>(
      action: _action,
      concurrency: concurrency,
      reporter: reporter,
      onChanged: syncState,
    );
  }

  /// Executes according to [concurrency].
  Future<CommandExecution<T, F>> execute() => mapOutcome(_lane.execute());

  /// Explicitly executes the same action again through the same policy.
  Future<CommandExecution<T, F>> retry() => execute();

  /// Requests cooperative cancellation of every running execution.
  bool cancel([Object reason = 'Command cancelled']) =>
      _lane.cancel(reason) > 0;

  /// Clears retained terminal state only while fully idle.
  bool reset() => _lane.resetTerminal();

  /// Reopens a lane stopped by an unexpected crash.
  void resume() => _lane.resume();

  @override
  int get laneRunningCount => _lane.runningCount;
  @override
  int get laneQueuedCount => _lane.queuedCount;
  @override
  bool get laneStopped => _lane.isStopped;
  @override
  CommandConcurrency get laneConcurrency => concurrency;
  @override
  CommandOutcome<T, F>? get laneLastOutcome => _lane.lastOutcome;
  @override
  int? get laneLastOutcomeExecutionId => _lane.lastOutcomeExecutionId;
  @override
  CommandLaneCrash? get laneLastCrash => _lane.lastCrash;
  @override
  int? get laneLatestAcceptedExecutionId => _lane.latestAcceptedExecutionId;
  @override
  Future<void> closeLane() => _lane.dispose();
}

/// Policy-aware one-argument ViewModel action.
///
/// `join` accepts only an argument equal to the running argument. Use a record
/// as [A] for multiple logical arguments.
final class Command1<A, T, F extends Object> extends ChangeNotifier
    with _CommandBinding<T, F> {
  /// Creates a command whose action does not observe cancellation.
  Command1(
    Future<Result<T, F>> Function(A argument) action, {
    this.concurrency = const CommandConcurrency.reject(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    DartitectDiagnosticSubject? diagnostics,
  }) : _action = ((argument, _) => action(argument)) {
    initializeDiagnostics(diagnostics);
    _createLane(reporter);
  }

  /// Creates a command whose action observes cooperative cancellation.
  Command1.cancellable(
    Future<Result<T, F>> Function(A argument, CancellationSignal signal)
    action, {
    this.concurrency = const CommandConcurrency.reject(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    DartitectDiagnosticSubject? diagnostics,
  }) : _action = action {
    initializeDiagnostics(diagnostics);
    _createLane(reporter);
  }

  static final Object _key = Object();
  final Future<Result<T, F>> Function(A, CancellationSignal) _action;
  late final KeyedCommandLane<Object, A, T, F> _lane;

  /// Selected bounded per-command policy.
  final CommandConcurrency concurrency;

  void _createLane(CommandCrashReporter reporter) {
    if (concurrency.kind == CommandConcurrencyKind.keyed) {
      throw ArgumentError.value(
        concurrency,
        'concurrency',
        'Use KeyedCommand1 for keyed scheduling.',
      );
    }
    _lane = KeyedCommandLane<Object, A, T, F>(
      action: (_, argument, signal) => _action(argument, signal),
      concurrency: CommandConcurrency.keyed(
        perKey: concurrency,
        maxConcurrent: 1,
      ),
      reporter: reporter,
      onChanged: syncState,
    );
  }

  /// Executes [argument] according to [concurrency].
  Future<CommandExecution<T, F>> execute(A argument) =>
      mapOutcome(_lane.execute(_key, argument));

  /// Requests cooperative cancellation of running work.
  bool cancel([Object reason = 'Command cancelled']) =>
      _lane.cancelKey(_key, reason) > 0;

  /// Clears retained terminal state only while fully idle.
  bool reset() => _lane.resetTerminal();

  /// Reopens the command after an unexpected crash.
  void resume() => _lane.resume(_key);

  @override
  int get laneRunningCount => _lane.runningCount;
  @override
  int get laneQueuedCount => _lane.queuedCount;
  @override
  bool get laneStopped => _lane.stoppedKeyCount > 0;
  @override
  CommandConcurrency get laneConcurrency => concurrency;
  @override
  CommandOutcome<T, F>? get laneLastOutcome => _lane.lastOutcome;
  @override
  int? get laneLastOutcomeExecutionId => _lane.lastOutcomeExecutionId;
  @override
  CommandLaneCrash? get laneLastCrash => _lane.lastCrash;
  @override
  int? get laneLatestAcceptedExecutionId => _lane.latestAcceptedExecutionId;
  @override
  Future<void> closeLane() => _lane.dispose();
}

/// Dedicated bounded keyed command with independent per-key scheduling.
final class KeyedCommand1<K, A, T, F extends Object> extends ChangeNotifier
    with _CommandBinding<T, F> {
  /// Creates a keyed command.
  KeyedCommand1(
    Future<Result<T, F>> Function(K key, A argument, CancellationSignal signal)
    action, {
    this.concurrency = const CommandConcurrency.keyed(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    DartitectDiagnosticSubject? diagnostics,
  }) : _action = action {
    initializeDiagnostics(diagnostics);
    _lane = KeyedCommandLane<K, A, T, F>(
      action: _action,
      concurrency: concurrency,
      reporter: reporter,
      onChanged: syncState,
    );
  }

  final Future<Result<T, F>> Function(
    K key,
    A argument,
    CancellationSignal signal,
  )
  _action;
  late final KeyedCommandLane<K, A, T, F> _lane;

  /// Key and per-key policies with positive bounds.
  final CommandConcurrency concurrency;

  /// Executes [argument] in the lane identified by [key].
  Future<CommandExecution<T, F>> execute(K key, A argument) =>
      mapOutcome(_lane.execute(key, argument));

  /// Requests cooperative cancellation for one key.
  bool cancelKey(K key, [Object reason = 'Keyed command cancelled']) =>
      _lane.cancelKey(key, reason) > 0;

  /// Requests cooperative cancellation for all keys.
  int cancelAll([Object reason = 'Keyed command cancelled']) =>
      _lane.cancelAll(reason);

  /// Reopens [key] after its unexpected crash has drained.
  void resume(K key) => _lane.resume(key);

  /// Clears aggregate retained terminal state only while fully idle.
  bool reset() => _lane.resetTerminal();

  /// Keys with currently running work. Key values are never exposed.
  int get activeKeyCount => _lane.activeKeyCount;

  @override
  int get laneRunningCount => _lane.runningCount;
  @override
  int get laneQueuedCount => _lane.queuedCount;
  @override
  bool get laneStopped => _lane.stoppedKeyCount > 0;
  @override
  CommandConcurrency get laneConcurrency => concurrency;
  @override
  int get laneActiveKeyCount => _lane.activeKeyCount;
  @override
  CommandOutcome<T, F>? get laneLastOutcome => _lane.lastOutcome;
  @override
  int? get laneLastOutcomeExecutionId => _lane.lastOutcomeExecutionId;
  @override
  CommandLaneCrash? get laneLastCrash => _lane.lastCrash;
  @override
  int? get laneLatestAcceptedExecutionId => _lane.latestAcceptedExecutionId;
  @override
  Future<void> closeLane() => _lane.dispose();
}

CommandRejectionReason _rejection(CommandLaneRejectionReason reason) =>
    switch (reason) {
      CommandLaneRejectionReason.busy => CommandRejectionReason.busy,
      CommandLaneRejectionReason.queueFull => CommandRejectionReason.queueFull,
      CommandLaneRejectionReason.concurrentLimit =>
        CommandRejectionReason.concurrentLimit,
      CommandLaneRejectionReason.keyLimit => CommandRejectionReason.keyLimit,
      CommandLaneRejectionReason.laneStopped =>
        CommandRejectionReason.laneStopped,
      CommandLaneRejectionReason.disposed => CommandRejectionReason.disposed,
    };
