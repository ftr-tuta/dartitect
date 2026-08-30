import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import 'composition/application_module.wiring.dartitect.g.dart';
import 'composition/canary_factories.dart';
import 'features/paved_road/composition/paved_road.wiring.dartitect.g.dart';

void main() => runDartitectApplication<ApplicationGraph>(
  create: ApplicationModule.create,
  loading: const MaterialApp(home: _Status('Bootstrapping')),
  application: (graph) => CanaryApp(graph: graph),
);

final class CanaryApp extends StatelessWidget {
  const CanaryApp({required this.graph, super.key});

  final ApplicationGraph graph;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: PavedRoadFeatureHost(
      graph: graph,
      factory: const PavedRoadFactory(),
      loading: (_) => const _Status('Loading feature'),
      failure: (_, failure, retry) => _Failure(retry: retry),
      ready: (_, runtime, viewModel) => CanaryScreen(viewModel: viewModel),
    ),
  );
}

final class CanaryScreen extends StatelessWidget {
  const CanaryScreen({required this.viewModel, super.key});

  final CanaryViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dartitect paved-road canary')),
    body: Center(
      child: ListenableBuilder(
        listenable: viewModel.doubled,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('value ${viewModel.counter.value}'),
            Text('lazy ${viewModel.doubled.value}'),
            FilledButton(
              onPressed: viewModel.increment,
              child: const Text('Increment local state'),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _Status extends StatelessWidget {
  const _Status(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

final class _Failure extends StatelessWidget {
  const _Failure({required this.retry});

  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(onPressed: retry, child: const Text('Retry')),
    ),
  );
}
