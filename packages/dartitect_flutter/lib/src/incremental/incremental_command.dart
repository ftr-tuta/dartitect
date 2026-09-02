import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect/dartitect_incremental.dart';
import 'package:flutter/foundation.dart';

import '../command/command.dart';
import '../reactive/live_resource.dart';

/// Notification cadence for non-terminal incremental state changes.
enum IncrementalPublication {
  /// Notifies after execution start and every admitted item.
  everyEmission,

  /// Coalesces non-terminal notifications into one microtask.
  coalesceMicrotask,

  /// Coalesces non-terminal notifications into one scheduled frame.
  coalesceFrame,
}

/// Projects one reduced item into consumer-defined progress.
typedef IncrementalProgressOf<Item, Aggregate, Progress> = Progress Function(
  Item item,
  Aggregate aggregate,
  IncrementalItemContext context,
);

/// Payload-free terminal category retained by a command receipt.
enum IncrementalCommandTerminalKind {
  /// Producer and consumer completed successfully.
  succeeded,

  /// Producer returned an expected typed failure.
  failed,

  /// Execution was cooperatively cancelled or reached its deadline.
  cancelled,

  /// Producer, reducer, projector, consumer, or invariant crashed.
  crashed,
}

/// Payload-free receipt for one terminal incremental execution.
final class IncrementalCommandReceipt {
  /// Creates immutable terminal accounting without aggregate or item payloads.
  const IncrementalCommandReceipt({
    required this.executionId,
    required this.emissionCount,
    required this.totalWeight,
    required this.terminalKind,
  });

  /// Positive command-local execution identity.
  final int executionId;

  /// Number of successfully reduced items.
  final int emissionCount;

  /// Sum of successfully reduced item weights.
  final int totalWeight;

  /// Terminal control category.
  final IncrementalCommandTerminalKind terminalKind;
}

/// Exhaustive Material-neutral state of one incremental command.
sealed class IncrementalCommandState<
  Aggregate,
  Failure extends Object,
  Progress
> {
  const IncrementalCommandState({
    required this.aggregate,
    required this.emissionCount,
    required this.totalWeight,
    required this.executionId,
    required this.hasProgress,
    required this.latestProgress,
    required this.receipt,
  });

  /// Current aggregate, including partial terminal work.
  final Aggregate aggregate;

  /// Successfully reduced item count.
  final int emissionCount;

  /// Cumulative successfully reduced item weight.
  final int totalWeight;

  /// Positive execution identity, or zero before the first execution.
  final int executionId;

  /// Whether at least one progress value was projected.
  final bool hasProgress;

  /// Latest projected progress when [hasProgress] is true.
  final Progress? latestProgress;

  /// Payload-free receipt for terminal states.
  final IncrementalCommandReceipt? receipt;

  /// Exhaustively reduces every state variant.
  R match<R>({
    required R Function(IncrementalCommandIdle<Aggregate, Failure, Progress>)
    idle,
    required R Function(IncrementalCommandRunning<Aggregate, Failure, Progress>)
    running,
    required R Function(
      IncrementalCommandSucceeded<Aggregate, Failure, Progress>,
    )
    succeeded,
    required R Function(IncrementalCommandFailed<Aggregate, Failure, Progress>)
    failed,
    required R Function(
      IncrementalCommandCancelled<Aggregate, Failure, Progress>,
    )
    cancelled,
    required R Function(IncrementalCommandCrashed<Aggregate, Failure, Progress>)
    crashed,
  }) => switch (this) {
    final IncrementalCommandIdle<Aggregate, Failure, Progress> state => idle(
      state,
    ),
    final IncrementalCommandRunning<Aggregate, Failure, Progress> state =>
      running(state),
    final IncrementalCommandSucceeded<Aggregate, Failure, Progress> state =>
      succeeded(state),
    final IncrementalCommandFailed<Aggregate, Failure, Progress> state =>
      failed(state),
    final IncrementalCommandCancelled<Aggregate, Failure, Progress> state =>
      cancelled(state),
    final IncrementalCommandCrashed<Aggregate, Failure, Progress> state =>
      crashed(state),
  };
}

