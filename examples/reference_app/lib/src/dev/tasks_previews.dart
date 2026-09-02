// Preview annotations are deliberately dev-only and never runtime-reachable.
// ignore_for_file: depend_on_referenced_packages

import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart';
import 'package:flutter/material.dart';

import '../../features/tasks/domain/task.dart';
import '../../features/tasks/presentation/tasks_page.dart';

const _previewTask = Task(
  id: 1,
  title: 'Synthetic local-first task',
  completed: false,
);

/// Discovers actual reusable task widgets from immutable synthetic values.
@DartitectPreviewMatrix()
Widget referenceTasksPreview() =>
    const MaterialApp(home: Scaffold(body: _ReferenceTasksPreviewSurface()));

final class _ReferenceTasksPreviewSurface extends StatelessWidget {
  const _ReferenceTasksPreviewSurface();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final row = TaskRow(
        task: _previewTask,
        selected: true,
        onSelect: _pureNoOp,
        onToggle: _pureNoOp,
      );
      final details = const TaskDetails(
        task: _previewTask,
        onToggle: _pureNoOp,
      );
      if (constraints.maxWidth < 600) {
        return Column(
          children: <Widget>[
            row,
            Expanded(child: details),
          ],
        );
      }
      return Row(
        children: <Widget>[
          Expanded(child: row),
          const VerticalDivider(width: 1),
          SizedBox(width: 360, child: details),
        ],
      );
    },
  );
}

void _pureNoOp() {}
