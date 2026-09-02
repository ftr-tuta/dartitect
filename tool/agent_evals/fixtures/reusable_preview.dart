import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

final class TaskCard extends StatelessWidget {
  const TaskCard({required this.store, super.key});

  final File store;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(store.existsSync() ? store.readAsStringSync() : 'No task'),
    ),
  );
}

@Preview(name: 'task-card')
Widget previewTaskCard() => TaskCard(store: File('tasks.json'));

void main() => runApp(MaterialApp(home: previewTaskCard()));
