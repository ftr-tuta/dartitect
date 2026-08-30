import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../composition/tasks_composition.dart';
import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';
import 'tasks_view_model.dart';

/// Composition boundary for the Tasks feature.
final class TasksPage extends StatelessWidget {
  const TasksPage({required this.repository, super.key});

  final TasksRepository repository;

  @override
  Widget build(BuildContext context) => ViewModelHost<TasksViewModel>.create(
    create: () => TasksComposition.createViewModel(repository),
    start: (viewModel) => viewModel.start(),
    builder: (context, viewModel) => TasksView(viewModel: viewModel),
  );
}

final class TasksView extends StatelessWidget {
  const TasksView({required this.viewModel, super.key});

  final TasksViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, child) => switch (viewModel.loadCommand.state) {
      CommandIdleState<List<Task>, TasksFailure>() ||
      CommandRunningState<List<Task>, TasksFailure>() => const Text(
        'Loading Tasks',
      ),
      CommandSuccessState<List<Task>, TasksFailure>(:final value) => Text(
        value.isEmpty ? 'No Tasks' : value.map((task) => task.title).join(', '),
      ),
      CommandFailureState<List<Task>, TasksFailure>() => const Text(
        'Tasks unavailable',
      ),
      CommandCrashState<List<Task>, TasksFailure>() => const Text(
        'Unexpected Tasks failure',
      ),
      CommandCancelledState<List<Task>, TasksFailure>() => const Text(
        'Tasks cancelled',
      ),
    },
  );
}
