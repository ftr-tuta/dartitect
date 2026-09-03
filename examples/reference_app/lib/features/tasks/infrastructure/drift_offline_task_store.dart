import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../application/offline_task_store.dart';
import '../domain/task.dart';
import '../domain/task_repository.dart';
import 'drift_task_database.dart';

/// Authoritative Drift implementation of the common task-store contract.
///
/// Select this engine instead of Memory or ObjectBox. It never dual-writes or
/// migrates data between providers.
final class DriftOfflineTaskStore implements OfflineTaskStore {
  DriftOfflineTaskStore._(this._owner);

  /// Opens an owned in-memory Drift database for deterministic tests.
  static Future<DriftOfflineTaskStore> openInMemory() async {
    final owner = await DriftDatabaseOwner.create<DriftTaskDatabase>(
      openDatabase: () => DriftTaskDatabase(NativeDatabase.memory()),
    );
    return DriftOfflineTaskStore._(owner);
  }

  final DriftDatabaseOwner<DriftTaskDatabase> _owner;
  final Set<_DriftTaskWatch> _watches = <_DriftTaskWatch>{};
  var _query = '';
  var _visibleLimit = 50;
  var _revision = 0;
  var _disposed = false;

  DriftTaskDatabase get _database => _owner.database;

  late final DriftMutationTransaction<DriftTaskDatabase> _transactions =
      DriftMutationTransaction<DriftTaskDatabase>(_database);

  @override
  late final SyncRunJournal<String> syncJournal =
      DriftSyncRunJournal<String, DriftTaskDatabase>(
        database: _database,
        appendEntry: _appendJournalEntry,
        readIncompleteAttempts: _readIncompleteAttempts,
      );

  @override
  final TaskStoreDiagnostics diagnostics = TaskStoreDiagnostics();

  @override
  bool get isNativeObjectBox => false;

  @override
  String get engineName => 'Drift';

  @override
  Future<void> seed(int count) async {
    _ensureActive();
    if ((await _database.select(_database.driftTaskRows).get()).isNotEmpty) {
      return;
    }
    await _database.batch((batch) {
      batch.insertAll(_database.driftTaskRows, <DriftTaskRowsCompanion>[
        for (var id = 1; id <= count; id += 1)
          DriftTaskRowsCompanion.insert(
            id: Value<int>(id),
            title: id == 1
                ? 'Inspect explicit composition'
                : 'Field task ${id.toString().padLeft(5, '0')}',
            completed: false,
            version: 1,
            syncState: EntitySyncState.synced.name,
          ),
      ]);
    });
    _publish();
  }

