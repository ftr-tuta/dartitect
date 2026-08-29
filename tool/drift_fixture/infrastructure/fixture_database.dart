import 'package:drift/drift.dart';

part 'fixture_database.g.dart';

/// Consumer-owned domain table used only by integration fixtures.
class FixtureItems extends Table {
  TextColumn get id => text()();

  TextColumn get value => text()();

  IntColumn get revision => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Consumer-owned durable outbox table used only by integration fixtures.
class FixtureOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get payload => text()();
}

/// Consumer-owned checkpoint table used only by integration fixtures.
class FixtureCheckpoints extends Table {
  TextColumn get key => text()();

  TextColumn get checkpoint => text()();

  IntColumn get fencingToken => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// Consumer-owned synchronization journal table used by integration fixtures.
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

/// Fixture database whose schema, migration, and executor stay app-owned.
@DriftDatabase(
  tables: <Type>[
    FixtureItems,
    FixtureOutbox,
    FixtureCheckpoints,
    FixtureJournal,
  ],
)
class DriftFixtureDatabase extends _$DriftFixtureDatabase {
  /// Creates the generated database around a consumer-provided [executor].
  DriftFixtureDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(fixtureItems, fixtureItems.revision);
      }
    },
  );
}
