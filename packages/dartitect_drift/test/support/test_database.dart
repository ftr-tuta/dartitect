import 'package:drift/drift.dart';

part 'test_database.g.dart';

class DomainItems extends Table {
  TextColumn get id => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get payload => text()();
}

class CheckpointRows extends Table {
  TextColumn get key => text()();

  TextColumn get checkpoint => text()();

  IntColumn get fencingToken => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

class JournalRows extends Table {
  TextColumn get attemptId => text()();

  IntColumn get sequence => integer()();

  DateTimeColumn get timestamp => dateTime()();

  IntColumn get fact => integer()();

  TextColumn get datasetKey => text().nullable()();

  BoolColumn get hasDatasetKey => boolean()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{attemptId, sequence};
}

@DriftDatabase(
  tables: <Type>[DomainItems, OutboxEntries, CheckpointRows, JournalRows],
)
class TestDatabase extends _$TestDatabase {
  TestDatabase(super.executor, {this.closeFailure});

  final Object? closeFailure;
  int closeCount = 0;

  @override
  int get schemaVersion => 1;

  @override
  Future<void> close() async {
    closeCount += 1;
    await super.close();
    if (closeFailure case final failure?) throw failure;
  }
}
