import 'package:drift/drift.dart';

part 'drift_audit_database.g.dart';

/// Consumer-owned Drift table for the audit bounded context.
class AuditEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get message => text()();
}

/// Consumer-generated database accepting an app-owned executor.
@DriftDatabase(tables: <Type>[AuditEvents])
class AuditDatabase extends _$AuditDatabase {
  AuditDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