/// No incremental execution has started since construction or reset.
final class IncrementalCommandIdle<Aggregate, Failure extends Object, Progress>
    extends IncrementalCommandState<Aggregate, Failure, Progress> {
  /// Creates an idle state around a fresh initial aggregate.
  const IncrementalCommandIdle({required super.aggregate})
    : super(
        emissionCount: 0,
        totalWeight: 0,
        executionId: 0,
        hasProgress: false,
        latestProgress: null,
        receipt: null,
      );
}

/// One accepted execution is publishing its current partial aggregate.
final class IncrementalCommandRunning<
  Aggregate,
  Failure extends Object,
  Progress
>
    extends IncrementalCommandState<Aggregate, Failure, Progress> {
  /// Creates a running state.
  const IncrementalCommandRunning({
    required super.aggregate,
    required super.emissionCount,
    required super.totalWeight,
    required super.executionId,
    required super.hasProgress,
    required super.latestProgress,
  }) : super(receipt: null);
}

/// The latest current execution completed successfully.
final class IncrementalCommandSucceeded<
  Aggregate,
  Failure extends Object,
  Progress
>
    extends IncrementalCommandState<Aggregate, Failure, Progress> {
  /// Creates a successful terminal state.
  const IncrementalCommandSucceeded({
    required super.aggregate,
    required super.emissionCount,
    required super.totalWeight,
    required super.executionId,
    required super.hasProgress,
    required super.latestProgress,
    required IncrementalCommandReceipt super.receipt,
  });
}

/// The producer returned its first expected typed failure.
final class IncrementalCommandFailed<
  Aggregate,
  Failure extends Object,
  Progress
>
    extends IncrementalCommandState<Aggregate, Failure, Progress> {
  /// Creates an expected-failure terminal state with partial aggregate.
  const IncrementalCommandFailed({
    required this.failure,
    required this.stackTrace,
    required super.aggregate,
    required super.emissionCount,
    required super.totalWeight,
    required super.executionId,
    required super.hasProgress,
    required super.latestProgress,
    required IncrementalCommandReceipt super.receipt,
  });

  /// Original expected failure.
  final Failure failure;

  /// Stack retained by the producer's [Err].
  final StackTrace stackTrace;
}

/// The latest current execution was cooperatively cancelled.
final class IncrementalCommandCancelled<
  Aggregate,
  Failure extends Object,
  Progress
>
    extends IncrementalCommandState<Aggregate, Failure, Progress> {
  /// Creates a cancelled terminal state with partial aggregate.
  const IncrementalCommandCancelled({
    required this.reason,
    required super.aggregate,
    required super.emissionCount,
    required super.totalWeight,
    required super.executionId,
    required super.hasProgress,
    required super.latestProgress,
    required IncrementalCommandReceipt super.receipt,
  });

  /// Cancellation or deadline reason.
  final Object? reason;
}

/// The latest current execution crashed unexpectedly.
final class IncrementalCommandCrashed<
  Aggregate,
  Failure extends Object,
  Progress
>
    extends IncrementalCommandState<Aggregate, Failure, Progress> {
  /// Creates a crash terminal state with original stack and partial aggregate.
  const IncrementalCommandCrashed({
    required this.error,
    required this.stackTrace,
    required super.aggregate,
    required super.emissionCount,
    required super.totalWeight,
    required super.executionId,
    required super.hasProgress,
    required super.latestProgress,
    required IncrementalCommandReceipt super.receipt,
  });

  /// Original unexpected error.
  final Object error;

  /// Original unexpected stack trace.
  final StackTrace stackTrace;
}

/// No-argument Flutter projection of one bounded incremental operation.
final class IncrementalCommand<
  Item,
  Aggregate,
  Failure extends Object,
  Progress
