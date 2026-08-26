import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_objectbox/dartitect_objectbox.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../../../objectbox.g.dart';
import '../application/offline_task_store.dart';
import '../domain/task.dart';
import '../domain/task_repository.dart';
import 'task_records.dart';

/// Native authoritative store backed by a real generated ObjectBox model.
final class ObjectBoxOfflineTaskStore implements OfflineTaskStore {
  ObjectBoxOfflineTaskStore._(this._owner)
    : _executor = ObjectBoxProjectionExecutor<int, int>(
        store: _owner.store,
        project: _nativeChecksum,
      );

  /// Opens an owned Store. A supplied directory remains caller-owned.
  static Future<ObjectBoxOfflineTaskStore> open({String? directoryPath}) async {
    final owner = await ObjectBoxStoreOwner.create(
      openStore: (path) => openStore(directory: path),
      directoryPath: directoryPath,
    );
    return ObjectBoxOfflineTaskStore._(owner);
  }

  final ObjectBoxStoreOwner _owner;
  final ObjectBoxProjectionExecutor<int, int> _executor;
  final Set<_ObjectBoxTaskWatch> _watches = <_ObjectBoxTaskWatch>{};
  var _query = '';
  var _visibleLimit = 50;
  var _revision = 0;
  var _disposed = false;

  Box<TaskRecord> get _tasks => _owner.store.box<TaskRecord>();
  Box<OutboxRecord> get _outbox => _owner.store.box<OutboxRecord>();
  Box<SyncCheckpointRecord> get _syncCheckpoints =>
      _owner.store.box<SyncCheckpointRecord>();

  @override
  late final SyncRunJournal<String> syncJournal =
      ObjectBoxSyncRunJournal<String>(
        store: _owner.store,
        appendEntry: _appendJournalEntry,
        readIncompleteAttempts: _readIncompleteAttempts,
      );

  @override
  final TaskStoreDiagnostics diagnostics = TaskStoreDiagnostics();

  @override
  bool get isNativeObjectBox => true;

  @override
  Future<void> seed(int count) async {
    _ensureActive();
    if (_tasks.count() != 0) return;
    _owner.store.runInTransaction<void>(TxMode.write, () {
      _tasks.putMany(<TaskRecord>[
        for (var id = 1; id <= count; id += 1)
          TaskRecord(
            id: id,
            title: id == 1
                ? 'Inspect explicit composition'
                : 'Field task ${id.toString().padLeft(5, '0')}',
            completed: false,
            version: 1,
            syncState: EntitySyncState.synced.name,
          ),
      ]);
    });
    _revision += 1;
  }

  @override
  Future<TaskStoreWatch> watch() async {
    _ensureActive();
    final watch = _ObjectBoxTaskWatch(this, _tasks.query());
    _watches.add(watch);
    await watch.start();
    return watch;
  }

  @override
  void select(TaskCursor cursor, {required bool reset}) {
    _ensureActive();
    _query = cursor.query.trim().toLowerCase();
    if (reset) _visibleLimit = 50;
    _revision += 1;
    for (final watch in _watches.toList(growable: false)) {
      watch.publish();
    }
  }

  @override
  Future<Result<PagedLocalSnapshot<int, Task>, TaskFailure>> readSnapshot(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final query = _tasks.query().build();
    diagnostics.activeQueries += 1;
    try {
      final records = await query.findAsync();
      signal.throwIfCancelled();
      records.sort((left, right) => left.id.compareTo(right.id));
      final tasks = records
          .where((record) => record.title.toLowerCase().contains(_query))
          .take(_visibleLimit)
          .map(_taskFromRecord)
          .toList(growable: false);
      return Ok<PagedLocalSnapshot<int, Task>>(
        PagedLocalSnapshot<int, Task>(revision: _revision, items: tasks),
      );
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    } finally {
      query.close();
      diagnostics.activeQueries -= 1;
    }
  }

  @override
  Future<Result<PageWriteReceipt<TaskCursor>, TaskFailure>> writePage(
    PageWrite<TaskCursor, Task> write,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    try {
      _owner.store.runInTransaction<void>(TxMode.write, () {
        _tasks.putMany(write.items.map(_recordFromTask).toList());
      });
      _visibleLimit = write.reset
          ? write.items.length
          : _visibleLimit + write.items.length;
      _revision += 1;
      return Ok<PageWriteReceipt<TaskCursor>>(
        PageWriteReceipt<TaskCursor>(
          localRevision: _revision,
          nextCursor: write.nextCursor,
        ),
      );
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    }
  }

