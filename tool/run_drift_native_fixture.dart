import 'dart:async';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'drift_fixture/executor.dart';
import 'drift_fixture/infrastructure/fixture_database.dart';

Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-drift-native-',
  );
  final file = File('${temporary.path}/fixture.sqlite');
  try {
    _createVersionOneDatabase(file);
    await _exerciseDatabase(file);
    stdout.writeln('Drift native fixture passed.');
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

void _createVersionOneDatabase(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
      CREATE TABLE fixture_items (
        id TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
    database.execute('''
      CREATE TABLE fixture_outbox (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        payload TEXT NOT NULL
      );
    ''');
    database.execute('''
      CREATE TABLE fixture_checkpoints (
        key TEXT NOT NULL PRIMARY KEY,
        checkpoint TEXT NOT NULL,
        fencing_token INTEGER NULL
      );
    ''');
    database.execute('''
      CREATE TABLE fixture_journal (
        attempt_id TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        fact INTEGER NOT NULL,
        dataset_key TEXT NULL,
        has_dataset_key INTEGER NOT NULL,
        PRIMARY KEY (attempt_id, sequence)
      );
    ''');
    database.execute(
      'INSERT INTO fixture_items (id, value) VALUES (?, ?)',
      <Object?>['legacy', 'migrated'],
    );
    database.execute('PRAGMA user_version = 1');
  } finally {
    database.close();
  }
}

Future<void> _exerciseDatabase(File file) async {
  final opened = await openDriftFixtureExecutor(
    databaseName: 'dartitect-native-fixture',
    databaseUri: file.uri,
    sqlite3Uri: Uri(),
    workerUri: Uri(),
  );
  if (opened.storageImplementation != 'nativeBackground') {
    throw StateError('Native fixture did not use the background executor.');
  }
  final owner = await DriftDatabaseOwner.create<DriftFixtureDatabase>(
    openDatabase: () => DriftFixtureDatabase(opened.executor),
    configure: (database) => database.customSelect('SELECT 1').getSingle(),
  );
  try {
    final database = owner.database;
    final legacy = await (database.select(
      database.fixtureItems,
    )..where((row) => row.id.equals('legacy'))).getSingle();
    if (legacy.value != 'migrated' || legacy.revision != 0) {
      throw StateError('Native migration did not preserve the legacy row.');
    }

    final emissions = <List<FixtureItem>>[];
    final initial = Completer<void>();
    final subscription = database
        .select(database.fixtureItems)
        .watch()
        .distinct(_sameItems)
        .listen((rows) {
          emissions.add(rows);
          if (!initial.isCompleted) initial.complete();
        });
    await initial.future;
    try {
      final transaction = DriftMutationTransaction<DriftFixtureDatabase>(
        database,
      );
      final committed = await transaction.run<String, _FixtureFailure>((
        db,
      ) async {
        await db
            .into(db.fixtureItems)
            .insert(
              FixtureItemsCompanion.insert(
                id: 'committed',
                value: 'created',
                revision: const Value<int>(1),
              ),
            );
        await db
            .into(db.fixtureOutbox)
            .insert(FixtureOutboxCompanion.insert(payload: 'item:committed'));
        return const Ok<String>('ok');
      });
      if (committed != const Ok<String>('ok')) {
        throw StateError('Native transaction did not return its result.');
      }
      await _waitFor(
        () => emissions.any((rows) => rows.any((row) => row.id == 'committed')),
      );

      final rolledBack = Err<_FixtureFailure>(
        const _FixtureFailure(),
        StackTrace.current,
      );
      final result = await transaction.run<void, _FixtureFailure>((db) async {
        await db
            .into(db.fixtureItems)
            .insert(
              FixtureItemsCompanion.insert(id: 'rolled-back', value: 'hidden'),
            );
        return rolledBack;
      });
      if (!identical(result, rolledBack)) {
        throw StateError('Native transaction replaced the expected failure.');
      }
      if (await (database.select(
            database.fixtureItems,
          )..where((row) => row.id.equals('rolled-back'))).getSingleOrNull() !=
          null) {
        throw StateError('Native rollback retained a domain row.');
      }
      if (emissions.any((rows) => rows.any((row) => row.id == 'rolled-back'))) {
        throw StateError('Native watch published a rolled-back row.');
      }

      await (database.update(
        database.fixtureItems,
      )..where((row) => row.id.equals('committed'))).write(
        const FixtureItemsCompanion(
          value: Value<String>('updated'),
          revision: Value<int>(2),
        ),
      );
      final updated = await (database.select(
        database.fixtureItems,
      )..where((row) => row.id.equals('committed'))).getSingle();
      if (updated.value != 'updated' || updated.revision != 2) {
        throw StateError('Native update did not persist.');
      }
      await (database.delete(
        database.fixtureItems,
      )..where((row) => row.id.equals('legacy'))).go();
    } finally {
      await subscription.cancel();
    }
  } finally {
    await owner.disposeAsync();
  }

  final reopenedExecutor = await openDriftFixtureExecutor(
    databaseName: 'dartitect-native-fixture',
    databaseUri: file.uri,
    sqlite3Uri: Uri(),
    workerUri: Uri(),
  );
  final reopened = await DriftDatabaseOwner.create<DriftFixtureDatabase>(
    openDatabase: () => DriftFixtureDatabase(reopenedExecutor.executor),
  );
  try {
    final rows = await reopened.database
        .select(reopened.database.fixtureItems)
        .get();
    if (rows.length != 1 ||
        rows.single.id != 'committed' ||
        rows.single.value != 'updated') {
      throw StateError('Native close/reopen persistence failed.');
    }
  } finally {
    await reopened.disposeAsync();
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
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Native watch did not publish the committed state.');
}

final class _FixtureFailure implements Exception {
  const _FixtureFailure();
}
