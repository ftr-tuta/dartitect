import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';
import 'tasks_view_model.dart';

final class TasksView extends StatelessWidget {
  const TasksView({required this.viewModel, this.onToggle, super.key});

  final TasksViewModel viewModel;
  final Future<void> Function(String id)? onToggle;

  @override
  Widget build(BuildContext context) =>
      CommandStateBuilder<List<Task>, TasksFailure>(
        command: viewModel.loadCommand,
        idle: (_, state) => const Text('Loading Tasks'),
        running: (_, state) => const Text('Loading Tasks'),
        success: (_, state) => state.value.isEmpty
            ? const Text('No Tasks')
            : Column(
                children: <Widget>[
                  for (final task in state.value)
                    TextButton(
                      onPressed: onToggle == null
                          ? null
                          : () async => onToggle!(task.id),
                      child: Column(
                        children: <Widget>[
                          Text(task.title),
                          Text('Status: ${task.status.name}'),
                        ],
                      ),
                    ),
                ],
              ),
        failure: (_, state) => const Text('Tasks unavailable'),
        crashed: (_, state) => const Text('Unexpected Tasks failure'),
        cancelled: (_, state) => const Text('Tasks cancelled'),
      );
}
