import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_first_task_session.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/domain/task_repository.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/memory_offline_task_store.dart';
import 'package:dartitect_reference_app/features/tasks/infrastructure/reference_task_remote.dart';
import 'package:dartitect_reference_app/features/tasks/presentation/tasks_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ViewModel restartLatest publishes only the current search generation',
    () async {
      final repository = await LocalFirstTaskRepository.create(
        store: MemoryOfflineTaskStore(),
        remote: ReferenceTaskRemote(),
      );
      final viewModel = TasksViewModel(repository);
      addTearDown(() async {
        await viewModel.disposeAsync();
        await repository.disposeAsync();
      });

      final stale = viewModel.searchCommand.execute('slow');
      final current = viewModel.searchCommand.execute('Field task 09999');

      expect(
        await stale,
        isA<
          CommandExecutionCancelled<PageWriteReceipt<TaskCursor>, TaskFailure>
        >(),
      );
      expect(
        await current,
        isA<
          CommandExecutionSucceeded<PageWriteReceipt<TaskCursor>, TaskFailure>
        >(),
      );
      expect(viewModel.query, 'Field task 09999');
      expect(viewModel.tasks.collection.keys.value, <int>[9999]);
      expect(viewModel.tasks.observationWaiterCount, 0);
      expect(viewModel.tasks.activeTimerCount, 0);
    },
  );

  test('ViewModel owns commands/effects and projects diagnostics', () async {
    final repository = await LocalFirstTaskRepository.create(
      store: MemoryOfflineTaskStore(),
      remote: ReferenceTaskRemote(),
    );
    final viewModel = TasksViewModel(repository);
    final received = <TasksEffect>[];
    final subscription = viewModel.effects.listen(received.add);

    expect(viewModel.ownedResourceCount, 6);
    expect(viewModel.forwardedListenerCount, 6);
    viewModel.selectTask(1);
    expect(viewModel.selectedTaskId, 1);

    viewModel.openDiagnostics();
    await Future<void>.delayed(Duration.zero);
    final diagnostics = received.whereType<OpenTasksDiagnosticsEffect>().single;
    expect(diagnostics.data.storeKind, 'memory');
    expect(diagnostics.data.activeWatchers, 1);

    await viewModel.connectivityCommand.execute(true);
    await viewModel.toggleCommand.execute(1, 1);
    await Future<void>.delayed(Duration.zero);
    expect(
      received.whereType<TasksMutationEffect>().single.result,
      TaskMutationPresentation.queued,
    );

    subscription.dispose();
    await viewModel.disposeAsync();
    expect(viewModel.isDisposed, isTrue);
    expect(viewModel.ownedResourceCount, 0);
    expect(viewModel.forwardedListenerCount, 0);
    expect(viewModel.effects.isDisposed, isTrue);
    await repository.disposeAsync();
  });
}
