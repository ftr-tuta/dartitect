import 'package:drift/drift.dart';

part 'drift_fixture_database.g.dart';

/// Consumer-owned Drift rows for a bounded context distinct from ObjectBox.
class DriftFixtureOrders extends Table {
  TextColumn get id => text()();

  TextColumn get description => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Consumer-owned outbox colocated with the Drift bounded context.
class DriftFixtureOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get payload => text()();
}

/// Generated consumer database accepting an app-provided executor.
@DriftDatabase(tables: <Type>[DriftFixtureOrders, DriftFixtureOutbox])
class CoexistenceDriftDatabase extends _$CoexistenceDriftDatabase {
  CoexistenceDriftDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
