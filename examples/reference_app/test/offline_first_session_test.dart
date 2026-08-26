import 'package:dartitect/dartitect.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_first_task_session.dart';
import 'package:dartitect_reference_app/features/tasks/application/task_remote.dart';
import 'package:dartitect_reference_app/features/tasks/domain/task_repository.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/memory_offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/reference_task_remote.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pages and switch-latest search keep the local store authoritative',
    () async {
      final session = await _memorySession();
      addTearDown(session.disposeAsync);

      expect(session.paged.collection.length.value, 50);
      expect(
        await session.refresh(),
        isA<CommandSucceeded<Object?, TaskFailure>>(),
      );
      expect(session.paged.collection.length.value, 50);
      expect(
        await session.loadMore(),
        isA<CommandSucceeded<Object?, TaskFailure>>(),
      );
      expect(session.paged.collection.length.value, 100);

      final stale = session.search('slow');
      final latest = session.search('Field task 09999');
      expect(await stale, isA<CommandCancelled<Object?, TaskFailure>>());
      expect(await latest, isA<CommandSucceeded<Object?, TaskFailure>>());
      expect(session.paged.collection.keys.value, <int>[9999]);
      expect(session.paged.observationWaiterCount, 0);
      expect(session.paged.activeTimerCount, 0);
    },
  );

  test(
    'offline mutation reconnects and duplicate delivery is idempotent',
    () async {
      final remote = ReferenceTaskRemote(mode: ReferenceRemoteMode.offline);
      final session = await _memorySession(remote: remote);
      addTearDown(session.disposeAsync);

      final queued = _execution(await session.toggle(1));
      expect(queued.disposition, CommitDisposition.queued);
      expect((await session.store.findTask(1))?.completed, isTrue);
      expect(
        (await session.store.findTask(1))?.syncState,
        EntitySyncState.pending,
      );

      final recovered = await session.reconnect();
      expect(recovered, isA<Ok<Object?>>());
      expect(
        (await session.store.findTask(1))?.syncState,
        EntitySyncState.synced,
      );
      expect(remote.diagnostics.appliedDeliveries, 1);

      final operations = (await _operations(session))
          .where((operation) => operation.key == 1);
      final redelivered = _execution(await session.redeliver(operations.last));
      expect(redelivered.disposition, CommitDisposition.committed);
      expect(remote.diagnostics.appliedDeliveries, 1);
      expect(remote.diagnostics.duplicateDeliveries, 1);
    },
  );

  test(
    'one mutation updates its item without signaling keys or neighbors',
    () async {
      final session = await _memorySession();
      addTearDown(session.disposeAsync);
      var keySignals = 0;
      var changedItemSignals = 0;
      var neighborSignals = 0;
      final changedItem = session.paged.collection.item(1);
      final neighbor = session.paged.collection.item(2);
      void keysChanged() => keySignals += 1;
      void itemChanged() => changedItemSignals += 1;
      void neighborChanged() => neighborSignals += 1;
      session.paged.collection.keys.addListener(keysChanged);
      changedItem.addListener(itemChanged);
      neighbor.addListener(neighborChanged);

      _execution(await session.toggle(1));
      await Future<void>.delayed(Duration.zero);

      expect(changedItemSignals, greaterThan(0));
      expect(keySignals, 0);
      expect(neighborSignals, 0);
      session.paged.collection.keys.removeListener(keysChanged);
      changedItem.removeListener(itemChanged);
      neighbor.removeListener(neighborChanged);
    },
  );

  test(
    'reject conflict and uncertain outcomes remain explicit and durable',
    () async {
      final session = await _memorySession();
      addTearDown(session.disposeAsync);

      for (final scenario in <(int, ReferenceRemoteMode, EntitySyncState)>[
        (2, ReferenceRemoteMode.reject, EntitySyncState.rejected),
        (3, ReferenceRemoteMode.conflict, EntitySyncState.conflicted),
        (4, ReferenceRemoteMode.uncertain, EntitySyncState.uncertain),
      ]) {
        session.remote.mode = scenario.$2;
        final execution = _execution(await session.toggle(scenario.$1));
        expect(execution.syncState, scenario.$3);
        expect((await session.store.findTask(scenario.$1))?.completed, isTrue);
        expect(
          (await session.store.findTask(scenario.$1))?.syncState,
          scenario.$3,
        );
      }
    },
  );

  test('unexpected delivery crash stops only its key until audited', () async {
    final remote = ReferenceTaskRemote(mode: ReferenceRemoteMode.crash);
    final session = await _memorySession(remote: remote);
    addTearDown(session.disposeAsync);

    await expectLater(session.toggle(5), throwsStateError);
    expect(session.mutations.stoppedKeyCount, 1);
    expect(session.diagnostics.crashes, hasLength(1));
    expect(
      (await session.store.findTask(5))?.syncState,
      EntitySyncState.uncertain,
    );

    final rejected = await session.toggle(5);
    expect(rejected, isA<CommandRejected<Object?, TaskFailure>>());
    expect(remote.diagnostics.mutationRequests, 0);

    remote.mode = ReferenceRemoteMode.online;
    final recovered = _execution(await session.auditAndResume(5));
    expect(recovered.disposition, CommitDisposition.committed);
    expect(session.mutations.stoppedKeyCount, 0);
    expect(
      (await session.store.findTask(5))?.syncState,
      EntitySyncState.synced,
    );
  });

  test(
    '10k sync, isolate projection, and teardown leave zero residual work',
    () async {
      final session = await _memorySession();
      final storeDiagnostics = session.store.diagnostics;
      final sessionDiagnostics = session.diagnostics;
      final remoteDiagnostics = session.remote.diagnostics;

      expect(await session.store.backgroundChecksum(), 10000);
      final syncReport = await session.runMaintenanceSync();
      expect(syncReport.succeeded, isTrue);
      expect(syncReport.datasets.single.confirmedCheckpoint, 1);
      expect(await session.runBackgroundProjection(21), const Ok<int>(42));
      expect(session.sync.activeRunCount, 0);
      expect(sessionDiagnostics.activeIsolateWorkers, 0);
      expect(storeDiagnostics.activeBackgroundTasks, 0);
      expect(storeDiagnostics.activeWatchers, 1);
      expect(storeDiagnostics.activeQueries, 1);
      expect(session.journal.length, 0);

      await session.disposeAsync();
      expect(storeDiagnostics.activeBackgroundTasks, 0);
      expect(storeDiagnostics.activeWatchers, 0);
      expect(storeDiagnostics.activeQueries, 0);
      expect(session.sync.activeRunCount, 0);
      expect(sessionDiagnostics.activeIsolateWorkers, 0);
      expect(storeDiagnostics.disposed, isTrue);
      expect(sessionDiagnostics.disposed, isTrue);
      expect(session.journal.isDisposed, isTrue);
      expect(remoteDiagnostics.closeCalls, 1);
    },
  );
}

Future<OfflineFirstTaskSession> _memorySession({ReferenceTaskRemote? remote}) =>
    OfflineFirstTaskSession.create(
      store: MemoryOfflineTaskStore(),
      remote: remote ?? ReferenceTaskRemote(),
    );

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

Future<List<OutboxOperation<int, TaskMutation>>> _operations(
  OfflineFirstTaskSession session,
) async {
  final source = CancellationSource();
  try {
    final result = await session.store.loadRecoverable(source.signal);
    return (result as Ok<List<OutboxOperation<int, TaskMutation>>>).value;
  } finally {
    source.dispose();
  }
}
