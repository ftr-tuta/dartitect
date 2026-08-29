import 'dart:async';
import 'dart:js_interop';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:drift/drift.dart';
import 'package:web/web.dart' as web;

import '../drift_fixture/executor.dart';
import '../drift_fixture/infrastructure/fixture_database.dart';

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
    web.console.error('Drift fixture failed: $error\n$stackTrace'.toJS);
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
  final seeded = await _open(databaseName);
  _requireSafeStorage(seeded.storageImplementation);
  final versionOne = DriftFixtureDatabase(seeded.executor);
  await versionOne
      .into(versionOne.fixtureItems)
      .insert(FixtureItemsCompanion.insert(id: 'legacy', value: 'migrated'));
  await versionOne.customStatement(
    'ALTER TABLE fixture_items DROP COLUMN revision',
  );
  await versionOne.customStatement('PRAGMA user_version = 1');
  await versionOne.close();

  final migrated = await _open(databaseName);
  _requireSafeStorage(migrated.storageImplementation);
  final owner = await DriftDatabaseOwner.create<DriftFixtureDatabase>(
    openDatabase: () => DriftFixtureDatabase(migrated.executor),
  );
  try {
    final database = owner.database;
    final legacy = await (database.select(
      database.fixtureItems,
    )..where((row) => row.id.equals('legacy'))).getSingle();
    if (legacy.value != 'migrated' || legacy.revision != 0) {
      throw StateError('migration failed');
    }

    await database
        .into(database.fixtureItems)
        .insert(FixtureItemsCompanion.insert(id: 'crud', value: 'created'));
    final created = await (database.select(
      database.fixtureItems,
    )..where((row) => row.id.equals('crud'))).getSingle();
    if (created.value != 'created') throw StateError('insert/read failed');
    await (database.update(database.fixtureItems)
          ..where((row) => row.id.equals('crud')))
        .write(const FixtureItemsCompanion(value: Value<String>('updated')));
    final updated = await (database.select(
      database.fixtureItems,
    )..where((row) => row.id.equals('crud'))).getSingle();
    if (updated.value != 'updated') throw StateError('update failed');
    await (database.delete(
      database.fixtureItems,
    )..where((row) => row.id.equals('crud'))).go();
    if (await (database.select(
          database.fixtureItems,
        )..where((row) => row.id.equals('crud'))).getSingleOrNull() !=
        null) {
      throw StateError('delete failed');
    }

    final emissions = <List<FixtureItem>>[];
    final subscription = database
        .select(database.fixtureItems)
        .watch()
        .distinct(_sameItems)
        .listen(emissions.add);
    try {
      await _waitFor(() => emissions.isNotEmpty);
      final transaction = DriftMutationTransaction<DriftFixtureDatabase>(
        database,
      );
      await transaction.run<void, _WebFixtureFailure>((db) async {
        await db
            .into(db.fixtureItems)
            .insert(
              FixtureItemsCompanion.insert(id: 'committed', value: 'domain'),
            );
        await db
            .into(db.fixtureOutbox)
            .insert(FixtureOutboxCompanion.insert(payload: 'committed'));
        return const Ok<void>(null);
      });
      await _waitFor(
        () => emissions.any((rows) => rows.any((row) => row.id == 'committed')),
      );
      await transaction.run<void, _WebFixtureFailure>((db) async {
        await db
            .into(db.fixtureItems)
            .insert(
              FixtureItemsCompanion.insert(id: 'rolled-back', value: 'hidden'),
            );
        return Err<_WebFixtureFailure>(
          const _WebFixtureFailure(),
          StackTrace.current,
        );
      });
      if (await (database.select(
            database.fixtureItems,
          )..where((row) => row.id.equals('rolled-back'))).getSingleOrNull() !=
          null) {
        throw StateError('rollback failed');
      }
      if (emissions.any((rows) => rows.any((row) => row.id == 'rolled-back'))) {
        throw StateError('watch published rolled-back state');
      }
    } finally {
      await subscription.cancel();
    }
  } finally {
    await owner.disposeAsync();
  }

  final reopenedExecutor = await _open(databaseName);
  _requireSafeStorage(reopenedExecutor.storageImplementation);
  final reopened = DriftFixtureDatabase(reopenedExecutor.executor);
  final committed = await (reopened.select(
    reopened.fixtureItems,
  )..where((row) => row.id.equals('committed'))).getSingleOrNull();
  if (committed == null) throw StateError('close/reopen persistence failed');

  _status('READY:${reopenedExecutor.storageImplementation}');
  try {
    await _waitFor(
      () =>
          web.window.localStorage.getItem('dartitect-secondary-ready') ==
              databaseName &&
          web.window.localStorage.getItem('dartitect-primary-foreground') ==
              databaseName,
    );
    await reopened
        .into(reopened.fixtureItems)
        .insert(
          FixtureItemsCompanion.insert(
            id: 'cross-context',
            value: 'foreground',
          ),
        );
    _status('PASS:${reopenedExecutor.storageImplementation}:foreground');
    await _waitFor(
      () =>
          web.window.localStorage.getItem('dartitect-secondary-pass') ==
          databaseName,
    );
  } finally {
    await reopened.close();
  }
}

Future<void> _runSecondary(String databaseName) async {
  final opened = await _open(databaseName);
  _requireSafeStorage(opened.storageImplementation);
  final database = DriftFixtureDatabase(opened.executor);
  final initialSnapshot = Completer<void>();
  final crossContext = Completer<void>();
  final subscription = database
      .select(database.fixtureItems)
      .watch()
      .listen(
        (rows) {
          if (!initialSnapshot.isCompleted) initialSnapshot.complete();
          if (rows.any((row) => row.id == 'cross-context') &&
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

bool _sameItems(List<FixtureItem> left, List<FixtureItem> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 600; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('web fixture condition timed out');
}

void _status(String value) {
  web.document.body?.textContent = value;
  web.console.log(value.toJS);
}

final class _WebFixtureFailure implements Exception {
  const _WebFixtureFailure();
}
