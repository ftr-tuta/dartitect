import 'package:drift/drift.dart';

part 'fixture_database.g.dart';

/// Consumer-owned `Task(id, title, version, status)` canary domain table.
class FixtureTasks extends Table {
  TextColumn get id => text()();

  TextColumn get title => text()();

  IntColumn get version => integer().withDefault(const Constant<int>(1))();

  TextColumn get status => text().withDefault(const Constant<String>('open'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Managed operational outbox used by the vertical integration fixture.
class FixtureOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get taskId => text()();

  TextColumn get title => text()();

  IntColumn get expectedVersion => integer()();

  TextColumn get status => text()();

  TextColumn get idempotencyKey => text().unique()();
}

/// Managed operational checkpoint used by the vertical integration fixture.
class FixtureCheckpoints extends Table {
  TextColumn get key => text()();

  TextColumn get checkpoint => text()();

  IntColumn get fencingToken => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// Managed synchronization journal used by the vertical integration fixture.
class FixtureJournal extends Table {
  TextColumn get attemptId => text()();

  IntColumn get sequence => integer()();

  DateTimeColumn get timestamp => dateTime()();

  IntColumn get fact => integer()();

  TextColumn get datasetKey => text().nullable()();

  BoolColumn get hasDatasetKey => boolean()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{attemptId, sequence};
}

/// Managed fencing lease used to reject stale headless writers.
class FixtureLeases extends Table {
  TextColumn get dataset => text()();

  TextColumn get owner => text()();

  IntColumn get fencingToken => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

/// Managed delivery receipt keyed by the durable idempotency key.
class FixtureReceipts extends Table {
  TextColumn get idempotencyKey => text()();

  TextColumn get disposition => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{idempotencyKey};
}

/// Consumer Task table plus the managed operational fragment for the canary.
@DriftDatabase(
  tables: <Type>[
    FixtureTasks,
    FixtureOutbox,
    FixtureCheckpoints,
    FixtureJournal,
    FixtureLeases,
    FixtureReceipts,
  ],
)
class DriftFixtureDatabase extends _$DriftFixtureDatabase {
  /// Creates the generated database around a consumer-provided [executor].
  DriftFixtureDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(fixtureTasks, fixtureTasks.version);
        await migrator.addColumn(fixtureTasks, fixtureTasks.status);
      }
      if (from < 3) {
        await migrator.createTable(fixtureOutbox);
        await migrator.createTable(fixtureCheckpoints);
        await migrator.createTable(fixtureJournal);
        await migrator.createTable(fixtureLeases);
        await migrator.createTable(fixtureReceipts);
      }
    },
  );
}