  @override
  Future<Result<void, TaskFailure>> applyLocalAndEnqueue(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    try {
      _owner.store.runInTransaction<void>(TxMode.write, () {
        final task = _tasks.get(operation.key);
        if (task == null) throw StateError('Missing task row.');
        task
          ..completed = operation.argument.completed
          ..version += 1
          ..syncState = EntitySyncState.pending.name;
        _tasks.put(task);
        _outbox.put(_recordFromOperation(operation));
      });
      _revision += 1;
      return const Ok<void>(null);
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    }
  }

  @override
  Future<Result<void, TaskFailure>> markState(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    try {
      _owner.store.runInTransaction<void>(TxMode.write, () {
        final existing = _findOutbox(operation.idempotencyKey);
        _outbox.put(_recordFromOperation(operation, id: existing?.id ?? 0));
        final task = _tasks.get(operation.key);
        if (task != null) {
          task
            ..version += 1
            ..syncState = operation.syncState.name;
          _tasks.put(task);
        }
      });
      _revision += 1;
      return const Ok<void>(null);
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    }
  }

  @override
  Future<Result<List<OutboxOperation<int, TaskMutation>>, TaskFailure>>
  loadRecoverable(CancellationSignal signal) async {
    signal.throwIfCancelled();
    try {
      return Ok<List<OutboxOperation<int, TaskMutation>>>(
        _outbox.getAll().map(_operationFromRecord).toList(growable: false),
      );
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    }
  }

  @override
  Future<Result<void, TaskFailure>> compensate(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    try {
      _owner.store.runInTransaction<void>(TxMode.write, () {
        final task = _tasks.get(operation.key);
        if (task != null) {
          task
            ..completed = !operation.argument.completed
            ..version += 1
            ..syncState = EntitySyncState.synced.name;
          _tasks.put(task);
        }
        final outbox = _findOutbox(operation.idempotencyKey);
        if (outbox != null) _outbox.remove(outbox.id);
      });
      _revision += 1;
      return const Ok<void>(null);
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    }
  }

  @override
  Future<int?> read(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    return _findCheckpoint(key)?.checkpoint;
  }

  @override
  Future<void> write(
    String key,
    int checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    _owner.store.runInTransaction<void>(TxMode.write, () {
      final existing = _findCheckpoint(key);
      final previousFence = existing == null || existing.fencingToken == 0
          ? null
          : existing.fencingToken;
      if (fencingToken != null &&
          previousFence != null &&
          fencingToken < previousFence) {
        throw StateError('Stale checkpoint fencing token.');
      }
      _syncCheckpoints.put(
        SyncCheckpointRecord(
          id: existing?.id ?? 0,
          datasetKey: key,
          checkpoint: checkpoint,
          fencingToken: fencingToken ?? previousFence ?? 0,
        ),
      );
    });
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    final existing = _findCheckpoint(key);
    if (existing != null) _syncCheckpoints.remove(existing.id);
  }

  @override
  Future<int> backgroundChecksum() async {
    _ensureActive();
    final cancellation = CancellationSource();
    diagnostics.activeBackgroundTasks += 1;
    try {
      final result = await _executor.execute(
        const TransferableProjectionRequest<int>(generation: 1, payload: 0),
        cancellation.signal,
      );
      return result.value;
    } finally {
      cancellation.dispose();
      diagnostics.activeBackgroundTasks -= 1;
    }
  }

  @override
  Future<Task?> findTask(int id) async {
    final record = _tasks.get(id);
    return record == null ? null : _taskFromRecord(record);
  }

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    for (final watch in _watches.toList(growable: false)) {
      await watch.disposeAsync();
    }
    _watches.clear();
    await _executor.disposeAsync();
    await _owner.disposeAsync();
    diagnostics.disposed = true;
  }

  OutboxRecord? _findOutbox(String key) {
    for (final record in _outbox.getAll()) {
      if (record.idempotencyKey == key) return record;
    }
    return null;
  }

  SyncCheckpointRecord? _findCheckpoint(String key) {
    for (final record in _syncCheckpoints.getAll()) {
      if (record.datasetKey == key) return record;
    }
    return null;
  }

  void _watchOpened() {
    diagnostics.activeWatchers += 1;
  }

  void _queryOpened() {
    diagnostics.activeQueries += 1;
  }

  void _queryClosed() {
    diagnostics.activeQueries -= 1;
  }

  void _watchClosed(_ObjectBoxTaskWatch watch) {
    if (_watches.remove(watch)) diagnostics.activeWatchers -= 1;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('ObjectBoxOfflineTaskStore is disposed.');
  }
}

final class _ObjectBoxTaskWatch implements TaskStoreWatch {
  _ObjectBoxTaskWatch(this.store, this.builder);

