import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/task.dart';
import '../domain/task_repository.dart';
import 'offline_task_store.dart';
import 'task_remote.dart';

/// Sanitized dependents-first teardown phase for workload diagnostics.
enum TaskSessionDisposePhase {
  /// Session admission remains open.
  active,

  /// Paged commands and their local observation are draining.
  paging,

  /// Sync attempts are draining.
  sync,

  /// Durable mutation lanes are draining.
  mutations,

  /// The borrowed local reactive source is closing.
  local,

  /// The bounded journal is closing.
  journal,

  /// The remote adapter is closing.
  remote,

  /// The authoritative store is closing last.
  store,

  /// Teardown completed with no owned handles.
  complete,
}

/// Runtime counters and crash evidence retained after session disposal.
final class TaskSessionDiagnostics {
  /// Unexpected command crashes reported by the mutation lane.
  final List<Object> crashes = <Object>[];

  /// App lifecycle transitions forwarded by the route.
  int lifecycleTransitions = 0;

  /// Current app lifecycle admission state.
  bool foreground = true;

  /// Whether dependents-first session teardown completed.
  bool disposed = false;

  /// Current sanitized teardown phase.
  TaskSessionDisposePhase disposePhase = TaskSessionDisposePhase.active;

  /// Owned isolate workers that have not completed terminal cleanup.
  int activeIsolateWorkers = 0;
}

/// Explicit feature composition for local-first pages and durable mutations.
final class OfflineFirstTaskSession implements AsyncDisposable {
  OfflineFirstTaskSession._({
    required this.store,
    required this.remote,
    required this.local,
    required this.paged,
    required this.mutations,
    required this.sync,
    required this.journal,
  });

  /// Creates, seeds, and activates a 10k-row reference workload.
  static Future<OfflineFirstTaskSession> create({
    required OfflineTaskStore store,
    required TaskRemote remote,
    int seedCount = 10000,
  }) async {
    await store.seed(seedCount);
    final journal = ReactiveJournal(capacity: 64);
    final local = LiveResource<PagedLocalSnapshot<int, Task>, TaskFailure>(
      source: _TaskStoreSource(store),
      policy: const ActivationPolicy.whileObserved(),
    );
    late final PagedLiveResource<TaskCursor, int, Task, TaskFailure> paged;
    paged = PagedLiveResource<TaskCursor, int, Task, TaskFailure>(
      local: local,
      initialCursor: const TaskCursor(),
      requestPage: remote.requestPage,
      writePage: store.writePage,
      keyOf: (task) => task.id,
      versionOf: (task) => task.version,
      collectionPolicy: CollectionUpdatePolicy.versionedByKey,
      observationTimeout: const Duration(seconds: 3),
      mapObservationTimeout: (_) => const TaskObservationTimeoutFailure(),
    );
    var sequence = 0;
    final diagnostics = TaskSessionDiagnostics();
    final mutations = MutationCommand<TaskMutation, int, void, TaskFailure>(
      store: store,
      synchronize: remote.synchronize,
      createIdempotencyKey: (key, argument) {
        sequence += 1;
        return 'reference-task-$key-$sequence';
      },
      classifyFailure: _classifyFailure,
      reporter: _TaskCrashReporter(diagnostics.crashes),
      observer: ReactiveObserverRegistration.borrowed(journal),
    );
    final sync = SyncEngine<String, int, TaskFailure>(
      datasets: <SyncDataset<String, int, TaskFailure>>[
        SyncDataset<String, int, TaskFailure>(
          key: 'maintenance',
          synchronize: (context) async {
            final recovered = await mutations.recoverPending();
            return switch (recovered) {
              Ok<Object?>() => Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.checkpoint(
                  (context.checkpoint ?? 0) + 1,
                ),
              ),
              Err<Object>(:final failure, :final stackTrace) =>
                Err<TaskFailure>(failure as TaskFailure, stackTrace),
            };
          },
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['maintenance']),
      checkpoints: store,
      journal: store.syncJournal,
    );
    final session = OfflineFirstTaskSession._(
      store: store,
      remote: remote,
      local: local,
      paged: paged,
      mutations: mutations,
      sync: sync,
      journal: journal,
    );
    session._diagnostics = diagnostics;
    await _waitForInitialLocalSnapshot(local);
    return session;
  }

  /// Consumer-owned authoritative store.
  final OfflineTaskStore store;

