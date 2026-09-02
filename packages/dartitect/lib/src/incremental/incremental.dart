import 'dart:async';

import '../concurrency/cancellation.dart';
import '../concurrency/operation_progress.dart'
    show OperationDeadlineExceededException;
import '../result.dart';

/// Creates one fresh finite, resource-free synchronous producer per execution.
///
/// A plain [Iterator] has no cancellation or close protocol. Use this only for
/// finite iterables that own no resource, or use
/// [CloseableSyncIncrementalProducer] instead.
typedef SyncIncrementalProducer<Item, Failure extends Object> =
    Iterable<Result<Item, Failure>> Function();

/// Creates one fresh cold single-subscription stream per execution.
typedef AsyncIncrementalProducer<Item, Failure extends Object> =
    Stream<Result<Item, Failure>> Function();

/// Computes the non-negative admission weight of one successful item.
typedef IncrementalWeightOf<Item> = int Function(Item item);

/// Applies one admitted item to an explicit aggregate.
typedef IncrementalReducer<Aggregate, Item> = Aggregate Function(
  Aggregate aggregate,
  Item item,
  IncrementalItemContext context,
);

/// Creates one fresh owned synchronous source per execution.
typedef CloseableSyncIncrementalProducer<Item, Failure extends Object> =
    CloseableSyncIncrementalSource<Item, Failure> Function();

/// Owned synchronous source with an explicit exact-once cleanup boundary.
abstract interface class CloseableSyncIncrementalSource<
  Item,
  Failure extends Object
> {
  /// Iterator pulled only after the previous consumer callback completes.
  Iterator<Result<Item, Failure>> get iterator;

  /// Releases source-owned resources after every terminal path.
  FutureOr<void> close();
}

/// Per-execution admission bounds.
final class IncrementalLimits {
  /// Declares item and weight limits validated by an operation at runtime.
  const IncrementalLimits({
    this.maxEmissions = 100000,
    this.maxWeight = 100000,
  });

  /// Maximum admitted successful emissions.
  final int maxEmissions;

  /// Maximum cumulative admitted weight.
  final int maxWeight;

  void _validate() {
    if (maxEmissions <= 0) {
      throw ArgumentError.value(
        maxEmissions,
        'limits.maxEmissions',
        'Must be positive.',
      );
    }
    if (maxWeight <= 0) {
      throw ArgumentError.value(
        maxWeight,
        'limits.maxWeight',
        'Must be positive.',
      );
    }
  }
}

/// Immutable context for one admitted successful item.
final class IncrementalItemContext {
  /// Creates a one-based, execution-scoped item context.
  const IncrementalItemContext({
    required this.executionId,
    required this.sequence,
    required this.weight,
    required this.cumulativeWeight,
    required this.timestamp,
  });

  /// Positive operation-local execution identity.
  final int executionId;

  /// One-based emission sequence.
  final int sequence;

  /// Non-negative weight of this item.
  final int weight;

  /// Cumulative weight including this item.
  final int cumulativeWeight;

  /// Injected UTC timestamp captured before consumer delivery.
  final DateTime timestamp;
}

/// Reason one incremental execution stopped producing values.
enum IncrementalTerminalKind {
  /// The producer completed normally.
  completed,

  /// The producer returned its first typed [Err].
  failed,

  /// Admission stopped before an item would exceed a configured limit.
  limitExceeded,
}

/// Payload-free execution accounting.
final class IncrementalReport {
  /// Creates one immutable terminal report.
  const IncrementalReport({
    required this.executionId,
    required this.emissionCount,
    required this.totalWeight,
    required this.startedAt,
    required this.finishedAt,
    required this.terminalKind,
  });

  /// Positive operation-local execution identity.
  final int executionId;

  /// Number of items admitted to the consumer.
  final int emissionCount;

  /// Sum of admitted item weights.
  final int totalWeight;

  /// Injected UTC execution start.
  final DateTime startedAt;

  /// Injected UTC instant captured immediately before terminal publication.
  final DateTime finishedAt;

  /// Terminal category represented by this report.
  final IncrementalTerminalKind terminalKind;

  /// Elapsed time according to the injected clock.
  Duration get elapsed {
    final duration = finishedAt.difference(startedAt);
    return duration.isNegative ? Duration.zero : duration;
  }
}