  final ObjectBoxOfflineTaskStore store;
  final QueryBuilder<TaskRecord> builder;
  final StreamController<void> controller = StreamController<void>.broadcast(
    sync: true,
  );
  final List<Query<TaskRecord>> queries = <Query<TaskRecord>>[];
  StreamSubscription<Query<TaskRecord>>? subscription;
  var disposed = false;

  @override
  Stream<void> get signals => controller.stream;

  Future<void> start() async {
    store._watchOpened();
    subscription = builder.watch(triggerImmediately: false).listen((query) {
      if (disposed) {
        query.close();
        return;
      }
      queries.add(query);
      store._queryOpened();
      publish();
    });
  }

  void publish() {
    if (!disposed) controller.add(null);
  }

  @override
  Future<void> disposeAsync() async {
    if (disposed) return;
    disposed = true;
    await subscription?.cancel();
    subscription = null;
    for (final query in queries.reversed) {
      query.close();
      store._queryClosed();
    }
    queries.clear();
    store._watchClosed(this);
    await controller.close();
  }
}

Task _taskFromRecord(TaskRecord record) => Task(
  id: record.id,
  title: record.title,
  completed: record.completed,
  version: record.version,
  syncState: EntitySyncState.values.byName(record.syncState),
);

TaskRecord _recordFromTask(Task task) => TaskRecord(
  id: task.id,
  title: task.title,
  completed: task.completed,
  version: task.version,
  syncState: task.syncState.name,
);

OutboxRecord _recordFromOperation(
  OutboxOperation<int, TaskMutation> operation, {
  int id = 0,
}) => OutboxRecord(
  id: id,
  idempotencyKey: operation.idempotencyKey,
  taskId: operation.key,
  completed: operation.argument.completed,
  attempt: operation.attempt,
  syncState: operation.syncState.name,
);

OutboxOperation<int, TaskMutation> _operationFromRecord(OutboxRecord record) =>
    OutboxOperation<int, TaskMutation>(
      idempotencyKey: record.idempotencyKey,
      key: record.taskId,
      argument: TaskMutation(
        taskId: record.taskId,
        completed: record.completed,
      ),
      attempt: record.attempt,
      syncState: EntitySyncState.values.byName(record.syncState),
    );

void _appendJournalEntry(Store store, SyncJournalEntry<String> entry) {
  store.box<SyncJournalRecord>().put(
    SyncJournalRecord(
      attemptId: entry.attemptId,
      sequence: entry.sequence,
      timestampMicros: entry.timestamp.microsecondsSinceEpoch,
      fact: entry.fact.name,
      datasetKey: entry.hasDatasetKey ? '${entry.datasetKey}' : '',
      hasDatasetKey: entry.hasDatasetKey,
    ),
  );
}

List<IncompleteSyncAttempt<String>> _readIncompleteAttempts(Store store) {
  final records = store.box<SyncJournalRecord>().getAll()
    ..sort((left, right) {
      final attempt = left.attemptId.compareTo(right.attemptId);
      return attempt != 0 ? attempt : left.sequence.compareTo(right.sequence);
    });
  final entries = <SyncJournalEntry<String>>[
    for (final record in records)
      SyncJournalEntry<String>(
        attemptId: record.attemptId,
        sequence: record.sequence,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(
          record.timestampMicros,
          isUtc: true,
        ),
        fact: SyncJournalFact.values.byName(record.fact),
        datasetKey: record.hasDatasetKey ? record.datasetKey : null,
        hasDatasetKey: record.hasDatasetKey,
      ),
  ];
  final grouped = <String, List<SyncJournalEntry<String>>>{};
  for (final entry in entries) {
    (grouped[entry.attemptId] ??= <SyncJournalEntry<String>>[]).add(entry);
  }
  return <IncompleteSyncAttempt<String>>[
    for (final group in grouped.values)
      if (!group.any(
            (entry) =>
                entry.fact == SyncJournalFact.attemptCompleted ||
                entry.fact == SyncJournalFact.attemptCrashed,
          ) &&
          group.any((entry) => entry.fact == SyncJournalFact.attemptStarted))
        IncompleteSyncAttempt<String>(
          attemptId: group.first.attemptId,
          startedAt: group
              .firstWhere(
                (entry) => entry.fact == SyncJournalFact.attemptStarted,
              )
              .timestamp,
          completedDatasetKeys: <String>[
            for (final entry in group)
              if (entry.fact == SyncJournalFact.datasetSucceeded)
                entry.datasetKey!,
          ],
        ),
  ];
}

FutureOr<int> _nativeChecksum(Store store, int seed) {
  final query = store.box<TaskRecord>().query().build();
  try {
    return query.find().fold<int>(
      seed,
      (checksum, record) => checksum + record.id + record.version,
    );
  } finally {
    query.close();
  }
}
