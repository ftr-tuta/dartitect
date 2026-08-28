import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';

/// Durable disposition of one local-first mutation attempt.
enum CommitDisposition {
  /// Remote delivery and durable local acknowledgement both completed.
  committed,

  /// The local change/outbox remain pending for an explicit or scheduled retry.
  queued,

  /// The remote boundary definitively rejected the mutation.
  rejected,

  /// Delivery may have committed, so rollback or retry requires an audit.
  uncertain,
}

/// Consumer-persisted synchronization state for one affected entity.
enum EntitySyncState {
  /// No pending local mutation remains.
  synced,

  /// A durable outbox operation is waiting for delivery.
  pending,

  /// One delivery attempt is currently in progress.
  syncing,

  /// The remote boundary definitively rejected the operation.
  rejected,

  /// Consumer conflict policy must reconcile local and remote values.
  conflicted,

  /// Delivery may have committed and requires an explicit audit decision.
  uncertain,
}

/// Retry category selected for an expected typed synchronization failure.
enum RetryKind {
  /// Never retries automatically.
  manual,

  /// Retries with a bounded exponential delay.
  transient,
}

/// Explicit manual or bounded transient retry classification.
final class RetryClassification {
  /// Creates the default manual-only classification.
  const RetryClassification.manual()
    : kind = RetryKind.manual,
      maxAttempts = 1,
      initialDelay = Duration.zero,
      multiplier = 1,
      maxDelay = Duration.zero;

  /// Creates an opt-in bounded exponential retry classification.
  RetryClassification.transient({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 200),
    this.multiplier = 2,
    this.maxDelay = const Duration(seconds: 30),
  }) : kind = RetryKind.transient {
    if (maxAttempts < 2) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Must be at least 2.',
      );
    }
    if (initialDelay <= Duration.zero) {
      throw ArgumentError.value(
        initialDelay,
        'initialDelay',
        'Must be positive.',
      );
    }
    if (multiplier < 1) {
      throw ArgumentError.value(
        multiplier,
        'multiplier',
        'Must be at least 1.',
      );
    }
    if (maxDelay < initialDelay) {
      throw ArgumentError.value(
        maxDelay,
        'maxDelay',
        'Must not be shorter than initialDelay.',
      );
    }
  }

  /// Retry category.
  final RetryKind kind;

  /// Total delivery attempts, including the first attempt.
  final int maxAttempts;

  /// Delay before the second delivery attempt.
  final Duration initialDelay;

  /// Integer exponential multiplier applied after each failed attempt.
  final int multiplier;

  /// Upper bound for one retry delay.
  final Duration maxDelay;

  /// Computes the bounded delay after [failedAttempt].
  Duration delayAfter(int failedAttempt) {
    if (kind == RetryKind.manual) return Duration.zero;
    if (failedAttempt < 1) {
      throw ArgumentError.value(
        failedAttempt,
        'failedAttempt',
        'Must be positive.',
      );
    }
    var microseconds = initialDelay.inMicroseconds;
    for (var index = 1; index < failedAttempt; index += 1) {
      microseconds *= multiplier;
      if (microseconds >= maxDelay.inMicroseconds) return maxDelay;
    }
    return Duration(
      microseconds: microseconds.clamp(0, maxDelay.inMicroseconds),
    );
  }
}

/// Consumer decision for an expected synchronization failure.
final class MutationFailurePolicy {
  /// Keeps the local change queued with [retry] semantics.
  const MutationFailurePolicy.queued({
    this.retry = const RetryClassification.manual(),
  }) : disposition = CommitDisposition.queued,
       syncState = EntitySyncState.pending;

  /// Records a definitive rejection without automatic compensation.
  const MutationFailurePolicy.rejected()
    : disposition = CommitDisposition.rejected,
      syncState = EntitySyncState.rejected,
      retry = const RetryClassification.manual();

  /// Records a conflict for consumer-owned reconciliation.
  const MutationFailurePolicy.conflicted()
    : disposition = CommitDisposition.rejected,
      syncState = EntitySyncState.conflicted,
      retry = const RetryClassification.manual();

