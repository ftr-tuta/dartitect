import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../application/offline_task_store.dart';
import '../domain/task.dart';
import '../domain/task_repository.dart';

/// Web/test fallback that preserves the same ownership and outbox contracts.
final class MemoryOfflineTaskStore implements OfflineTaskStore {
  final Map<int, Task> _tasks = <int, Task>{};
  final Map<String, OutboxOperation<int, TaskMutation>> _outbox =
      <String, OutboxOperation<int, TaskMutation>>{};
  final Map<String, int> _checkpoints = <String, int>{};
  final Set<_MemoryTaskWatch> _watches = <_MemoryTaskWatch>{};
  var _query = '';
  var _visibleLimit = 50;
  var _revision = 0;
  var _disposed = false;

  @override
  final TaskStoreDiagnostics diagnostics = TaskStoreDiagnostics();

  @override
  final SyncRunJournal<String> syncJournal = _MemorySyncRunJournal();

  @override
  bool get isNativeObjectBox => false;

  @override
  String get engineName => 'memory';

  @override
  Future<void> seed(int count) async {
    _ensureActive();
    if (_tasks.isNotEmpty) return;
    for (var id = 1; id <= count; id += 1) {
      _tasks[id] = Task(
        id: id,
        title: id == 1
            ? 'Inspect explicit composition'
            : 'Field task ${id.toString().padLeft(5, '0')}',
      );
    }
    _publish();
  }

  @override
  Future<TaskStoreWatch> watch() async {
    _ensureActive();
    final watch = _MemoryTaskWatch(this);
    _watches.add(watch);
    diagnostics
      ..activeWatchers += 1
      ..activeQueries += 1;
    return watch;
  }

  @override
  void select(TaskCursor cursor, {required bool reset}) {
    _ensureActive();
    _query = cursor.query.trim().toLowerCase();
    if (reset) _visibleLimit = 50;
    _publish();
  }

  @override
  Future<Result<PagedLocalSnapshot<int, Task>, TaskFailure>> readSnapshot(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final filtered = _tasks.values
        .where((task) => task.title.toLowerCase().contains(_query))
        .take(_visibleLimit)
        .toList(growable: false);
    return Ok<PagedLocalSnapshot<int, Task>>(
      PagedLocalSnapshot<int, Task>(revision: _revision, items: filtered),
    );
  }

  @override
  Future<Result<PageWriteReceipt<TaskCursor>, TaskFailure>> writePage(
    PageWrite<TaskCursor, Task> write,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    for (final task in write.items) {
      _tasks[task.id] = task;
    }
    _visibleLimit = write.reset
        ? write.items.length
        : _visibleLimit + write.items.length;
    _publish();
    return Ok<PageWriteReceipt<TaskCursor>>(
      PageWriteReceipt<TaskCursor>(
        localRevision: _revision,
        nextCursor: write.nextCursor,
      ),
    );
  }

  @override
  Future<Result<void, TaskFailure>> applyLocalAndEnqueue(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final current = _tasks[operation.key];
    if (current == null) {
      return Err<TaskFailure>(const TaskStorageFailure(), StackTrace.current);
    }
    _tasks[operation.key] = current.withCompletion(
      operation.argument.completed,
      EntitySyncState.pending,
    );
    _outbox[operation.idempotencyKey] = operation;
    _publish();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void, TaskFailure>> markState(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    _outbox[operation.idempotencyKey] = operation;
    final current = _tasks[operation.key];
    if (current != null) {
      _tasks[operation.key] = Task(
        id: current.id,
        title: current.title,
        completed: current.completed,
        version: current.version + 1,
        syncState: operation.syncState,
      );
    }
    _publish();
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<OutboxOperation<int, TaskMutation>>, TaskFailure>>
  loadRecoverable(CancellationSignal signal) async {
    signal.throwIfCancelled();
    return Ok<List<OutboxOperation<int, TaskMutation>>>(
      List<OutboxOperation<int, TaskMutation>>.of(_outbox.values),
    );
  }

  @override
  Future<Result<void, TaskFailure>> compensate(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final current = _tasks[operation.key];
    if (current != null) {
      _tasks[operation.key] = current.withCompletion(
        !operation.argument.completed,
        EntitySyncState.synced,
      );
    }
    _outbox.remove(operation.idempotencyKey);
    _publish();
    return const Ok<void>(null);
  }

  @override
  Future<int?> read(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    return _checkpoints[key];
  }

  @override
  Future<void> write(
    String key,
    int checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    _checkpoints[key] = checkpoint;
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    _checkpoints.remove(key);
  }

  @override
  Future<int> backgroundChecksum() async {
    _ensureActive();
    final executor = IsolateProjectionExecutor<List<int>, int>(
      project: _checksumVersions,
    );
    final cancellation = CancellationSource();
    diagnostics.activeBackgroundTasks += 1;
    try {
      final result = await executor.execute(
        TransferableProjectionRequest<List<int>>(
          generation: 1,
          payload: _tasks.values.map((task) => task.version).toList(),
        ),
        cancellation.signal,
      );
      return result.value;
    } finally {
      cancellation.dispose();
      await executor.disposeAsync();
      diagnostics.activeBackgroundTasks -= 1;
    }
  }

  @override
  Future<Task?> findTask(int id) async => _tasks[id];

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    for (final watch in _watches.toList(growable: false)) {
      await watch.disposeAsync();
    }
    _watches.clear();
    diagnostics.disposed = true;
  }

  void _publish() {
    _revision += 1;
    for (final watch in _watches.toList(growable: false)) {
      watch.publish();
    }
  }

  void _closeWatch(_MemoryTaskWatch watch) {
    if (!_watches.remove(watch)) return;
    diagnostics
      ..activeWatchers -= 1
      ..activeQueries -= 1;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('MemoryOfflineTaskStore is disposed.');
  }
}

final class _MemorySyncRunJournal implements SyncRunJournal<String> {
  final List<SyncJournalEntry<String>> entries = <SyncJournalEntry<String>>[];

