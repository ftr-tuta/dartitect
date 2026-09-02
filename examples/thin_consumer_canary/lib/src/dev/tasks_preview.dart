// Preview annotations are deliberately dev-only and never runtime-reachable.
// ignore_for_file: depend_on_referenced_packages

import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart';
import 'package:flutter/material.dart';

import '../../features/tasks/domain/tasks_model.dart';

/// Smoke preview built only from immutable synthetic task values.
@DartitectPreviewMatrix()
Widget thinConsumerTasksPreview() => const MaterialApp(
  home: Scaffold(
    body: _PreviewTaskTile(
      task: Task(id: 'preview', title: 'Synthetic preview task'),
    ),
  ),
);

final class _PreviewTaskTile extends StatelessWidget {
  const _PreviewTaskTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.task_alt),
    title: Text(task.title),
    subtitle: Text('Status: ${task.status.name}'),
  );
}
