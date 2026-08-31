// GENERATED CODE - DO NOT EDIT BY HAND.
// Operational schema only; domain tables and queries remain consumer-owned.
// ignore_for_file: public_member_api_docs

import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

const int primaryDartitectDriftSchemaVersion = 2;

class PrimaryDartitectOutboxRows extends Table {
  TextColumn get id => text()();
  TextColumn get dataset => text()();
  TextColumn get idempotencyKey => text().unique()();
  BlobColumn get payload => blob()();
  TextColumn get state => text()();
  IntColumn get attempt => integer().withDefault(const Constant<int>(0))();
  IntColumn get createdAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class PrimaryDartitectCheckpointRows extends Table {
  TextColumn get dataset => text()();
  BlobColumn get checkpoint => blob()();
  IntColumn get fencingToken => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class PrimaryDartitectJournalRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get attemptId => text()();
  IntColumn get sequence => integer()();
  TextColumn get fact => text()();
  IntColumn get recordedAtMicros => integer()();
}

class PrimaryDartitectLeaseRows extends Table {
  TextColumn get dataset => text()();
  TextColumn get owner => text()();
  IntColumn get fencingToken => integer()();
  IntColumn get expiresAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class PrimaryDartitectReceiptRows extends Table {
  TextColumn get operationId => text()();
  TextColumn get status => text()();
  IntColumn get recordedAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{operationId};
}

class PrimaryDartitectTransferCheckpointRows extends Table {
  TextColumn get transferId => text()();
  IntColumn get committedOffset => integer()();
  IntColumn get revision => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{transferId};
}

/// Include these tables in the consumer-owned Drift database declaration.
abstract final class PrimaryDartitectDriftFragment {
  static const List<Type> tables = <Type>[
    PrimaryDartitectOutboxRows,
    PrimaryDartitectCheckpointRows,
    PrimaryDartitectJournalRows,
    PrimaryDartitectLeaseRows,
    PrimaryDartitectReceiptRows,
    PrimaryDartitectTransferCheckpointRows,
  ];

  static final OperationalStorageContextManifest manifest =
      OperationalStorageContextManifest(
        context: 'primary',
        provider: 'drift',
        schemaVersion: primaryDartitectDriftSchemaVersion,
        datasets: <OperationalDatasetRegistration>[
          OperationalDatasetRegistration(
            feature: 'tasks',
            dataset: 'tasks',
            partition: 'default_partition',
            codec: 'tasks_v1',
            retention: 'indefinite',
            transactionBoundary: 'tasks_transaction',
          ),
        ],
        migrations: <OperationalStorageMigration>[
          OperationalStorageMigration(
            fromVersion: 1,
            toVersion: 2,
            id: 'context_scoped_operational_tables',
          ),
        ],
      );
}
