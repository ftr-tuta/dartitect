import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../domain/tasks_repository.dart';
import '../composition/tasks_composition.dart';
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
      CommandIdleState<List<String>, TasksFailure>() ||
      CommandRunningState<List<String>, TasksFailure>() => const Text(
        'Loading Tasks',
      ),
      CommandSuccessState<List<String>, TasksFailure>(:final value) => Text(
        value.isEmpty ? 'No Tasks' : value.join(', '),
      ),
      CommandFailureState<List<String>, TasksFailure>() => const Text(
        'Tasks unavailable',
      ),
      CommandCrashState<List<String>, TasksFailure>() => const Text(
        'Unexpected Tasks failure',
      ),
      CommandCancelledState<List<String>, TasksFailure>() => const Text(
        'Tasks cancelled',
      ),
    },
  );
}