  @override
  Future<void> append(SyncJournalEntry<String> entry) async {
    entries.add(entry);
  }

  @override
  Future<List<IncompleteSyncAttempt<String>>> loadIncompleteAttempts() async =>
      _incompleteAttempts(entries);
}

List<IncompleteSyncAttempt<String>> _incompleteAttempts(
  Iterable<SyncJournalEntry<String>> entries,
) {
  final grouped = <String, List<SyncJournalEntry<String>>>{};
  for (final entry in entries) {
    (grouped[entry.attemptId] ??= <SyncJournalEntry<String>>[]).add(entry);
  }
  final output = <IncompleteSyncAttempt<String>>[];
  for (final group in grouped.values) {
    group.sort((left, right) => left.sequence.compareTo(right.sequence));
    if (group.any(
      (entry) =>
          entry.fact == SyncJournalFact.attemptCompleted ||
          entry.fact == SyncJournalFact.attemptCrashed,
    )) {
      continue;
    }
    final started = group.where(
      (entry) => entry.fact == SyncJournalFact.attemptStarted,
    );
    if (started.isEmpty) continue;
    output.add(
      IncompleteSyncAttempt<String>(
        attemptId: group.first.attemptId,
        startedAt: started.first.timestamp,
        completedDatasetKeys: <String>[
          for (final entry in group)
            if (entry.fact == SyncJournalFact.datasetSucceeded)
              entry.datasetKey!,
        ],
      ),
    );
  }
  return List<IncompleteSyncAttempt<String>>.unmodifiable(output);
}

final class _MemoryTaskWatch implements TaskStoreWatch {
  _MemoryTaskWatch(this.store);

  final MemoryOfflineTaskStore store;
  final StreamController<void> controller = StreamController<void>(sync: true);
  var disposed = false;

  @override
  Stream<void> get signals => _ImmediateCancelStream<void>(controller.stream);

  void publish() {
    if (!disposed) controller.add(null);
  }

  @override
  Future<void> disposeAsync() {
    if (disposed) return Future<void>.value();
    disposed = true;
    store._closeWatch(this);
    // The only subscription is cancelled by LiveResource before this owner
    // closes the watch. `close()` marks the controller terminal synchronously;
    // awaiting its done-delivery future here can deadlock a Flutter fake-async
    // teardown after the last listener has already detached.
    unawaited(controller.close());
    return Future<void>.value();
  }
}

/// Deterministic test-stream wrapper whose logical detach is synchronous.
///
/// The memory store has no provider cleanup behind subscription cancellation;
/// its controller remains explicitly owned and closed by [_MemoryTaskWatch].
final class _ImmediateCancelStream<T> extends Stream<T> {
  const _ImmediateCancelStream(this._source);

  final Stream<T> _source;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _ImmediateCancelSubscription<T>(
    _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

final class _ImmediateCancelSubscription<T> implements StreamSubscription<T> {
  const _ImmediateCancelSubscription(this._inner);

  final StreamSubscription<T> _inner;

  @override
  Future<void> cancel() {
    unawaited(_inner.cancel());
    return Future<void>.value();
  }

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}

int _checksumVersions(List<int> versions) =>
    versions.fold<int>(0, (sum, version) => sum + version);
