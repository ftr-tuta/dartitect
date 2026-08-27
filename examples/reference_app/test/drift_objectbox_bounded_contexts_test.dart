import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/objectbox_offline_task_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'infrastructure/drift_audit_database.dart';

void main() {
  test(
    'Drift and ObjectBox own separate bounded contexts without dual writes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-bounded-contexts-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final tasks = await ObjectBoxOfflineTaskStore.open(
        directoryPath: '${root.path}/tasks-objectbox',
      );
      final audit = await DriftDatabaseOwner.create<AuditDatabase>(
        openDatabase: () => AuditDatabase(
          NativeDatabase.createInBackground(
            File('${root.path}/audit-drift.sqlite'),
          ),
        ),
      );
      final auditTransactions = DriftMutationTransaction<AuditDatabase>(
        audit.database,
      );

      await tasks.seed(1);
      final result = await auditTransactions.run<void, StateError>((
        database,
      ) async {
        await database
            .into(database.auditEvents)
            .insert(AuditEventsCompanion.insert(message: 'audit-only'));
        return const Ok<void>(null);
      });

      expect(result, isA<Ok<void>>());
      expect((await tasks.findTask(1))?.title, isNotEmpty);
      expect(
        await audit.database.select(audit.database.auditEvents).get(),
        hasLength(1),
      );

      await tasks.disposeAsync();
      await audit.disposeAsync();
    },
    skip: Platform.environment['DARTITECT_NATIVE_OBJECTBOX'] == '1'
        ? false
        : 'Run through verify --native-objectbox after verified setup.',
  );
}