/// Base type for bounded-admission failures.
sealed class IncrementalLimitExceededException implements Exception {
  const IncrementalLimitExceededException(this.report);

  /// Partial report excluding the rejected item.
  final IncrementalReport report;
}

/// The next item would exceed the emission-count bound.
final class IncrementalEmissionLimitExceededException
    extends IncrementalLimitExceededException {
  /// Creates an emission-bound failure.
  const IncrementalEmissionLimitExceededException({
    required this.limit,
    required this.attemptedSequence,
    required IncrementalReport report,
  }) : super(report);

  /// Configured maximum emission count.
  final int limit;

  /// One-based sequence rejected before consumer delivery.
  final int attemptedSequence;

  @override
  String toString() =>
      'IncrementalEmissionLimitExceededException('
      'limit: $limit, attemptedSequence: $attemptedSequence)';
}

/// The next item would exceed the cumulative-weight bound.
final class IncrementalWeightLimitExceededException
    extends IncrementalLimitExceededException {
  /// Creates a weight-bound failure.
  const IncrementalWeightLimitExceededException({
    required this.limit,
    required this.itemWeight,
    required this.attemptedWeight,
    required IncrementalReport report,
  }) : super(report);

  /// Configured maximum cumulative weight.
  final int limit;

  /// Weight of the rejected item.
  final int itemWeight;

  /// Cumulative weight that would have resulted from admission.
  final int attemptedWeight;

  @override
  String toString() =>
      'IncrementalWeightLimitExceededException('
      'limit: $limit, itemWeight: $itemWeight, '
      'attemptedWeight: $attemptedWeight)';
}

/// A producer returned a broadcast stream where a cold source was required.
final class IncrementalBroadcastStreamException implements Exception {
  /// Creates the stream-shape failure.
  const IncrementalBroadcastStreamException();

  @override
  String toString() =>
      'IncrementalBroadcastStreamException('
      'The producer must return a cold single-subscription stream.)';
}

/// An owned source failed while its terminal cleanup was being awaited.
final class IncrementalCleanupException implements Exception {
  /// Creates a cleanup failure while retaining any preceding terminal error.
  const IncrementalCleanupException({
    required this.error,
    required this.stackTrace,
    this.primaryError,
    this.primaryStackTrace,
  });

  /// Original cleanup error.
  final Object error;

  /// Original cleanup stack trace.
  final StackTrace stackTrace;

  /// Error that caused cleanup, when cleanup was secondary.
  final Object? primaryError;

  /// Original stack for [primaryError], when present.
  final StackTrace? primaryStackTrace;

  @override
  String toString() => 'IncrementalCleanupException($error)';
}

/// Typed consume terminal plus payload-free accounting.
final class IncrementalConsumeResult<Failure extends Object> {
  /// Creates a consume result.
  const IncrementalConsumeResult({required this.outcome, required this.report});

  /// Success or the producer's first expected failure.
  final Result<void, Failure> outcome;

  /// Execution accounting through the terminal boundary.
  final IncrementalReport report;
}

/// Explicit aggregate, typed terminal, and accounting returned by `fold`.
final class IncrementalFoldResult<Aggregate, Failure extends Object> {
  /// Creates a fold result without retaining emitted items.
  const IncrementalFoldResult({
    required this.aggregate,
    required this.outcome,
    required this.report,
  });

  /// Final or partial aggregate produced before the terminal.
  final Aggregate aggregate;

  /// Success or the producer's first expected failure.
  final Result<void, Failure> outcome;

  /// Execution accounting through the terminal boundary.
  final IncrementalReport report;
}

/// Explicit bounded items, typed terminal, and accounting returned by collect.
final class IncrementalCollectResult<Item, Failure extends Object> {
  /// Creates a bounded collection result.
  const IncrementalCollectResult({
    required this.items,
    required this.droppedItemCount,
    required this.outcome,
    required this.report,
  });

  /// Immutable retained suffix in producer order.
  final List<Item> items;

  /// Number of older admitted items overwritten by the bound.
  final int droppedItemCount;

  /// Success or the producer's first expected failure.
  final Result<void, Failure> outcome;

  /// Execution accounting through the terminal boundary.
  final IncrementalReport report;
}

/// Fixed-capacity ordered ring that never grows after construction.
final class BoundedRingBuffer<T> {
  /// Creates a ring with a positive [capacity].
  BoundedRingBuffer(this.capacity)
    : _storage = List<Object?>.filled(_validateCapacity(capacity), null);

