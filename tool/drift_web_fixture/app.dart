import 'dart:async';
import 'dart:js_interop';

import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:web/web.dart' as web;

import '../drift_fixture/executor.dart';
import '../drift_fixture/infrastructure/fixture_database.dart';
import '../drift_fixture/task_vertical_canary.dart';

Future<void> main() async {
  try {
    final query = Uri.parse(web.window.location.href).queryParameters;
    final role = query['role'];
    final databaseName = query['database'];
    if (role == null || databaseName == null) {
      throw StateError('role and database query parameters are required');
    }
    switch (role) {
      case 'primary':
        await _runPrimary(databaseName);
      case 'secondary':
        await _runSecondary(databaseName);
      default:
        throw StateError('Unknown fixture role.');
    }
  } catch (error, stackTrace) {
    _status('FAIL:${error.runtimeType}');
    web.console.error(
      'Task vertical Drift fixture failed: $error\n$stackTrace'.toJS,
    );
  }
}

Future<DriftFixtureExecutor> _open(String databaseName) =>
    openDriftFixtureExecutor(
      databaseName: databaseName,
      databaseUri: Uri(),
      sqlite3Uri: Uri.parse('/sqlite3.wasm'),
      workerUri: Uri.parse('/drift_worker.dart.js'),
    );

Future<void> _runPrimary(String databaseName) async {
  await _seedVersionOne(databaseName);
  final firstExecutor = await _open(databaseName);
  _requireSafeStorage(firstExecutor.storageImplementation);
  final first = await DriftDatabaseOwner.create<DriftFixtureDatabase>(
    openDatabase: () => DriftFixtureDatabase(firstExecutor.executor),
  );
  final foreground = TaskVerticalCanary(first.database);
  await foreground.start();
  final legacy = await (first.database.select(
    first.database.fixtureTasks,
  )..where((row) => row.id.equals('legacy'))).getSingle();
  _require(
    legacy.title == 'Migrated web task' &&
        legacy.version == 1 &&
        legacy.status == 'open',
    'web migration did not preserve the v1 Task',
  );
  _require(
    await foreground.refresh(
      id: 'task-web',
      title: 'Observed from web Drift',
      version: 3,
    ),
    'web refresh was fenced unexpectedly',
  );
  const conflictKey = 'task-web-conflict';
  await foreground.mutate(
    id: 'task-web',
    title: 'Durable web conflict',
    idempotencyKey: conflictKey,
  );
  foreground.remoteMode = TaskCanaryRemoteMode.conflict;
  _require(
    await foreground.deliver(conflictKey) == 'conflicted',
    'web conflict was not durable',
  );
  await foreground.checkpoint(
    owner: 'web-foreground',
    fencingToken: 11,
    checkpoint: 'web-page-11',
  );
  await foreground.disposeAsync();
  await first.disposeAsync();

  final reopenedExecutor = await _open(databaseName);
  _requireSafeStorage(reopenedExecutor.storageImplementation);
  final reopened = await DriftDatabaseOwner.create<DriftFixtureDatabase>(
    openDatabase: () => DriftFixtureDatabase(reopenedExecutor.executor),
  );
  final headless = TaskVerticalCanary(reopened.database);
  await headless.start();
  final recovered = await reopened.database
      .select(reopened.database.fixtureOutbox)
      .getSingle();
  _require(
    recovered.idempotencyKey == conflictKey &&
        await headless.auditAndRetry(conflictKey) == 'synced',
    'fresh web graph did not recover its outbox',
  );
  await headless.checkpoint(
    owner: 'web-headless',
    fencingToken: 12,
    checkpoint: 'web-page-12',
  );

  _status('READY:${reopenedExecutor.storageImplementation}');
  try {
    await _waitFor(
      () =>
          web.window.localStorage.getItem('dartitect-secondary-ready') ==
              databaseName &&
          web.window.localStorage.getItem('dartitect-primary-foreground') ==
              databaseName,
    );
    _require(
      await headless.refresh(
        id: 'cross-context',
        title: 'Foreground database authority',
        version: 1,
      ),
      'cross-context refresh was fenced',
    );
    _status('PASS:${reopenedExecutor.storageImplementation}:foreground');
    await _waitFor(
      () =>
          web.window.localStorage.getItem('dartitect-secondary-pass') ==
          databaseName,
    );
  } finally {
    await headless.disposeAsync();
    await reopened.disposeAsync();
  }
}

Future<void> _seedVersionOne(String databaseName) async {
  final seeded = await _open(databaseName);
  _requireSafeStorage(seeded.storageImplementation);
  final versionOne = DriftFixtureDatabase(seeded.executor);
  await versionOne
      .into(versionOne.fixtureTasks)
      .insert(
        FixtureTasksCompanion.insert(id: 'legacy', title: 'Migrated web task'),
      );
  for (final table in <String>[
    'fixture_outbox',
    'fixture_checkpoints',
    'fixture_journal',
    'fixture_leases',
    'fixture_receipts',
  ]) {
    await versionOne.customStatement('DROP TABLE $table');
  }
  await versionOne.customStatement(
    'ALTER TABLE fixture_tasks DROP COLUMN version',
  );
  await versionOne.customStatement(
    'ALTER TABLE fixture_tasks DROP COLUMN status',
  );
  await versionOne.customStatement('PRAGMA user_version = 1');
  await versionOne.close();
}

Future<void> _runSecondary(String databaseName) async {
  final opened = await _open(databaseName);
  _requireSafeStorage(opened.storageImplementation);
  final database = DriftFixtureDatabase(opened.executor);
  final initialSnapshot = Completer<void>();
  final crossContext = Completer<void>();
  final subscription = database
      .select(database.fixtureTasks)
      .watch()
      .listen(
        (rows) {
          if (!initialSnapshot.isCompleted) initialSnapshot.complete();
          if (rows.any(
                (row) =>
                    row.id == 'cross-context' &&
                    row.title == 'Foreground database authority',
              ) &&
              !crossContext.isCompleted) {
            crossContext.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!initialSnapshot.isCompleted) {
            initialSnapshot.completeError(error, stackTrace);
          }
          if (!crossContext.isCompleted) {
            crossContext.completeError(error, stackTrace);
          }
        },
      );
  await initialSnapshot.future.timeout(const Duration(seconds: 30));
  web.window.localStorage.setItem('dartitect-secondary-ready', databaseName);
  _status('READY:${opened.storageImplementation}');
  try {
    await crossContext.future.timeout(const Duration(seconds: 30));
    web.window.localStorage.setItem('dartitect-secondary-pass', databaseName);
    _status('PASS:${opened.storageImplementation}:cross-context-watch');
  } finally {
    await subscription.cancel();
    await database.close();
  }
}

void _requireSafeStorage(String implementation) {
  if (implementation == 'unsafeIndexedDb' || implementation == 'inMemory') {
    throw StateError('unsafe storage implementation');
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('web fixture condition timed out');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _status(String value) {
  web.document.body?.textContent = value;
  web.console.log(value.toJS);
}