  /// Owned deterministic HTTP boundary.
  final TaskRemote remote;

  /// Owned lifecycle-aware local resource.
  final LiveResource<PagedLocalSnapshot<int, Task>, TaskFailure> local;

  /// Owned local-authority paged collection.
  final PagedLiveResource<TaskCursor, int, Task, TaskFailure> paged;

  /// Owned per-task durable mutation lanes.
  final MutationCommand<TaskMutation, int, void, TaskFailure> mutations;

  /// Owned provider-neutral synchronization engine with durable journal facts.
  final SyncEngine<String, int, TaskFailure> sync;

  /// Bounded, memory-only causal diagnostics.
  final ReactiveJournal journal;

  late TaskSessionDiagnostics _diagnostics;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Stable diagnostics readable after teardown.
  TaskSessionDiagnostics get diagnostics => _diagnostics;

  /// Refreshes the active query from its first page.
  Future<CommandOutcome<PageWriteReceipt<TaskCursor>, TaskFailure>> refresh() {
    final cursor = TaskCursor(query: paged.initialCursor.query);
    store.select(cursor, reset: true);
    return paged.refresh();
  }

  /// Loads the next page, dropping reentrant requests.
  Future<CommandOutcome<PageWriteReceipt<TaskCursor>, TaskFailure>> loadMore() {
    final cursor = paged.nextCursor;
    if (cursor != null) store.select(cursor, reset: false);
    return paged.loadMore();
  }

  /// Runs switch-latest search and resets the local visible window.
  Future<CommandOutcome<PageWriteReceipt<TaskCursor>, TaskFailure>> search(
    String query,
  ) {
    final cursor = TaskCursor(query: query.trim());
    store.select(cursor, reset: true);
    return paged.search(cursor);
  }

  /// Runs the durable maintenance dataset and confirms its next checkpoint.
  Future<SyncReport<String, int, TaskFailure>> runMaintenanceSync() =>
      sync.start().done;

  /// Executes a transferable projection through the versioned isolate worker.
  Future<Result<int, TaskFailure>> runBackgroundProjection(int value) async {
    _diagnostics.activeIsolateWorkers += 1;
    final worker = await IsolateWorker.spawn<int, int, TaskFailure>(
      handler: _doubleProjection,
    );
    try {
      return await worker.execute(value);
    } finally {
      await worker.safeStop();
      _diagnostics.activeIsolateWorkers -= 1;
    }
  }

  /// Applies a task toggle locally before best-effort remote delivery.
  Future<
    CommandOutcome<
      MutationExecution<TaskMutation, int, void, TaskFailure>,
      TaskFailure
    >
  >
  toggle(int id) async {
    final current = await store.findTask(id);
    if (current == null) {
      return CommandFailed<
        MutationExecution<TaskMutation, int, void, TaskFailure>,
        TaskFailure
      >(const TaskStorageFailure(), StackTrace.current);
    }
    return mutations.execute(
      id,
      TaskMutation(taskId: id, completed: !current.completed),
    );
  }

  /// Restores connectivity and drains only durable pending operations.
  Future<
    Result<
      List<
        CommandOutcome<
          MutationExecution<TaskMutation, int, void, TaskFailure>,
          TaskFailure
        >
      >,
      TaskFailure
    >
  >
  reconnect() {
    remote.mode = ReferenceRemoteMode.online;
    return mutations.recoverPending();
  }

  /// Re-delivers a known operation with its original idempotency key.
  Future<
    CommandOutcome<
      MutationExecution<TaskMutation, int, void, TaskFailure>,
      TaskFailure
    >
  >
  redeliver(OutboxOperation<int, TaskMutation> operation) =>
      mutations.retry(operation);