  /// Maximum retained value count.
  final int capacity;

  final List<Object?> _storage;
  var _start = 0;
  var _length = 0;
  var _droppedCount = 0;

  /// Number of currently retained values.
  int get length => _length;

  /// Number of values overwritten since construction or the latest clear.
  int get droppedCount => _droppedCount;

  /// Whether no values are retained.
  bool get isEmpty => _length == 0;

  /// Whether [length] has reached [capacity].
  bool get isFull => _length == capacity;

  /// Immutable oldest-to-newest snapshot.
  List<T> get values => List<T>.unmodifiable(
    Iterable<T>.generate(
      _length,
      (index) => _storage[(_start + index) % capacity] as T,
    ),
  );

  /// Retains [value], overwriting the oldest value when full.
  void add(T value) {
    if (_length < capacity) {
      _storage[(_start + _length) % capacity] = value;
      _length += 1;
      return;
    }
    _storage[_start] = value;
    _start = (_start + 1) % capacity;
    _droppedCount += 1;
  }

  /// Drops every retained reference and resets overwrite accounting.
  void clear() {
    for (var index = 0; index < _storage.length; index += 1) {
      _storage[index] = null;
    }
    _start = 0;
    _length = 0;
    _droppedCount = 0;
  }

  static int _validateCapacity(int capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
    }
    return capacity;
  }
}

/// Cold incremental operation with explicit per-item backpressure.
final class IncrementalOperation<Item, Failure extends Object> {
  IncrementalOperation._({
    required _IncrementalSourceKind sourceKind,
    SyncIncrementalProducer<Item, Failure>? syncProducer,
    AsyncIncrementalProducer<Item, Failure>? asyncProducer,
    CloseableSyncIncrementalProducer<Item, Failure>? closeableProducer,
    required this.limits,
    required IncrementalWeightOf<Item>? weightOf,
    required DateTime Function()? now,
  }) : _sourceKind = sourceKind,
       _syncProducer = syncProducer,
       _asyncProducer = asyncProducer,
       _closeableProducer = closeableProducer,
       _weightOf = weightOf ?? _unitWeight,
       _now = now ?? _systemUtcNow {
    limits._validate();
  }

  /// Creates an operation around a finite resource-free iterable factory.
  factory IncrementalOperation.sync(
    SyncIncrementalProducer<Item, Failure> producer, {
    IncrementalLimits limits = const IncrementalLimits(),
    IncrementalWeightOf<Item>? weightOf,
    DateTime Function()? now,
  }) => IncrementalOperation<Item, Failure>._(
    sourceKind: _IncrementalSourceKind.sync,
    syncProducer: producer,
    limits: limits,
    weightOf: weightOf,
    now: now,
  );

  /// Creates an operation around a cold single-subscription stream factory.
  factory IncrementalOperation.async(
    AsyncIncrementalProducer<Item, Failure> producer, {
    IncrementalLimits limits = const IncrementalLimits(),
    IncrementalWeightOf<Item>? weightOf,
    DateTime Function()? now,
  }) => IncrementalOperation<Item, Failure>._(
    sourceKind: _IncrementalSourceKind.async,
    asyncProducer: producer,
    limits: limits,
    weightOf: weightOf,
    now: now,
  );

  /// Creates an operation around an owned closeable synchronous source.
  factory IncrementalOperation.syncCloseable(
    CloseableSyncIncrementalProducer<Item, Failure> producer, {
    IncrementalLimits limits = const IncrementalLimits(),
    IncrementalWeightOf<Item>? weightOf,
    DateTime Function()? now,
  }) => IncrementalOperation<Item, Failure>._(
    sourceKind: _IncrementalSourceKind.syncCloseable,
    closeableProducer: producer,
    limits: limits,
    weightOf: weightOf,
    now: now,
  );

  /// Per-execution item and weight bounds.
  final IncrementalLimits limits;

  final _IncrementalSourceKind _sourceKind;
  final SyncIncrementalProducer<Item, Failure>? _syncProducer;
  final AsyncIncrementalProducer<Item, Failure>? _asyncProducer;
  final CloseableSyncIncrementalProducer<Item, Failure>? _closeableProducer;
  final IncrementalWeightOf<Item> _weightOf;
  final DateTime Function() _now;
  var _nextExecutionId = 0;