  @override
  Future<TaskStoreWatch> watch() async {
    _ensureActive();
    final watch = _DriftTaskWatch(this);
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
    diagnostics.activeQueries += 1;
    try {
      final rows =
          await (_database.select(_database.driftTaskRows)
                ..orderBy(<OrderingTerm Function($DriftTaskRowsTable)>[
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      signal.throwIfCancelled();
      final tasks = rows
          .where((row) => row.title.toLowerCase().contains(_query))
          .take(_visibleLimit)
          .map(_taskFromRow)
          .toList(growable: false);
      return Ok<PagedLocalSnapshot<int, Task>>(
        PagedLocalSnapshot<int, Task>(revision: _revision, items: tasks),
      );
    } catch (_, stackTrace) {
      return Err<TaskFailure>(const TaskStorageFailure(), stackTrace);
    } finally {
      diagnostics.activeQueries -= 1;
    }
  }

  @override
  Future<Result<PageWriteReceipt<TaskCursor>, TaskFailure>> writePage(
    PageWrite<TaskCursor, Task> write,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final nextRevision = _revision + 1;
    final result = await _transactions
        .run<PageWriteReceipt<TaskCursor>, TaskFailure>((database) async {
          for (final task in write.items) {
            await database
                .into(database.driftTaskRows)
                .insertOnConflictUpdate(_companionFromTask(task));
          }
          signal.throwIfCancelled();
          return Ok<PageWriteReceipt<TaskCursor>>(
            PageWriteReceipt<TaskCursor>(
              localRevision: nextRevision,
              nextCursor: write.nextCursor,
            ),
          );
        });
    if (result is Ok<PageWriteReceipt<TaskCursor>>) {
      _visibleLimit = write.reset
          ? write.items.length
          : _visibleLimit + write.items.length;
      _publish();
    }
    return result;
  }

  @override
  Future<Result<void, TaskFailure>> applyLocalAndEnqueue(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final result = await _transactions.run<void, TaskFailure>((database) async {
      final current = await _findTaskRow(database, operation.key);
      if (current == null) {
        return Err<TaskFailure>(const TaskStorageFailure(), StackTrace.current);
      }
      await database
          .into(database.driftTaskRows)
          .insertOnConflictUpdate(
            DriftTaskRowsCompanion.insert(
              id: Value<int>(current.id),
              title: current.title,
              completed: operation.argument.completed,
              version: current.version + 1,
              syncState: EntitySyncState.pending.name,
            ),
          );
      await database
          .into(database.driftTaskOutboxRows)
          .insertOnConflictUpdate(_companionFromOperation(operation));
      signal.throwIfCancelled();
      return const Ok<void>(null);
    });
    if (result is Ok<void>) _publish();
    return result;
  }

  @override
  Future<Result<void, TaskFailure>> markState(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final result = await _transactions.run<void, TaskFailure>((database) async {
      await database
          .into(database.driftTaskOutboxRows)
          .insertOnConflictUpdate(_companionFromOperation(operation));
      final current = await _findTaskRow(database, operation.key);
      if (current != null) {
        await database
            .into(database.driftTaskRows)
            .insertOnConflictUpdate(
              DriftTaskRowsCompanion.insert(
                id: Value<int>(current.id),
                title: current.title,
                completed: current.completed,
                version: current.version + 1,
                syncState: operation.syncState.name,
              ),
            );
      }
      signal.throwIfCancelled();
      return const Ok<void>(null);
    });
    if (result is Ok<void>) _publish();
    return result;
  }

  @override
  Future<Result<List<OutboxOperation<int, TaskMutation>>, TaskFailure>>
  loadRecoverable(CancellationSignal signal) async {
    signal.throwIfCancelled();
    try {
      final rows = await _database.select(_database.driftTaskOutboxRows).get();
      signal.throwIfCancelled();
      return Ok<List<OutboxOperation<int, TaskMutation>>>(
        rows.map(_operationFromRow).toList(growable: false),
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
    final result = await _transactions.run<void, TaskFailure>((database) async {
      final current = await _findTaskRow(database, operation.key);
      if (current != null) {
        await database
            .into(database.driftTaskRows)
            .insertOnConflictUpdate(
              DriftTaskRowsCompanion.insert(
                id: Value<int>(current.id),
                title: current.title,
                completed: !operation.argument.completed,
                version: current.version + 1,
                syncState: EntitySyncState.synced.name,
              ),
            );
      }
      await (database.delete(database.driftTaskOutboxRows)..where(
            (row) => row.idempotencyKey.equals(operation.idempotencyKey),
          ))
          .go();
      signal.throwIfCancelled();
      return const Ok<void>(null);
    });
    if (result is Ok<void>) _publish();
    return result;
  }

  @override
  Future<int?> read(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    final row = await (_database.select(
      _database.driftTaskCheckpointRows,
    )..where((candidate) => candidate.key.equals(key))).getSingleOrNull();
    signal.throwIfCancelled();
    return row?.checkpoint;
  }

  @override
  Future<void> write(
    String key,
    int checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    await _database.transaction(() async {
      final current = await (_database.select(
        _database.driftTaskCheckpointRows,
      )..where((candidate) => candidate.key.equals(key))).getSingleOrNull();
      final previousFence = current?.fencingToken;
      if (fencingToken != null &&
          previousFence != null &&
          fencingToken < previousFence) {
        throw StateError('Stale checkpoint fencing token.');
      }
      await _database
          .into(_database.driftTaskCheckpointRows)
          .insertOnConflictUpdate(
            DriftTaskCheckpointRowsCompanion.insert(
              key: key,
              checkpoint: checkpoint,
              fencingToken: Value<int?>(fencingToken ?? previousFence),
            ),
          );
    });
    signal.throwIfCancelled();
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    await (_database.delete(
      _database.driftTaskCheckpointRows,
    )..where((candidate) => candidate.key.equals(key))).go();
    signal.throwIfCancelled();
  }

  @override
  Future<int> backgroundChecksum() async {
    _ensureActive();
    diagnostics.activeBackgroundTasks += 1;
    try {
      final rows = await _database.select(_database.driftTaskRows).get();
      return rows.fold<int>(
        0,
        (checksum, row) => checksum + row.id + row.version,
      );
    } finally {
      diagnostics.activeBackgroundTasks -= 1;
    }
  }

  @override
  Future<Task?> findTask(int id) async {
    final row = await _findTaskRow(_database, id);
    return row == null ? null : _taskFromRow(row);
  }

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    for (final watch in _watches.toList(growable: false)) {
      await watch.disposeAsync();
    }
    _watches.clear();
    await _owner.disposeAsync();
    diagnostics.disposed = true;
  }

  void _publish() {
    _revision += 1;
    for (final watch in _watches.toList(growable: false)) {
      watch.publish();
    }
  }

  void _closeWatch(_DriftTaskWatch watch) {
    if (!_watches.remove(watch)) return;
    diagnostics
      ..activeWatchers -= 1
      ..activeQueries -= 1;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('DriftOfflineTaskStore is disposed.');
  }
}

final class _DriftTaskWatch implements TaskStoreWatch {
  _DriftTaskWatch(this.store);

  final DriftOfflineTaskStore store;
  final StreamController<void> controller = StreamController<void>(sync: true);
  var disposed = false;

  @override
  Stream<void> get signals => controller.stream;

  void publish() {
    if (!disposed) controller.add(null);
  }

  @override
  Future<void> disposeAsync() {
    if (disposed) return Future<void>.value();
    disposed = true;
    store._closeWatch(this);
    unawaited(controller.close());
    return Future<void>.value();
  }
}

Future<DriftTaskRow?> _findTaskRow(DriftTaskDatabase database, int id) =>
    (database.select(
      database.driftTaskRows,
    )..where((row) => row.id.equals(id))).getSingleOrNull();

Task _taskFromRow(DriftTaskRow row) => Task(
  id: row.id,
  title: row.title,
  completed: row.completed,
  version: row.version,
  syncState: EntitySyncState.values.byName(row.syncState),
);

DriftTaskRowsCompanion _companionFromTask(Task task) =>
    DriftTaskRowsCompanion.insert(
      id: Value<int>(task.id),
      title: task.title,
      completed: task.completed,
      version: task.version,
      syncState: task.syncState.name,
    );

DriftTaskOutboxRowsCompanion _companionFromOperation(
  OutboxOperation<int, TaskMutation> operation,
) => DriftTaskOutboxRowsCompanion.insert(
  idempotencyKey: operation.idempotencyKey,
  taskId: operation.key,
  completed: operation.argument.completed,
  attempt: operation.attempt,
  syncState: operation.syncState.name,
);

OutboxOperation<int, TaskMutation> _operationFromRow(DriftTaskOutboxRow row) =>
    OutboxOperation<int, TaskMutation>(
      idempotencyKey: row.idempotencyKey,
      key: row.taskId,
      argument: TaskMutation(taskId: row.taskId, completed: row.completed),
      attempt: row.attempt,
      syncState: EntitySyncState.values.byName(row.syncState),
    );

Future<void> _appendJournalEntry(
  DriftTaskDatabase database,
  SyncJournalEntry<String> entry,
) => database
    .into(database.driftTaskJournalRows)
    .insert(
      DriftTaskJournalRowsCompanion.insert(
        attemptId: entry.attemptId,
        sequence: entry.sequence,
        timestamp: entry.timestamp,
        fact: entry.fact.index,
        datasetKey: Value<String?>(entry.datasetKey),
        hasDatasetKey: entry.hasDatasetKey,
      ),
    );

Future<List<IncompleteSyncAttempt<String>>> _readIncompleteAttempts(
  DriftTaskDatabase database,
) async {
  final rows =
      await (database.select(database.driftTaskJournalRows)
            ..orderBy(<OrderingTerm Function($DriftTaskJournalRowsTable)>[
              (row) => OrderingTerm.asc(row.attemptId),
              (row) => OrderingTerm.asc(row.sequence),
            ]))
          .get();
  final grouped = <String, List<DriftTaskJournalRow>>{};
  for (final row in rows) {
    (grouped[row.attemptId] ??= <DriftTaskJournalRow>[]).add(row);
  }
  return <IncompleteSyncAttempt<String>>[
    for (final group in grouped.values)
      if (!group.any(
            (row) =>
                SyncJournalFact.values[row.fact] ==
                    SyncJournalFact.attemptCompleted ||
                SyncJournalFact.values[row.fact] ==
                    SyncJournalFact.attemptCrashed,
          ) &&
          group.any(
            (row) =>
                SyncJournalFact.values[row.fact] ==
                SyncJournalFact.attemptStarted,
          ))
        IncompleteSyncAttempt<String>(
          attemptId: group.first.attemptId,
          startedAt: group
              .firstWhere(
                (row) =>
                    SyncJournalFact.values[row.fact] ==
                    SyncJournalFact.attemptStarted,
              )
              .timestamp,
          completedDatasetKeys: <String>[
            for (final row in group)
              if (SyncJournalFact.values[row.fact] ==
                  SyncJournalFact.datasetSucceeded)
                row.datasetKey!,
          ],
        ),
  ];
}