  /// Audits an uncertain/crashed key, persists pending, resumes, and retries.
  Future<
    CommandOutcome<
      MutationExecution<TaskMutation, int, void, TaskFailure>,
      TaskFailure
    >
  >
  auditAndResume(int key) async {
    final source = CancellationSource();
    try {
      final loaded = await store.loadRecoverable(source.signal);
      if (loaded case Err<Object>(:final failure, :final stackTrace)) {
        return CommandFailed<
          MutationExecution<TaskMutation, int, void, TaskFailure>,
          TaskFailure
        >(failure as TaskFailure, stackTrace);
      }
      final operations =
          (loaded as Ok<List<OutboxOperation<int, TaskMutation>>>).value;
      final operation = operations.lastWhere(
        (candidate) => candidate.key == key,
        orElse: () => throw StateError('No durable operation for task key.'),
      );
      final audited = operation.withState(syncState: EntitySyncState.pending);
      final marked = await store.markState(audited, source.signal);
      if (marked case Err<Object>(:final failure, :final stackTrace)) {
        return CommandFailed<
          MutationExecution<TaskMutation, int, void, TaskFailure>,
          TaskFailure
        >(failure as TaskFailure, stackTrace);
      }
      mutations.resume(key);
      return await mutations.retry(audited);
    } finally {
      source.dispose();
    }
  }

  /// Records route lifecycle without creating a global application hook.
  void setForeground(bool value) {
    if (_diagnostics.foreground == value) return;
    _diagnostics
      ..foreground = value
      ..lifecycleTransitions += 1;
  }

  @override
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _diagnostics.disposePhase = TaskSessionDisposePhase.paging;
    await paged.dispose();
    _diagnostics.disposePhase = TaskSessionDisposePhase.sync;
    await sync.disposeAsync();
    _diagnostics.disposePhase = TaskSessionDisposePhase.mutations;
    await mutations.dispose();
    _diagnostics.disposePhase = TaskSessionDisposePhase.local;
    await local.dispose();
    _diagnostics.disposePhase = TaskSessionDisposePhase.journal;
    journal.dispose();
    _diagnostics.disposePhase = TaskSessionDisposePhase.remote;
    remote.dispose();
    _diagnostics.disposePhase = TaskSessionDisposePhase.store;
    await store.disposeAsync();
    _diagnostics
      ..disposed = true
      ..disposePhase = TaskSessionDisposePhase.complete;
  }
}

Future<Result<int, TaskFailure>> _doubleProjection(
  int value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value * 2);
}

MutationFailurePolicy _classifyFailure(TaskFailure failure) =>
    switch (failure) {
      TaskRejectedFailure() => const MutationFailurePolicy.rejected(),
      TaskConflictFailure() => const MutationFailurePolicy.conflicted(),
      TaskUncertainFailure() => const MutationFailurePolicy.uncertain(),
      _ => const MutationFailurePolicy.queued(),
    };

final class _TaskStoreSource
    implements ReactiveSource<PagedLocalSnapshot<int, Task>, TaskFailure> {
  const _TaskStoreSource(this.store);

  final OfflineTaskStore store;

  @override
  Future<
    Result<
      ReactiveSourceSession<PagedLocalSnapshot<int, Task>, TaskFailure>,
      TaskFailure
    >
  >
  open() async {
    try {
      final watch = await store.watch();
      return Ok<
        ReactiveSourceSession<PagedLocalSnapshot<int, Task>, TaskFailure>
      >(_TaskStoreSession(store, watch));
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    }
  }
}

final class _TaskStoreSession
    implements
        ReactiveSourceSession<PagedLocalSnapshot<int, Task>, TaskFailure> {
  const _TaskStoreSession(this.store, this.watch);

  final OfflineTaskStore store;
  final TaskStoreWatch watch;

  @override
  Stream<void> get signals => watch.signals;

  @override
  Future<Result<PagedLocalSnapshot<int, Task>, TaskFailure>> read(
    CancellationSignal signal,
  ) => store.readSnapshot(signal);

  @override
  Future<void> close() => watch.disposeAsync();
}

final class _TaskCrashReporter implements CommandCrashReporter {
  const _TaskCrashReporter(this.crashes);

  final List<Object> crashes;

  @override
  void report(Object error, StackTrace stackTrace) => crashes.add(error);
}

Future<void> _waitForInitialLocalSnapshot(
  LiveResource<PagedLocalSnapshot<int, Task>, TaskFailure> local,
) async {
  if (local.state
      is ResourceReady<PagedLocalSnapshot<int, Task>, TaskFailure>) {
    return;
  }
  final ready = Completer<void>();
  void changed() {
    if (local.state
        case ResourceReady<PagedLocalSnapshot<int, Task>, TaskFailure>()) {
      if (!ready.isCompleted) ready.complete();
    }
  }

  local.addListener(changed);
  changed();
  try {
    await ready.future.timeout(const Duration(seconds: 3));
  } finally {
    local.removeListener(changed);
  }
}