  /// Delivers successful items one at a time and awaits each callback.
  Future<IncrementalConsumeResult<Failure>> consume({
    required FutureOr<void> Function(Item item, IncrementalItemContext context)
    onValue,
    CancellationSignal? cancellation,
    DateTime? deadline,
  }) async {
    final result = await _execute(
      onValue: onValue,
      cancellation: cancellation,
      deadline: deadline,
    );
    return IncrementalConsumeResult<Failure>(
      outcome: result.outcome,
      report: result.report,
    );
  }

  /// Reduces every admitted item without retaining the item sequence.
  Future<IncrementalFoldResult<Aggregate, Failure>> fold<Aggregate>({
    required Aggregate initial,
    required IncrementalReducer<Aggregate, Item> reducer,
    CancellationSignal? cancellation,
    DateTime? deadline,
  }) async {
    var aggregate = initial;
    final result = await _execute(
      onValue: (item, context) {
        aggregate = reducer(aggregate, item, context);
      },
      cancellation: cancellation,
      deadline: deadline,
    );
    return IncrementalFoldResult<Aggregate, Failure>(
      aggregate: aggregate,
      outcome: result.outcome,
      report: result.report,
    );
  }

  /// Retains only the latest [capacity] admitted items in producer order.
  Future<IncrementalCollectResult<Item, Failure>> collectBounded({
    required int capacity,
    CancellationSignal? cancellation,
    DateTime? deadline,
  }) async {
    final ring = BoundedRingBuffer<Item>(capacity);
    final result = await _execute(
      onValue: (item, _) => ring.add(item),
      cancellation: cancellation,
      deadline: deadline,
    );
    return IncrementalCollectResult<Item, Failure>(
      items: ring.values,
      droppedItemCount: ring.droppedCount,
      outcome: result.outcome,
      report: result.report,
    );
  }

