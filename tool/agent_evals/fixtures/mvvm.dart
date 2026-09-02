import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: TasksPage()));

final class Task {
  const Task(this.title);

  final String title;
}

final class TaskRemoteService {
  Future<List<Task>> load() async => const <Task>[Task('Synthetic task')];
}

final class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

final class _TasksPageState extends State<TasksPage> {
  final remote = TaskRemoteService();
  var tasks = const <Task>[];

  @override
  void initState() {
    super.initState();
    remote.load().then((value) => setState(() => tasks = value));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tasks')),
    body: ListView(
      children: tasks.map((task) => ListTile(title: Text(task.title))).toList(),
    ),
  );
}
