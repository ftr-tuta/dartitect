// Drift declarations are provider schema rather than a consumer-facing API.
// ignore_for_file: public_member_api_docs

import 'package:drift/drift.dart';

part 'drift_task_database.g.dart';

/// Authoritative task rows for the optional Drift engine.
class DriftTaskRows extends Table {
  IntColumn get id => integer()();
  TextColumn get title => text()();
  BoolColumn get completed => boolean()();
  IntColumn get version => integer()();
  TextColumn get syncState => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Durable mutation outbox colocated with Drift task rows.
class DriftTaskOutboxRows extends Table {
  TextColumn get idempotencyKey => text()();
  IntColumn get taskId => integer()();
  BoolColumn get completed => boolean()();
  IntColumn get attempt => integer()();
  TextColumn get syncState => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{idempotencyKey};
}

/// Provider-local synchronization checkpoints.
class DriftTaskCheckpointRows extends Table {
  TextColumn get key => text()();
  IntColumn get checkpoint => integer()();
  IntColumn get fencingToken => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// Payload-free synchronization journal facts.
class DriftTaskJournalRows extends Table {
  TextColumn get attemptId => text()();
  IntColumn get sequence => integer()();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get fact => integer()();
  TextColumn get datasetKey => text().nullable()();
  BoolColumn get hasDatasetKey => boolean()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{attemptId, sequence};
}

/// Generated consumer-owned Drift database for one selected task engine.
@DriftDatabase(
  tables: <Type>[
    DriftTaskRows,
    DriftTaskOutboxRows,
    DriftTaskCheckpointRows,
    DriftTaskJournalRows,
  ],
)
final class DriftTaskDatabase extends _$DriftTaskDatabase {
  /// Creates the database around an application-selected executor.
  DriftTaskDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
