import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_first_task_session.dart';
import 'package:dartitect_reference_app/features/tasks/application/task_remote.dart';
import 'package:dartitect_reference_app/features/tasks/domain/task_repository.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/objectbox_offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/reference_task_remote.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ObjectBox Task and operational UIDs stay frozen', () {
    final model = jsonDecode(
      File('${_packageRoot().path}/lib/objectbox-model.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final entities = (model['entities']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      <String, Object?>{
        for (final entity in entities) entity['name']! as String: entity['id'],
      },
      <String, Object?>{
        'TaskRecord': '1:731904221560000001',
        'OutboxRecord': '2:731904221560000002',
        'SyncJournalRecord': '3:731904221560000003',
        'SyncCheckpointRecord': '4:731904221560000004',
      },
    );
    final task = entities.singleWhere(
      (entity) => entity['name'] == 'TaskRecord',
    );
    expect(
      (task['properties']! as List<Object?>).cast<Map<String, Object?>>().map(
        (property) => '${property['name']}:${property['id']}',
      ),
      <String>[
        'id:1:731904221560000101',
        'title:2:731904221560000102',
        'completed:3:731904221560000103',
        'version:4:731904221560000104',
        'syncState:5:731904221560000105',
      ],
    );
  });

  test(
    'ObjectBox survives offline process restart and recovers the outbox',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dartitect-reference-objectbox-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      final firstStore = await ObjectBoxOfflineTaskStore.open(
        directoryPath: directory.path,
      );
      final first = await LocalFirstTaskRepository.create(
        store: firstStore,
        remote: ReferenceTaskRemote(mode: ReferenceRemoteMode.offline),
      );
      final queued = _execution(await first.toggle(7));
      expect(queued.disposition, CommitDisposition.queued);
      expect((await first.store.findTask(7))?.completed, isTrue);
      final firstDiagnostics = first.store.diagnostics;
      await first.disposeAsync();
      expect(firstDiagnostics.disposed, isTrue);
      expect(firstDiagnostics.activeQueries, 0);
      expect(firstDiagnostics.activeWatchers, 0);

      final secondStore = await ObjectBoxOfflineTaskStore.open(
        directoryPath: directory.path,
      );
      final second = await LocalFirstTaskRepository.create(
        store: secondStore,
        remote: ReferenceTaskRemote(),
      );
      expect((await second.store.findTask(7))?.completed, isTrue);
      expect(
        (await second.store.findTask(7))?.syncState,
        EntitySyncState.pending,
      );

      final recovered = await second.reconnect();
      expect(recovered, isA<Ok<Object?>>());
      expect(second.mutations.recoveredOperationCount, 1);
      expect(
        (await second.store.findTask(7))?.syncState,
        EntitySyncState.synced,
      );
      expect(await second.store.backgroundChecksum(), greaterThan(10000));
      final syncReport = await second.runMaintenanceSync();
      expect(syncReport.succeeded, isTrue);
      expect(syncReport.datasets.single.confirmedCheckpoint, 1);
      expect(await second.runBackgroundProjection(5000), const Ok<int>(10000));

      final checkpointSource = CancellationSource();
      expect(
        await second.store.read('maintenance', checkpointSource.signal),
        1,
      );
      checkpointSource.dispose();

      final secondDiagnostics = second.store.diagnostics;
      final secondSessionDiagnostics = second.diagnostics;
      await second.disposeAsync();
      expect(secondDiagnostics.activeBackgroundTasks, 0);
      expect(secondDiagnostics.activeQueries, 0);
      expect(secondDiagnostics.activeWatchers, 0);
      expect(secondSessionDiagnostics.activeIsolateWorkers, 0);
      expect(secondDiagnostics.disposed, isTrue);
    },
    skip: Platform.environment['DARTITECT_NATIVE_OBJECTBOX'] == '1'
        ? false
        : 'Run through verify --native-objectbox after verified setup.',
  );
}

Directory _packageRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final document =
          jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      final packages = document['packages']! as List<Object?>;
      final entry = packages.cast<Map<String, Object?>>().singleWhere(
        (candidate) => candidate['name'] == 'dartitect_reference_app',
      );
      return Directory.fromUri(config.uri.resolve(entry['rootUri']! as String));
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Dart package configuration was not found.');
    }
    directory = directory.parent;
  }
}

MutationExecution<TaskMutation, int, void, TaskFailure> _execution(
  CommandOutcome<
    MutationExecution<TaskMutation, int, void, TaskFailure>,
    TaskFailure
  >
  outcome,
) =>
    (outcome
            as CommandSucceeded<
              MutationExecution<TaskMutation, int, void, TaskFailure>,
              TaskFailure
            >)
        .value;
