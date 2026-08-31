import 'package:flutter/material.dart';

import '../composition/application_module.wiring.dartitect.g.dart';
import '../features/tasks/application/tasks_mutation.dart';
import '../features/tasks/composition/tasks.wiring.dartitect.g.dart';
import '../features/tasks/composition/tasks_factory.dart';
import '../features/tasks/presentation/tasks_view.dart';

final class ThinConsumerApp extends StatelessWidget {
  const ThinConsumerApp({required this.graph, super.key});

  final ApplicationGraph graph;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ThinConsumerCanary',
    home: TasksFeatureHost(
      graph: graph,
      factory: const TasksFactory(),
      start: (viewModel) => viewModel.start(),
      loading: (_) => const Text('Loading Tasks'),
      failure: (_, failure, retry) =>
          TextButton(onPressed: retry, child: const Text('Retry Tasks')),
      ready: (_, runtime, viewModel) => TasksView(
        viewModel: viewModel,
        onToggle: (id) async {
          await runtime.mutationCommand.execute(
            id,
            TasksMutation(aggregateId: id),
          );
          await viewModel.loadCommand.execute();
        },
      ),
    ),
  );
}