>
    extends ChangeNotifier
    implements
        AsyncDisposable,
        ValueListenable<IncrementalCommandState<Aggregate, Failure, Progress>> {
  /// Creates a command whose producer remains cold until lane admission.
  IncrementalCommand({
    required IncrementalOperation<Item, Failure> operation,
    required Aggregate Function() initialAggregate,
    required IncrementalReducer<Aggregate, Item> reducer,
    required IncrementalProgressOf<Item, Aggregate, Progress> progressOf,
    this.concurrency = const CommandConcurrency.reject(),
    this.publication = IncrementalPublication.everyEmission,
    SourceFrameScheduler frameScheduler = const FlutterSourceFrameScheduler(),
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
  }) : _operation = operation,
       _initialAggregate = initialAggregate,
       _reducer = reducer,
       _progressOf = progressOf,
       _frameScheduler = frameScheduler,
       _state = IncrementalCommandIdle<Aggregate, Failure, Progress>(
         aggregate: initialAggregate(),
       ) {
    _command = Command0<IncrementalCommandReceipt, Failure>.cancellable(
      _runExecution,
      concurrency: concurrency,
      reporter: reporter,
    )..addListener(_commandChanged);
  }

  final IncrementalOperation<Item, Failure> _operation;
  final Aggregate Function() _initialAggregate;
  final IncrementalReducer<Aggregate, Item> _reducer;
  final IncrementalProgressOf<Item, Aggregate, Progress> _progressOf;
  final SourceFrameScheduler _frameScheduler;

  /// Bounded admission policy shared with ordinary and progress commands.
  final CommandConcurrency concurrency;

  /// Notification cadence; reduction itself is never coalesced.
  final IncrementalPublication publication;

  late final Command0<IncrementalCommandReceipt, Failure> _command;
  final Map<int, _IncrementalDraft<Aggregate, Progress>> _drafts =
      <int, _IncrementalDraft<Aggregate, Progress>>{};
  final Map<
    Future<CommandExecution<IncrementalCommandReceipt, Failure>>,
    Future<CommandExecution<IncrementalCommandReceipt, Failure>>
  >
  _mapped = Map.identity();
  IncrementalCommandState<Aggregate, Failure, Progress> _state;
  var _startedExecutionId = 0;
  var _latestStartedExecutionId = 0;
  var _notificationGeneration = 0;
  var _notificationScheduled = false;
  var _disposed = false;
  var _notifierDisposed = false;
  Future<void>? _disposal;

  /// Current exhaustive incremental state.
  IncrementalCommandState<Aggregate, Failure, Progress> get state => _state;

  /// Current exhaustive incremental state as a [ValueListenable] value.
  @override
  IncrementalCommandState<Aggregate, Failure, Progress> get value => state;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Whether the shared command lane has active work.
  bool get isRunning => _command.isRunning;

  /// Executes a fresh producer and aggregate through [concurrency].
  Future<CommandExecution<IncrementalCommandReceipt, Failure>> execute() {
    if (_disposed) {
      return Future<CommandExecution<IncrementalCommandReceipt, Failure>>.value(
        CommandExecutionRejected<IncrementalCommandReceipt, Failure>(
          CommandRejectionReason.disposed,
        ),
      );
    }
    final source = _command.execute();
    final existing = _mapped[source];
    if (existing != null) return existing;
    final mapped = source.then((result) async {
      if (result
          case CommandExecutionCancelled<IncrementalCommandReceipt, Failure>(
            :final executionId,
          )) {
        await _drafts[executionId]?.drained.future;
      }
      return result;
    });
    _mapped[source] = mapped;
    void removeMapped() => _mapped.remove(source)?.ignore();
    mapped
        .then<void>(
          (_) => removeMapped(),
          onError: (Object _, StackTrace __) => removeMapped(),
        )
        .ignore();
    return mapped;
  }

  /// Requests cooperative cancellation and waits through [execute]'s future.
  bool cancel([Object reason = 'Incremental command cancelled']) =>
      _command.cancel(reason);

  /// Reopens a lane stopped by an unexpected crash.
  void resume() => _command.resume();

  /// Clears an idle terminal and creates a fresh initial aggregate.
  bool reset() {
    if (!_command.reset()) return false;
    _notificationGeneration += 1;
    _notificationScheduled = false;
    _state = IncrementalCommandIdle<Aggregate, Failure, Progress>(
      aggregate: _initialAggregate(),
    );
    notifyListeners();
    return true;
  }

  Future<Result<IncrementalCommandReceipt, Failure>> _runExecution(
    CancellationSignal cancellation,
  ) async {
    final executionId = ++_startedExecutionId;
    _latestStartedExecutionId = executionId;
    final draft = _IncrementalDraft<Aggregate, Progress>(
      executionId,
      _initialAggregate(),
    );
    _drafts[executionId] = draft;
    _notificationGeneration += 1;
    _notificationScheduled = false;
    _publishRunning(draft);
    try {
      final result = await _operation.consume(
        cancellation: cancellation,
        onValue: (item, context) {
          final aggregate = _reducer(draft.aggregate, item, context);
          draft
            ..aggregate = aggregate
            ..emissionCount = context.sequence
            ..totalWeight = context.cumulativeWeight;
          final progress = _progressOf(item, aggregate, context);
          draft
            ..latestProgress = progress
            ..hasProgress = true;
          if (executionId == _latestStartedExecutionId) {
            _publishRunning(draft);
          }
        },
      );
      switch (result.outcome) {
        case Ok<void>():
          final receipt = draft.receipt(
            IncrementalCommandTerminalKind.succeeded,
          );
          draft.receiptValue = receipt;
          return Ok<IncrementalCommandReceipt>(receipt);
        case Err<Object>(:final failure, :final stackTrace):
          draft.receiptValue = draft.receipt(
            IncrementalCommandTerminalKind.failed,
          );
          return Err<Failure>(failure as Failure, stackTrace);
      }
    } on OperationDeadlineExceededException catch (error) {
      throw CancellationException(error);
    } finally {
      if (!draft.drained.isCompleted) draft.drained.complete();
    }
  }

  void _commandChanged() {
    if (_disposed) return;
    final commandState = _command.state;
    final terminalId = commandState.terminalExecutionId;
    if (terminalId == null || terminalId <= 0) return;
    final draft = _drafts[terminalId];
    if (draft == null || terminalId < _latestStartedExecutionId) return;
    switch (commandState) {
      case CommandSuccessState<IncrementalCommandReceipt, Failure>(
        :final value,
      ):
        _publishTerminal(
          IncrementalCommandSucceeded<Aggregate, Failure, Progress>(
            aggregate: draft.aggregate,
            emissionCount: draft.emissionCount,
            totalWeight: draft.totalWeight,
            executionId: terminalId,
            hasProgress: draft.hasProgress,
            latestProgress: draft.latestProgress,
            receipt: value,
          ),
        );
      case CommandFailureState<IncrementalCommandReceipt, Failure>(
        :final failure,
        :final stackTrace,
      ):
        final receipt =
            draft.receiptValue ??
            draft.receipt(IncrementalCommandTerminalKind.failed);
        _publishTerminal(
          IncrementalCommandFailed<Aggregate, Failure, Progress>(
            failure: failure,
            stackTrace: stackTrace,
            aggregate: draft.aggregate,
            emissionCount: draft.emissionCount,
            totalWeight: draft.totalWeight,
            executionId: terminalId,
            hasProgress: draft.hasProgress,
            latestProgress: draft.latestProgress,
            receipt: receipt,
          ),
        );
      case CommandCancelledState<IncrementalCommandReceipt, Failure>(
        :final reason,
      ):
        if (draft.terminalScheduled) return;
        draft.terminalScheduled = true;
        unawaited(
          draft.drained.future.then((_) {
            if (_disposed || terminalId != _latestStartedExecutionId) return;
            _publishTerminal(
              IncrementalCommandCancelled<Aggregate, Failure, Progress>(
                reason: reason,
                aggregate: draft.aggregate,
                emissionCount: draft.emissionCount,
                totalWeight: draft.totalWeight,
                executionId: terminalId,
                hasProgress: draft.hasProgress,
                latestProgress: draft.latestProgress,
                receipt: draft.receipt(
                  IncrementalCommandTerminalKind.cancelled,
                ),
              ),
            );
          }),
        );
      case CommandCrashState<IncrementalCommandReceipt, Failure>(
        :final error,
        :final stackTrace,
      ):
        _publishTerminal(
          IncrementalCommandCrashed<Aggregate, Failure, Progress>(
            error: error,
            stackTrace: stackTrace,
            aggregate: draft.aggregate,
            emissionCount: draft.emissionCount,
            totalWeight: draft.totalWeight,
            executionId: terminalId,
            hasProgress: draft.hasProgress,
            latestProgress: draft.latestProgress,
            receipt: draft.receipt(IncrementalCommandTerminalKind.crashed),
          ),
        );
      case CommandIdleState<IncrementalCommandReceipt, Failure>() ||
          CommandRunningState<IncrementalCommandReceipt, Failure>():
        return;
    }
  }

  void _publishRunning(_IncrementalDraft<Aggregate, Progress> draft) {
    if (_disposed || draft.executionId != _latestStartedExecutionId) return;
    _state = IncrementalCommandRunning<Aggregate, Failure, Progress>(
      aggregate: draft.aggregate,
      emissionCount: draft.emissionCount,
      totalWeight: draft.totalWeight,
      executionId: draft.executionId,
      hasProgress: draft.hasProgress,
      latestProgress: draft.latestProgress,
    );
    _scheduleNonTerminalNotification();
  }

  void _scheduleNonTerminalNotification() {
    switch (publication) {
      case IncrementalPublication.everyEmission:
        notifyListeners();
      case IncrementalPublication.coalesceMicrotask:
        _scheduleNotification(schedule: scheduleMicrotask);
      case IncrementalPublication.coalesceFrame:
        _scheduleNotification(schedule: _frameScheduler.schedule);
    }
  }

  void _scheduleNotification({
    required void Function(VoidCallback callback) schedule,
  }) {
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    final generation = _notificationGeneration;
    schedule(() {
      if (_disposed || generation != _notificationGeneration) return;
      _notificationScheduled = false;
      notifyListeners();
    });
  }

  void _publishTerminal(
    IncrementalCommandState<Aggregate, Failure, Progress> terminal,
  ) {
    if (_disposed || terminal.executionId != _latestStartedExecutionId) return;
    _state = terminal;
    _notificationGeneration += 1;
    _notificationScheduled = false;
    notifyListeners();
  }

  Future<void> _beginDisposal() {
    final existing = _disposal;
    if (existing != null) return existing;
    _disposed = true;
    _notificationGeneration += 1;
    _notificationScheduled = false;
    _mapped.clear();
    _command.removeListener(_commandChanged);
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    return _disposal = _command.disposeAsync().whenComplete(_drafts.clear);
  }

  @override
  Future<void> disposeAsync() => _beginDisposal();

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _notifierDisposed = true;
    super.dispose();
    unawaited(_beginDisposal());
  }
}

final class _IncrementalDraft<Aggregate, Progress> {
  _IncrementalDraft(this.executionId, this.aggregate);

  final int executionId;
  Aggregate aggregate;
  var emissionCount = 0;
  var totalWeight = 0;
  var hasProgress = false;
  Progress? latestProgress;
  IncrementalCommandReceipt? receiptValue;
  final Completer<void> drained = Completer<void>();
  var terminalScheduled = false;

  IncrementalCommandReceipt receipt(IncrementalCommandTerminalKind kind) =>
      IncrementalCommandReceipt(
        executionId: executionId,
        emissionCount: emissionCount,
        totalWeight: totalWeight,
        terminalKind: kind,
      );
}
