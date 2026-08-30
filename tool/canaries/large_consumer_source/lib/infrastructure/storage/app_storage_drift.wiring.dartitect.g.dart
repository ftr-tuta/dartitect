// GENERATED CODE - DO NOT EDIT BY HAND.
// Operational schema only; domain tables and queries remain consumer-owned.
// ignore_for_file: public_member_api_docs

import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

const int appStorageDartitectDriftSchemaVersion = 2;

class AppStorageDartitectOutboxRows extends Table {
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

class AppStorageDartitectCheckpointRows extends Table {
  TextColumn get dataset => text()();
  BlobColumn get checkpoint => blob()();
  IntColumn get fencingToken => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class AppStorageDartitectJournalRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get attemptId => text()();
  IntColumn get sequence => integer()();
  TextColumn get fact => text()();
  IntColumn get recordedAtMicros => integer()();
}

class AppStorageDartitectLeaseRows extends Table {
  TextColumn get dataset => text()();
  TextColumn get owner => text()();
  IntColumn get fencingToken => integer()();
  IntColumn get expiresAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class AppStorageDartitectReceiptRows extends Table {
  TextColumn get operationId => text()();
  TextColumn get status => text()();
  IntColumn get recordedAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{operationId};
}

class AppStorageDartitectTransferCheckpointRows extends Table {
  TextColumn get transferId => text()();
  IntColumn get committedOffset => integer()();
  IntColumn get revision => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{transferId};
}

/// Include these tables in the consumer-owned Drift database declaration.
abstract final class AppStorageDartitectDriftFragment {
  static const List<Type> tables = <Type>[
    AppStorageDartitectOutboxRows,
    AppStorageDartitectCheckpointRows,
    AppStorageDartitectJournalRows,
    AppStorageDartitectLeaseRows,
    AppStorageDartitectReceiptRows,
    AppStorageDartitectTransferCheckpointRows,
  ];

  static final OperationalStorageContextManifest manifest =
      OperationalStorageContextManifest(
        context: 'app_storage',
        provider: 'drift',
        schemaVersion: appStorageDartitectDriftSchemaVersion,
        datasets: <OperationalDatasetRegistration>[
          OperationalDatasetRegistration(
            feature: 'cache_application_1',
            dataset: 'cache_application_1',
            partition: 'default_partition',
            codec: 'cache_application_1_v1',
            retention: 'indefinite',
            transactionBoundary: 'cache_application_1_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'cache_application_2',
            dataset: 'cache_application_2',
            partition: 'default_partition',
            codec: 'cache_application_2_v1',
            retention: 'indefinite',
            transactionBoundary: 'cache_application_2_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'cache_application_3',
            dataset: 'cache_application_3',
            partition: 'default_partition',
            codec: 'cache_application_3_v1',
            retention: 'indefinite',
            transactionBoundary: 'cache_application_3_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'local_application_1',
            dataset: 'local_application_1',
            partition: 'default_partition',
            codec: 'local_application_1_v1',
            retention: 'indefinite',
            transactionBoundary: 'local_application_1_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'local_application_2',
            dataset: 'local_application_2',
            partition: 'default_partition',
            codec: 'local_application_2_v1',
            retention: 'indefinite',
            transactionBoundary: 'local_application_2_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'local_application_3',
            dataset: 'local_application_3',
            partition: 'default_partition',
            codec: 'local_application_3_v1',
            retention: 'indefinite',
            transactionBoundary: 'local_application_3_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'offline_full_application_1',
            dataset: 'offline_full_application_1',
            partition: 'default_partition',
            codec: 'offline_full_application_1_v1',
            retention: 'indefinite',
            transactionBoundary: 'offline_full_application_1_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'offline_full_application_2',
            dataset: 'offline_full_application_2',
            partition: 'default_partition',
            codec: 'offline_full_application_2_v1',
            retention: 'indefinite',
            transactionBoundary: 'offline_full_application_2_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'offline_full_application_3',
            dataset: 'offline_full_application_3',
            partition: 'default_partition',
            codec: 'offline_full_application_3_v1',
            retention: 'indefinite',
            transactionBoundary: 'offline_full_application_3_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'replica_application_1',
            dataset: 'replica_application_1',
            partition: 'default_partition',
            codec: 'replica_application_1_v1',
            retention: 'indefinite',
            transactionBoundary: 'replica_application_1_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'replica_application_2',
            dataset: 'replica_application_2',
            partition: 'default_partition',
            codec: 'replica_application_2_v1',
            retention: 'indefinite',
            transactionBoundary: 'replica_application_2_transaction',
          ),
          OperationalDatasetRegistration(
            feature: 'replica_application_3',
            dataset: 'replica_application_3',
            partition: 'default_partition',
            codec: 'replica_application_3_v1',
            retention: 'indefinite',
            transactionBoundary: 'replica_application_3_transaction',
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
