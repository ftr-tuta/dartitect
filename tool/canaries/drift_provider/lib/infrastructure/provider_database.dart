import 'package:drift/drift.dart';

part 'provider_database.g.dart';

/// Consumer-owned feature rows.
class ProviderRows extends Table {
  /// Stable consumer identifier.
  TextColumn get id => text()();

  /// Consumer payload kept outside the adapter.
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Consumer-owned durable synchronization checkpoints.
class ProviderCheckpoints extends Table {
  /// Dataset key.
  TextColumn get key => text()();

  /// Confirmed checkpoint.
  IntColumn get checkpoint => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// Generated consumer database with an injected executor.
@DriftDatabase(tables: <Type>[ProviderRows, ProviderCheckpoints])
class ProviderDatabase extends _$ProviderDatabase {
  /// Creates the database over consumer-selected storage.
  ProviderDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
