import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/domain/task_repository.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/drift_offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/memory_offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/objectbox_offline_task_store.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Memory implements the authoritative task-store contract', () async {
    await _exerciseStore(MemoryOfflineTaskStore(), expectedEngine: 'memory');
  });

  test('Drift implements the authoritative task-store contract', () async {
    await _exerciseStore(
      await DriftOfflineTaskStore.openInMemory(),
      expectedEngine: 'Drift',
    );
  });

  test(
    'ObjectBox implements the authoritative task-store contract',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-objectbox-contract-',
      );
      try {
        await _exerciseStore(
          await ObjectBoxOfflineTaskStore.open(directoryPath: root.path),
          expectedEngine: 'ObjectBox',
        );
      } finally {
        if (root.existsSync()) await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['DARTITECT_NATIVE_OBJECTBOX'] == '1'
        ? false
        : 'Run through verify --native-objectbox after verified setup.',
  );
}

Future<void> _exerciseStore(
  OfflineTaskStore store, {
  required String expectedEngine,
}) async {
  final cancellation = CancellationSource();
  try {
    expect(store.engineName, expectedEngine);
    await store.seed(3);
    expect((await store.findTask(1))?.completed, isFalse);

    final operation = OutboxOperation<int, TaskMutation>(
      idempotencyKey: '$expectedEngine-task-1',
      key: 1,
      argument: const TaskMutation(taskId: 1, completed: true),
    );
    expect(
      await store.applyLocalAndEnqueue(operation, cancellation.signal),
      isA<Ok<void>>(),
    );
    expect((await store.findTask(1))?.completed, isTrue);
    final recoverable = await store.loadRecoverable(cancellation.signal);
    expect(
      (recoverable as Ok<List<OutboxOperation<int, TaskMutation>>>).value,
      hasLength(1),
    );

    expect(
      await store.markState(
        operation.withState(syncState: EntitySyncState.synced),
        cancellation.signal,
      ),
      isA<Ok<void>>(),
    );
    expect((await store.findTask(1))?.syncState, EntitySyncState.synced);

    await store.write('tasks', 7, cancellation.signal, fencingToken: 1);
    expect(await store.read('tasks', cancellation.signal), 7);

    final watch = await store.watch();
    expect(store.diagnostics.activeWatchers, 1);
    await watch.disposeAsync();
    expect(store.diagnostics.activeWatchers, 0);
  } finally {
    cancellation.dispose();
    await store.disposeAsync();
    expect(store.diagnostics.disposed, isTrue);
  }
}