  /// Records an explicitly uncertain expected transport outcome.
  const MutationFailurePolicy.uncertain()
    : disposition = CommitDisposition.uncertain,
      syncState = EntitySyncState.uncertain,
      retry = const RetryClassification.manual();

  /// Durable command disposition.
  final CommitDisposition disposition;

  /// Entity/outbox state persisted by the consumer store.
  final EntitySyncState syncState;

  /// Retry policy for this failure.
  final RetryClassification retry;
}

/// Immutable durable operation stored in the consumer-owned outbox schema.
final class OutboxOperation<K, A> {
  /// Creates an operation with a stable [idempotencyKey].
  OutboxOperation({
    required this.idempotencyKey,
    required this.key,
    required this.argument,
    this.attempt = 0,
    this.syncState = EntitySyncState.pending,
  }) {
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'Must not be empty.',
      );
    }
    if (attempt < 0) {
      throw ArgumentError.value(attempt, 'attempt', 'Must not be negative.');
    }
  }

  /// Consumer-scoped key reused by every at-least-once delivery.
  final String idempotencyKey;

  /// Entity or aggregate key used for per-key sequential scheduling.
  final K key;

  /// Consumer mutation argument persisted without inspection by Dartitect.
  final A argument;

  /// Number of delivery attempts already started.
  final int attempt;

  /// Latest consumer-persisted synchronization state.
  final EntitySyncState syncState;

  /// Returns a new durable representation for [attempt] and [syncState].
  OutboxOperation<K, A> withState({int? attempt, EntitySyncState? syncState}) =>
      OutboxOperation<K, A>(
        idempotencyKey: idempotencyKey,
        key: key,
        argument: argument,
        attempt: attempt ?? this.attempt,
        syncState: syncState ?? this.syncState,
      );
}

/// Consumer-owned persistence boundary for local mutation and durable outbox.
abstract interface class MutationOutboxStore<K, A, F extends Object> {
  /// Atomically applies the local change and enqueues [operation].
  ///
  /// An `Err<F>` must leave both the domain data and outbox unchanged.
  Future<Result<void, F>> applyLocalAndEnqueue(
    OutboxOperation<K, A> operation,
    CancellationSignal signal,
  );

  /// Atomically persists the operation attempt and entity synchronization state.
  Future<Result<void, F>> markState(
    OutboxOperation<K, A> operation,
    CancellationSignal signal,
  );

  /// Loads durable operations eligible for automatic session recovery.
  ///
  /// The command filters out non-pending and duplicate idempotency keys.
  Future<Result<List<OutboxOperation<K, A>>, F>> loadRecoverable(
    CancellationSignal signal,
  );

  /// Runs an explicit consumer-owned compensating local transaction.
  Future<Result<void, F>> compensate(
    OutboxOperation<K, A> operation,
    CancellationSignal signal,
  );
}

/// Local-first execution result returned as a successful command outcome.
final class MutationExecution<A, K, T, F extends Object> {
  /// Creates an immutable mutation result.
  const MutationExecution({
    required this.operation,
    required this.disposition,
    required this.syncState,
    required this.hasRemoteValue,
    this.remoteValue,
    this.syncFailure,
    this.syncFailureStackTrace,
  });

  /// Latest durable operation representation.
  final OutboxOperation<K, A> operation;

  /// Local-first disposition.
  final CommitDisposition disposition;

  /// Entity state associated with [disposition].
  final EntitySyncState syncState;

  /// Distinguishes a nullable remote success from no remote success.
  final bool hasRemoteValue;

  /// Remote success value when [hasRemoteValue] is true.
  final T? remoteValue;

  /// Expected synchronization/persistence failure, if one occurred after the
  /// atomic local change was accepted.
  final F? syncFailure;

  /// Original stack trace paired with [syncFailure].
  final StackTrace? syncFailureStackTrace;
}

