import 'dart:io';

import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'drift_fixture/executor.dart';
import 'drift_fixture/infrastructure/fixture_database.dart';
import 'drift_fixture/task_vertical_canary.dart';

Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-task-vertical-native-',
  );
  final file = File('${temporary.path}/tasks.sqlite');
  try {
    _createVersionOneDatabase(file);
    await _exerciseVerticalFeature(file);
    stdout.writeln('Task vertical Drift native canary passed.');
  } finally {
    await _deleteTemporaryDirectory(temporary);
  }
}

Future<void> _deleteTemporaryDirectory(Directory directory) async {
  const attempts = 20;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    if (!await directory.exists()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == attempts) rethrow;
      // Windows can retain the SQLite file briefly after the background
      // executor has completed its awaited shutdown.
      await Future<void>.delayed(Duration(milliseconds: attempt * 25));
    }
  }
}

void _createVersionOneDatabase(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      CREATE TABLE fixture_tasks (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL
      );
    ''');
    database.execute(
      'INSERT INTO fixture_tasks (id, title) VALUES (?, ?)',
      <Object?>['legacy', 'Migrated task'],
    );
    database.execute('PRAGMA user_version = 1');
  } finally {
    database.close();
  }
}

Future<void> _exerciseVerticalFeature(File file) async {
  final first = await _open(file);
  final firstCanary = TaskVerticalCanary(first.database);
  await firstCanary.start();
  final legacy = await (first.database.select(
    first.database.fixtureTasks,
  )..where((row) => row.id.equals('legacy'))).getSingle();
  _require(
    legacy.title == 'Migrated task' &&
        legacy.version == 1 &&
        legacy.status == 'open',
    'v1 to v3 migration did not preserve the Task',
  );

  _require(
    await firstCanary.refresh(
      id: 'task-1',
      title: 'Observed from Drift',
      version: 4,
    ),
    'remote refresh was fenced unexpectedly',
  );
  _require(
    firstCanary.visibleTasks.any(
      (task) => task.id == 'task-1' && task.version == 4,
    ),
    'database-only UI did not observe the remote refresh',
  );

  try {
    await firstCanary.mutate(
      id: 'task-1',
      title: 'Must roll back',
      idempotencyKey: 'rolled-back-key',
      crashBeforeOutbox: true,
    );
    throw StateError('injected transaction crash was swallowed');
  } on StateError catch (error) {
    if (error.message == 'injected transaction crash was swallowed') rethrow;
  }
  final rolledBack = await (first.database.select(
    first.database.fixtureTasks,
  )..where((row) => row.id.equals('task-1'))).getSingle();
  _require(
    rolledBack.title == 'Observed from Drift' &&
        (await first.database.select(first.database.fixtureOutbox).get())
            .isEmpty,
    'local mutation and outbox were not atomic',
  );

  const uncertainKey = 'task-1-idempotency';
  await firstCanary.mutate(
    id: 'task-1',
    title: 'Offline edit',
    idempotencyKey: uncertainKey,
  );
  firstCanary.remoteMode = TaskCanaryRemoteMode.uncertain;
  _require(
    await firstCanary.deliver(uncertainKey) == 'uncertain',
    'uncertain delivery was hidden',
  );
  _require(
    await firstCanary.auditAndRetry(uncertainKey) == 'synced',
    'audited delivery did not recover',
  );
  await firstCanary.mutate(
    id: 'task-1',
    title: 'Idempotent replay',
    idempotencyKey: uncertainKey,
  );
  _require(
    await firstCanary.deliver(uncertainKey) == 'synced' &&
        firstCanary.evidence.appliedDeliveries == 1 &&
        firstCanary.evidence.duplicateDeliveries == 1,
    'delivery did not reuse and deduplicate its idempotency key',
  );

  const conflictKey = 'task-1-conflict';
  await firstCanary.mutate(
    id: 'task-1',
    title: 'Conflicting edit',
    idempotencyKey: conflictKey,
  );
  firstCanary.remoteMode = TaskCanaryRemoteMode.conflict;
  _require(
    await firstCanary.deliver(conflictKey) == 'conflicted',
    'conflict policy did not remain explicit',
  );
  await firstCanary.checkpoint(
    owner: 'foreground',
    fencingToken: 7,
    checkpoint: 'page-7',
  );
  await _expectStaleFence(firstCanary);

  final firstEvidence = firstCanary.evidence;
  await firstCanary.disposeAsync();
  _require(firstEvidence.closeCalls == 1, 'Dio was not closed exactly once');
  await first.disposeAsync();

  final restarted = await _open(file);
  final headless = TaskVerticalCanary(restarted.database);
  await headless.start();
  final pending = await restarted.database
      .select(restarted.database.fixtureOutbox)
      .get();
  _require(
    pending.single.idempotencyKey == conflictKey &&
        pending.single.status == 'conflicted',
    'restart did not recover the durable conflicted operation',
  );
  _require(
    await headless.auditAndRetry(conflictKey) == 'synced',
    'fresh headless graph did not recover the outbox',
  );
  await headless.checkpoint(
    owner: 'headless',
    fencingToken: 8,
    checkpoint: 'page-8',
  );
  final checkpoint = await (restarted.database.select(
    restarted.database.fixtureCheckpoints,
  )..where((row) => row.key.equals('tasks'))).getSingle();
  _require(
    checkpoint.checkpoint == 'page-8' && checkpoint.fencingToken == 8,
    'headless checkpoint did not respect the new fence',
  );
  _require(
    (await restarted.database.select(restarted.database.fixtureJournal).get())
            .length ==
        2,
    'durable journal did not survive restart',
  );

  await headless.holdNextRefresh();
  final delayed = headless.refresh(
    id: 'late-task',
    title: 'Must not survive logout',
    version: 1,
  );
  await headless.heldRefreshStarted;
  await headless.logout();
  headless.releaseRefresh();
  _require(!await delayed, 'old session refresh crossed logout generation');
  _require(
    (await restarted.database.select(restarted.database.fixtureTasks).get())
            .isEmpty &&
        headless.evidence.staleGenerationDrops == 1,
    'logout did not clear and fence session state',
  );

  final headlessEvidence = headless.evidence;
  await headless.disposeAsync();
  _require(
    headlessEvidence.closeCalls == 1,
    'headless graph transport did not tear down',
  );
  await restarted.disposeAsync();
}

Future<DriftDatabaseOwner<DriftFixtureDatabase>> _open(File file) async {
  final opened = await openDriftFixtureExecutor(
    databaseName: 'dartitect-task-vertical-native',
    databaseUri: file.uri,
    sqlite3Uri: Uri(),
    workerUri: Uri(),
  );
  _require(
    opened.storageImplementation == 'nativeBackground',
    'native canary did not use the background Drift executor',
  );
  return DriftDatabaseOwner.create<DriftFixtureDatabase>(
    openDatabase: () => DriftFixtureDatabase(opened.executor),
  );
}

Future<void> _expectStaleFence(TaskVerticalCanary canary) async {
  try {
    await canary.checkpoint(
      owner: 'stale-headless',
      fencingToken: 6,
      checkpoint: 'stale',
    );
  } on StateError catch (error) {
    if (error.message == 'stale fencing token') return;
    rethrow;
  }
  throw StateError('stale fencing token was accepted');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