  Future<_IncrementalRunResult<Failure>> _execute({
    required FutureOr<void> Function(Item item, IncrementalItemContext context)
    onValue,
    CancellationSignal? cancellation,
    DateTime? deadline,
  }) async {
    if (deadline != null && !deadline.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
    final state = _IncrementalRunState(
      executionId: ++_nextExecutionId,
      startedAt: _readUtcNow(),
      now: _readUtcNow,
    );
    final guard = _IncrementalGuard(
      cancellation: cancellation,
      deadline: deadline,
      now: _readUtcNow,
    );
    try {
      return await switch (_sourceKind) {
        _IncrementalSourceKind.sync => _runSync(state, guard, onValue),
        _IncrementalSourceKind.syncCloseable => _runSyncCloseable(
          state,
          guard,
          onValue,
        ),
        _IncrementalSourceKind.async => _runAsync(state, guard, onValue),
      };
    } finally {
      guard.dispose();
    }
  }

  Future<_IncrementalRunResult<Failure>> _runSync(
    _IncrementalRunState state,
    _IncrementalGuard guard,
    FutureOr<void> Function(Item, IncrementalItemContext) onValue,
  ) async {
    guard.check();
    final iterator = _syncProducer!().iterator;
    while (true) {
      guard.check();
      if (!iterator.moveNext()) {
        return state.complete<Failure>();
      }
      final terminal = await _handle(iterator.current, state, guard, onValue);
      if (terminal != null) return terminal;
    }
  }

  Future<_IncrementalRunResult<Failure>> _runSyncCloseable(
    _IncrementalRunState state,
    _IncrementalGuard guard,
    FutureOr<void> Function(Item, IncrementalItemContext) onValue,
  ) async {
    guard.check();
    final source = _closeableProducer!();
    final cleanup = _IncrementalCleanup(source.close);
    try {
      final iterator = source.iterator;
      while (true) {
        guard.check();
        if (!iterator.moveNext()) {
          await cleanup.run();
          guard.check();
          return state.complete<Failure>();
        }
        final terminal = await _handle(iterator.current, state, guard, onValue);
        if (terminal != null) {
          await cleanup.run(
            primaryError: switch (terminal.outcome) {
              Err<Object>(:final failure) => failure,
              Ok<void>() => null,
            },
            primaryStackTrace: switch (terminal.outcome) {
              Err<Object>(:final stackTrace) => stackTrace,
              Ok<void>() => null,
            },
          );
          return terminal.withReport(
            state.report(IncrementalTerminalKind.failed),
          );
        }
      }
    } on IncrementalCleanupException {
      rethrow;
    } on IncrementalLimitExceededException catch (error, stackTrace) {
      await _rethrowLimitAfterCleanup(cleanup, state, error, stackTrace);
    } catch (error, stackTrace) {
      await cleanup.run(primaryError: error, primaryStackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_IncrementalRunResult<Failure>> _runAsync(
    _IncrementalRunState state,
    _IncrementalGuard guard,
    FutureOr<void> Function(Item, IncrementalItemContext) onValue,
  ) async {
    guard.check();
    final stream = _asyncProducer!();
    if (stream.isBroadcast) {
      throw const IncrementalBroadcastStreamException();
    }
    final cursor = _IncrementalAsyncCursor<Result<Item, Failure>>(stream);
    final cleanup = _IncrementalCleanup(cursor.cancel);
    guard.attach(cleanup.start);
    try {
      while (true) {
        guard.check();
        if (!await cursor.moveNext()) {
          guard.check();
          await cleanup.run();
          guard.check();
          return state.complete<Failure>();
        }
        guard.check();
        final terminal = await _handle(cursor.current, state, guard, onValue);
        if (terminal != null) {
          await cleanup.run(
            primaryError: switch (terminal.outcome) {
              Err<Object>(:final failure) => failure,
              Ok<void>() => null,
            },
            primaryStackTrace: switch (terminal.outcome) {
              Err<Object>(:final stackTrace) => stackTrace,
              Ok<void>() => null,
            },
          );
          return terminal.withReport(
            state.report(IncrementalTerminalKind.failed),
          );
        }
      }
    } on IncrementalCleanupException {
      rethrow;
    } on IncrementalLimitExceededException catch (error, stackTrace) {
      await _rethrowLimitAfterCleanup(cleanup, state, error, stackTrace);
    } catch (error, stackTrace) {
      await cleanup.run(primaryError: error, primaryStackTrace: stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_IncrementalRunResult<Failure>?> _handle(
    Result<Item, Failure> next,
    _IncrementalRunState state,
    _IncrementalGuard guard,
    FutureOr<void> Function(Item, IncrementalItemContext) onValue,
  ) async {
    switch (next) {
      case Err<Object>(:final failure, :final stackTrace):
        return state.fail<Failure>(failure as Failure, stackTrace);
      case Ok<dynamic>(:final value):
        final item = value as Item;
        final itemWeight = _weightOf(item);
        if (itemWeight < 0) {
          throw ArgumentError.value(
            itemWeight,
            'weightOf(item)',
            'Must not be negative.',
          );
        }
        final attemptedSequence = state.emissionCount + 1;
        if (attemptedSequence > limits.maxEmissions) {
          throw IncrementalEmissionLimitExceededException(
            limit: limits.maxEmissions,
            attemptedSequence: attemptedSequence,
            report: state.report(IncrementalTerminalKind.limitExceeded),
          );
        }
        final attemptedWeight = state.totalWeight + itemWeight;
        if (attemptedWeight > limits.maxWeight) {
          throw IncrementalWeightLimitExceededException(
            limit: limits.maxWeight,
            itemWeight: itemWeight,
            attemptedWeight: attemptedWeight,
            report: state.report(IncrementalTerminalKind.limitExceeded),
          );
        }
        final context = IncrementalItemContext(
          executionId: state.executionId,
          sequence: attemptedSequence,
          weight: itemWeight,
          cumulativeWeight: attemptedWeight,
          timestamp: _readUtcNow(),
        );
        state
          ..emissionCount = attemptedSequence
          ..totalWeight = attemptedWeight;
        await onValue(item, context);
        guard.check();
        return null;
    }
  }

  DateTime _readUtcNow() {
    final value = _now();
    if (!value.isUtc) {
      throw StateError('Incremental clock must return UTC instants.');
    }
    return value;
  }

  static int _unitWeight<T>(T _) => 1;

  static DateTime _systemUtcNow() => DateTime.now().toUtc();

  static Future<Never> _rethrowLimitAfterCleanup(
    _IncrementalCleanup cleanup,
    _IncrementalRunState state,
    IncrementalLimitExceededException error,
    StackTrace stackTrace,
  ) async {
    await cleanup.run(primaryError: error, primaryStackTrace: stackTrace);
    final report = state.report(IncrementalTerminalKind.limitExceeded);
    final refreshed = switch (error) {
      IncrementalEmissionLimitExceededException() =>
        IncrementalEmissionLimitExceededException(
          limit: error.limit,
          attemptedSequence: error.attemptedSequence,
          report: report,
        ),
      IncrementalWeightLimitExceededException() =>
        IncrementalWeightLimitExceededException(
          limit: error.limit,
          itemWeight: error.itemWeight,
          attemptedWeight: error.attemptedWeight,
          report: report,
        ),
    };
    Error.throwWithStackTrace(refreshed, stackTrace);
  }
}

enum _IncrementalSourceKind { sync, syncCloseable, async }

final class _IncrementalRunState {
  _IncrementalRunState({
    required this.executionId,
    required this.startedAt,
    required this.now,
  });

  final int executionId;
  final DateTime startedAt;
  final DateTime Function() now;
  var emissionCount = 0;
  var totalWeight = 0;

  IncrementalReport report(IncrementalTerminalKind terminalKind) =>
      IncrementalReport(
        executionId: executionId,
        emissionCount: emissionCount,
        totalWeight: totalWeight,
        startedAt: startedAt,
        finishedAt: now(),
        terminalKind: terminalKind,
      );

  _IncrementalRunResult<F> complete<F extends Object>() =>
      _IncrementalRunResult<F>(
        outcome: const Ok<void>(null),
        report: report(IncrementalTerminalKind.completed),
      );

  _IncrementalRunResult<F> fail<F extends Object>(
    F failure,
    StackTrace stackTrace,
  ) => _IncrementalRunResult<F>(
    outcome: Err<F>(failure, stackTrace),
    report: report(IncrementalTerminalKind.failed),
  );
}

final class _IncrementalRunResult<F extends Object> {
  const _IncrementalRunResult({required this.outcome, required this.report});

  final Result<void, F> outcome;
  final IncrementalReport report;

  _IncrementalRunResult<F> withReport(IncrementalReport nextReport) =>
      _IncrementalRunResult<F>(outcome: outcome, report: nextReport);
}

final class _IncrementalGuard {
  _IncrementalGuard({
    required this.cancellation,
    required this.deadline,
    required this.now,
  }) {
    final limit = deadline;
    if (limit != null) {
      final remaining = limit.difference(now());
      if (remaining <= Duration.zero) {
        _deadlineElapsed = true;
      } else {
        _deadlineTimer = Timer(remaining, () {
          _deadlineElapsed = true;
          _interrupt?.call();
        });
      }
    }
    _registration = cancellation?.register((_) => _interrupt?.call());
  }

  final CancellationSignal? cancellation;
  final DateTime? deadline;
  final DateTime Function() now;
  Timer? _deadlineTimer;
  CancellationRegistration? _registration;
  void Function()? _interrupt;
  var _deadlineElapsed = false;

  void attach(void Function() interrupt) {
    _interrupt = interrupt;
    if (cancellation?.isCancelled ?? false || _deadlineElapsed) interrupt();
  }

  void check() {
    cancellation?.throwIfCancelled();
    final limit = deadline;
    if (_deadlineElapsed || (limit != null && !now().isBefore(limit))) {
      throw OperationDeadlineExceededException(limit!);
    }
  }

  void dispose() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _registration?.dispose();
    _registration = null;
    _interrupt = null;
  }
}

final class _IncrementalAsyncCursor<T> {
  _IncrementalAsyncCursor(Stream<T> stream)
    : _iterator = StreamIterator(stream);

  final StreamIterator<T> _iterator;
  Future<void>? _cancellation;

  T get current => _iterator.current;

  Future<bool> moveNext() => _iterator.moveNext();

  Future<void> cancel() => _cancellation ??= _iterator.cancel();
}

final class _IncrementalCleanup {
  _IncrementalCleanup(this._callback);

  final FutureOr<void> Function() _callback;
  Future<void>? _running;

  void start() {
    _running ??= Future<void>.sync(_callback);
  }

  Future<void> run({
    Object? primaryError,
    StackTrace? primaryStackTrace,
  }) async {
    start();
    try {
      await _running;
    } catch (error, stackTrace) {
      throw IncrementalCleanupException(
        error: error,
        stackTrace: stackTrace,
        primaryError: primaryError,
        primaryStackTrace: primaryStackTrace,
      );
    }
  }
}