/// Owned offline-first mutation lanes with durable at-least-once delivery.
final class MutationCommand<A, K, T, F extends Object>
    implements AsyncDisposable {
  /// Creates per-key sequential mutation lanes around consumer-owned storage.
  MutationCommand({
    required MutationOutboxStore<K, A, F> store,
    required Future<Result<T, F>> Function(
      OutboxOperation<K, A> operation,
      CancellationSignal signal,
    )
    synchronize,
    String Function(K key, A argument)? createIdempotencyKey,
    IdGenerator? idGenerator,
    MutationFailurePolicy Function(F failure)? classifyFailure,
    Future<void> Function(Duration delay, CancellationSignal signal)?
    waitBeforeRetry,
    RetryExecutor? retryExecutor,
    CommandCrashReporter reporter = const NoOpCommandCrashReporter(),
    ReactiveObserverRegistration observer =
        const ReactiveObserverRegistration.borrowed(NoOpReactiveObserver()),
    ChangeCauseRegistry? causeRegistry,
    int Function()? monotonicMicroseconds,
    int maxConcurrentKeys = 4,
    int maxQueuePerKey = 64,
  }) : _store = store,
       _synchronize = synchronize,
       _createIdempotencyKey = createIdempotencyKey,
       _idGenerator = createIdempotencyKey == null
           ? idGenerator ?? SecureUuidV4Generator()
           : idGenerator,
       _classifyFailure = classifyFailure ?? _manualQueue,
       _retryExecutor =
           retryExecutor ??
           RetryExecutor(
             scheduler: _MutationRetryScheduler(
               waitBeforeRetry ?? _systemRetryWait,
             ),
           ),
       _reporter = reporter,
       _observerRegistration = observer,
       _causeRegistry = causeRegistry ?? ChangeCauseRegistry(),
       _monotonicMicroseconds = monotonicMicroseconds {
    if (maxConcurrentKeys <= 0) {
      throw ArgumentError.value(
        maxConcurrentKeys,
        'maxConcurrentKeys',
        'Must be positive.',
      );
    }
    if (maxQueuePerKey <= 0) {
      throw ArgumentError.value(
        maxQueuePerKey,
        'maxQueuePerKey',
        'Must be positive.',
      );
    }
    _lane =
        KeyedCommandLane<
          K,
          _MutationRequest<K, A>,
          MutationExecution<A, K, T, F>,
          F
        >(
          action: (_, request, signal) => _run(request, signal),
          concurrency: CommandConcurrency.keyed(
            perKey: CommandConcurrency.sequential(maxQueue: maxQueuePerKey),
            maxConcurrent: maxConcurrentKeys,
          ),
          reporter: reporter,
        );
    _events = SafeReactiveObserver(
      observer: observer.observer,
      onFailure: _report,
    );
    _eventStopwatch.start();
  }

  final MutationOutboxStore<K, A, F> _store;
  final Future<Result<T, F>> Function(
    OutboxOperation<K, A> operation,
    CancellationSignal signal,
  )
  _synchronize;
  final String Function(K key, A argument)? _createIdempotencyKey;
  final IdGenerator? _idGenerator;
  final MutationFailurePolicy Function(F failure) _classifyFailure;
  final RetryExecutor _retryExecutor;
  final CommandCrashReporter _reporter;
  final ReactiveObserverRegistration _observerRegistration;
  final ChangeCauseRegistry _causeRegistry;
  final int Function()? _monotonicMicroseconds;
  final Stopwatch _eventStopwatch = Stopwatch();
  late final SafeReactiveObserver _events;
  late final KeyedCommandLane<
    K,
    _MutationRequest<K, A>,
    MutationExecution<A, K, T, F>,
    F
  >
  _lane;
  var _operationCount = 0;
  var _recoveredOperationCount = 0;
  var _revision = 0;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Operations admitted through execute, retry, or recovery.
  int get operationCount => _operationCount;

  /// Monotonic terminal operation revision emitted to reactive observers.
  int get revision => _revision;

  /// Unique pending operations admitted by session recovery.
  int get recoveredOperationCount => _recoveredOperationCount;

  /// Entity keys with a delivery currently running.
  int get activeKeyCount => _lane.activeKeyCount;

  /// Total running delivery/local-apply pipelines.
  int get runningCount => _lane.runningCount;

  /// Total calls waiting in bounded per-key queues.
  int get queuedCount => _lane.queuedCount;

  /// Per-key lanes stopped by unexpected crashes.
  int get stoppedKeyCount => _lane.stoppedKeyCount;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Observer failures isolated from mutation behavior.
  int get observerFailureCount => _events.failureCount;

  /// Recursive observer emissions dropped to prevent loops.
  int get droppedReentrantEvents => _events.droppedReentrantEvents;

  /// Applies locally, enqueues atomically, and starts best-effort delivery.
  Future<CommandOutcome<MutationExecution<A, K, T, F>, F>> execute(
    K key,
    A argument, {
    String? idempotencyKey,
    ChangeCause cause = ChangeCauses.mutationExecute,
  }) {
    _ensureActive();
    final staticCause = _causeRegistry.requireStatic(cause);
    final operation = OutboxOperation<K, A>(
      idempotencyKey:
          idempotencyKey ??
          _createIdempotencyKey?.call(key, argument) ??
          _idGenerator!.nextId(),
      key: key,
      argument: argument,
    );
    return _schedule(operation, applyLocal: true, cause: staticCause);
  }

  /// Explicitly retries one already durable pending operation.
  Future<CommandOutcome<MutationExecution<A, K, T, F>, F>> retry(
    OutboxOperation<K, A> operation, {
    ChangeCause cause = ChangeCauses.mutationRetry,
  }) {
    _ensureActive();
    final staticCause = _causeRegistry.requireStatic(cause);
    if (operation.syncState == EntitySyncState.uncertain) {
      throw StateError(
        'Audit uncertain delivery and persist pending before retrying.',
      );
    }
    return _schedule(operation, applyLocal: false, cause: staticCause);
  }

  /// Loads and drains unique pending operations without reapplying local data.
  Future<Result<List<CommandOutcome<MutationExecution<A, K, T, F>, F>>, F>>
  recoverPending() async {
    _ensureActive();
    final source = CancellationSource();
    try {
      final loaded = await _store.loadRecoverable(source.signal);
      switch (loaded) {
        case Err<Object>(:final failure, :final stackTrace):
          return Err<F>(failure as F, stackTrace);
        case Ok<dynamic>(:final value):
          final operations = value as List<OutboxOperation<K, A>>;
          final seen = <String>{};
          final pending = operations.where(
            (operation) =>
                operation.syncState == EntitySyncState.pending &&
                seen.add(operation.idempotencyKey),
          );
          final futures =
              <Future<CommandOutcome<MutationExecution<A, K, T, F>, F>>>[];
          for (final operation in pending) {
            _recoveredOperationCount += 1;
            futures.add(
              _schedule(
                operation,
                applyLocal: false,
                cause: ChangeCauses.mutationRecovery,
              ),
            );
          }
          return Ok<List<CommandOutcome<MutationExecution<A, K, T, F>, F>>>(
            await Future.wait(futures),
          );
      }
    } catch (error, stackTrace) {
      _report(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      source.dispose();
    }
  }

  /// Runs the consumer's explicit compensating transaction.
  Future<Result<void, F>> compensate(OutboxOperation<K, A> operation) async {
    _ensureActive();
    final source = CancellationSource();
    try {
      return await _store.compensate(operation, source.signal);
    } finally {
      source.dispose();
    }
  }

  /// Reopens one stopped key only after the consumer has audited durable state.
  void resume(K key) {
    _ensureActive();
    _lane.resume(key);
  }

  /// Cancels, drains, and releases all per-key lanes.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  @override
  Future<void> disposeAsync() => dispose();

  Future<CommandOutcome<MutationExecution<A, K, T, F>, F>> _schedule(
    OutboxOperation<K, A> operation, {
    required bool applyLocal,
    required ChangeCause cause,
  }) {
    _operationCount += 1;
    final staticCause = _causeRegistry.requireStatic(cause);
    return _lane.execute(
      operation.key,
      _MutationRequest<K, A>(
        operation,
        applyLocal: applyLocal,
        cause: staticCause,
      ),
    );
  }

  Future<Result<MutationExecution<A, K, T, F>, F>> _run(
    _MutationRequest<K, A> request,
    CancellationSignal signal,
  ) async {
    final started = _eventNow();
    try {
      final result = await _runOperation(request, signal);
      final previousRevision = _revision;
      _revision += 1;
      _emitEvent(
        request.cause,
        result is Err<Object>
            ? ReactiveEventKind.failed
            : ReactiveEventKind.updated,
        previousRevision,
        started,
      );
      return result;
    } on CancellationException {
      final previousRevision = _revision;
      _revision += 1;
      _emitEvent(
        request.cause,
        ReactiveEventKind.cancelled,
        previousRevision,
        started,
      );
      rethrow;
    } catch (error, stackTrace) {
      final previousRevision = _revision;
      _revision += 1;
      _emitEvent(
        request.cause,
        ReactiveEventKind.crashed,
        previousRevision,
        started,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Result<MutationExecution<A, K, T, F>, F>> _runOperation(
    _MutationRequest<K, A> request,
    CancellationSignal signal,
  ) async {
    var operation = request.operation;
    var localAccepted = !request.applyLocal;
    var deliveryMayHaveCommitted = false;
    try {
      if (request.applyLocal) {
        final applied = await _store.applyLocalAndEnqueue(operation, signal);
        signal.throwIfCancelled();
        if (applied case Err<Object>(:final failure, :final stackTrace)) {
          return Err<F>(failure as F, stackTrace);
        }
        localAccepted = true;
      }

      var latestRetry = const RetryClassification.manual();
      final delivered = await _retryExecutor
          .execute<T, _MutationRetryFailure<F>>(
            operation: (_, cancellation) async {
              operation = operation.withState(
                attempt: operation.attempt + 1,
                syncState: EntitySyncState.syncing,
              );
              final markedSyncing = await _store.markState(
                operation,
                cancellation,
              );
              cancellation.throwIfCancelled();
              if (markedSyncing case Err<Object>(
                :final failure,
                :final stackTrace,
              )) {
                return Err<_MutationRetryFailure<F>>(
                  _MutationRetryFailure<F>.stateWrite(failure as F, stackTrace),
                  stackTrace,
                );
              }

              deliveryMayHaveCommitted = true;
              final synchronized = await _synchronize(operation, cancellation);
              cancellation.throwIfCancelled();
              return switch (synchronized) {
                Ok<dynamic>(:final value) => Ok<T>(value as T),
                Err<Object>(:final failure, :final stackTrace) =>
                  await _prepareRetryFailure(
                    operation: operation,
                    failure: failure as F,
                    stackTrace: stackTrace,
                    cancellation: cancellation,
                    onPending: (pending, retry) {
                      operation = pending;
                      latestRetry = retry;
                    },
                    onDeliveryRejected: () {
                      deliveryMayHaveCommitted = false;
                    },
                  ),
              };
            },
            policy: RetryPolicy<_MutationRetryFailure<F>>(
              classify: (failure) {
                final policy = failure.policy;
                if (failure.isStateWrite || policy == null) {
                  return const RetryDecision.stop();
                }
                final retry = policy.retry;
                if (retry.kind == RetryKind.transient &&
                    operation.attempt < retry.maxAttempts) {
                  return const RetryDecision.retry();
                }
                return policy.disposition == CommitDisposition.uncertain
                    ? const RetryDecision.uncertain()
                    : const RetryDecision.stop();
              },
              maxAttempts: 0x7fffffff,
              maxElapsed: const Duration(days: 3650),
              backoff: _MutationRetryBackoff(
                (_) => latestRetry.delayAfter(operation.attempt),
              ),
            ),
            cancellation: signal,
          );

      switch (delivered) {
        case Ok<dynamic>(:final value):
          final synced = operation.withState(syncState: EntitySyncState.synced);
          final marked = await _store.markState(synced, signal);
          signal.throwIfCancelled();
          if (marked case Err<Object>(:final failure, :final stackTrace)) {
            final uncertain = operation.withState(
              syncState: EntitySyncState.uncertain,
            );
            await _markBestEffort(uncertain);
            return Ok<MutationExecution<A, K, T, F>>(
              _execution(
                uncertain,
                CommitDisposition.uncertain,
                EntitySyncState.uncertain,
                syncFailure: failure as F,
                syncFailureStackTrace: stackTrace,
              ),
            );
          }
          deliveryMayHaveCommitted = false;
          return Ok<MutationExecution<A, K, T, F>>(
            _execution(
              synced,
              CommitDisposition.committed,
              EntitySyncState.synced,
              hasRemoteValue: true,
              remoteValue: value as T,
            ),
          );
        case Err<Object>(:final failure):
          final retryFailure = failure as _MutationRetryFailure<F>;
          if (retryFailure.isStateWrite) {
            final state = retryFailure.requiresAudit
                ? EntitySyncState.uncertain
                : EntitySyncState.pending;
            final durable = operation.withState(syncState: state);
            await _markBestEffort(durable);
            return Ok<MutationExecution<A, K, T, F>>(
              _execution(
                durable,
                retryFailure.requiresAudit
                    ? CommitDisposition.uncertain
                    : CommitDisposition.queued,
                state,
                syncFailure: retryFailure.failure,
                syncFailureStackTrace: retryFailure.stackTrace,
              ),
            );
          }
          final policy = retryFailure.policy!;
          final retry = policy.retry;
          final finalPolicy =
              retry.kind == RetryKind.transient &&
                  operation.attempt >= retry.maxAttempts
              ? const MutationFailurePolicy.queued()
              : policy;
          final finalOperation = operation.withState(
            syncState: finalPolicy.syncState,
          );
          final marked = await _store.markState(finalOperation, signal);
          signal.throwIfCancelled();
          if (marked case Err<Object>(:final failure, :final stackTrace)) {
            final uncertain = operation.withState(
              syncState: EntitySyncState.uncertain,
            );
            await _markBestEffort(uncertain);
            return Ok<MutationExecution<A, K, T, F>>(
              _execution(
                uncertain,
                CommitDisposition.uncertain,
                EntitySyncState.uncertain,
                syncFailure: failure as F,
                syncFailureStackTrace: stackTrace,
              ),
            );
          }
          return Ok<MutationExecution<A, K, T, F>>(
            _execution(
              finalOperation,
              finalPolicy.disposition,
              finalPolicy.syncState,
              syncFailure: retryFailure.failure,
              syncFailureStackTrace: retryFailure.stackTrace,
            ),
          );
      }
    } on CancellationException {
      if (localAccepted) {
        final state = deliveryMayHaveCommitted
            ? EntitySyncState.uncertain
            : EntitySyncState.pending;
        await _markBestEffort(operation.withState(syncState: state));
      }
      rethrow;
    } catch (error, stackTrace) {
      if (localAccepted) {
        final state = deliveryMayHaveCommitted
            ? EntitySyncState.uncertain
            : EntitySyncState.pending;
        await _markBestEffort(operation.withState(syncState: state));
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Result<T, _MutationRetryFailure<F>>> _prepareRetryFailure({
    required OutboxOperation<K, A> operation,
    required F failure,
    required StackTrace stackTrace,
    required CancellationSignal cancellation,
    required void Function(
      OutboxOperation<K, A> pending,
      RetryClassification retry,
    )
    onPending,
    required void Function() onDeliveryRejected,
  }) async {
    onDeliveryRejected();
    final policy = _classifyFailure(failure);
    final retry = policy.retry;
    if (retry.kind == RetryKind.transient &&
        operation.attempt < retry.maxAttempts) {
      final pending = operation.withState(syncState: EntitySyncState.pending);
      final marked = await _store.markState(pending, cancellation);
      cancellation.throwIfCancelled();
      if (marked case Err<Object>(:final failure, :final stackTrace)) {
        return Err<_MutationRetryFailure<F>>(
          _MutationRetryFailure<F>.stateWrite(
            failure as F,
            stackTrace,
            requiresAudit: true,
          ),
          stackTrace,
        );
      }
      onPending(pending, retry);
    }
    return Err<_MutationRetryFailure<F>>(
      _MutationRetryFailure<F>.synchronization(failure, stackTrace, policy),
      stackTrace,
    );
  }

  MutationExecution<A, K, T, F> _execution(
    OutboxOperation<K, A> operation,
    CommitDisposition disposition,
    EntitySyncState syncState, {
    bool hasRemoteValue = false,
    T? remoteValue,
    F? syncFailure,
    StackTrace? syncFailureStackTrace,
  }) => MutationExecution<A, K, T, F>(
    operation: operation,
    disposition: disposition,
    syncState: syncState,
    hasRemoteValue: hasRemoteValue,
    remoteValue: remoteValue,
    syncFailure: syncFailure,
    syncFailureStackTrace: syncFailureStackTrace,
  );

  Future<void> _markBestEffort(OutboxOperation<K, A> operation) async {
    final source = CancellationSource();
    try {
      await _store.markState(operation, source.signal);
    } on Object {
      return;
    } finally {
      source.dispose();
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    try {
      _reporter.report(error, stackTrace);
    } on Object {
      return;
    }
  }

  void _emitEvent(
    ChangeCause cause,
    ReactiveEventKind kind,
    int previousRevision,
    int started,
  ) {
    _events.onChange(
      ReactiveChangeEvent(
        source: ReactiveEventSource.mutationCommand,
        kind: kind,
        cause: cause,
        previousRevision: previousRevision,
        nextRevision: _revision,
        duration: _eventDuration(started),
        listenerCount: 0,
      ),
    );
  }

  int _eventNow() {
    try {
      return _monotonicMicroseconds?.call() ??
          _eventStopwatch.elapsedMicroseconds;
    } on Object {
      return 0;
    }
  }

  Duration _eventDuration(int started) {
    final elapsed = _eventNow() - started;
    return Duration(microseconds: elapsed < 0 ? 0 : elapsed);
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _lane.dispose();
    await _observerRegistration.disposeOwned();
  }

  void _ensureActive() {
    if (_disposed) throw StateError('MutationCommand is disposed.');
  }

  static MutationFailurePolicy _manualQueue(Object failure) =>
      const MutationFailurePolicy.queued();

  static Future<void> _systemRetryWait(
    Duration delay,
    CancellationSignal signal,
  ) {
    signal.throwIfCancelled();
    final completer = Completer<void>();
    late final Timer timer;
    late final CancellationRegistration registration;
    timer = Timer(delay, () {
      registration.dispose();
      if (!completer.isCompleted) completer.complete();
    });
    registration = signal.register((reason) {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(CancellationException(reason));
      }
    });
    return completer.future;
  }
}

final class _MutationRequest<K, A> {
  const _MutationRequest(
    this.operation, {
    required this.applyLocal,
    required this.cause,
  });

  final OutboxOperation<K, A> operation;
  final bool applyLocal;
  final ChangeCause cause;
}

final class _MutationRetryFailure<F extends Object> {
  const _MutationRetryFailure._({
    required this.failure,
    required this.stackTrace,
    required this.policy,
    required this.isStateWrite,
    required this.requiresAudit,
  });

  const _MutationRetryFailure.synchronization(
    F failure,
    StackTrace stackTrace,
    MutationFailurePolicy policy,
  ) : this._(
        failure: failure,
        stackTrace: stackTrace,
        policy: policy,
        isStateWrite: false,
        requiresAudit: false,
      );

  const _MutationRetryFailure.stateWrite(
    F failure,
    StackTrace stackTrace, {
    bool requiresAudit = false,
  }) : this._(
         failure: failure,
         stackTrace: stackTrace,
         policy: null,
         isStateWrite: true,
         requiresAudit: requiresAudit,
       );

  final F failure;
  final StackTrace stackTrace;
  final MutationFailurePolicy? policy;
  final bool isStateWrite;
  final bool requiresAudit;
}

final class _MutationRetryScheduler implements ResilienceScheduler {
  const _MutationRetryScheduler(this._wait);

  final Future<void> Function(Duration delay, CancellationSignal cancellation)
  _wait;

  @override
  Future<void> wait(Duration delay, CancellationSignal cancellation) =>
      _wait(delay, cancellation);
}

final class _MutationRetryBackoff implements BackoffStrategy {
  const _MutationRetryBackoff(this.compute);

  final Duration Function(int failedAttempt) compute;

  @override
  Duration delayAfter(int failedAttempt) => compute(failedAttempt);
}
