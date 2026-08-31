import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'composition/application_module.wiring.dartitect.g.dart';
import 'composition/canary_factories.dart';
import 'features/paved_road/composition/paved_road.wiring.dartitect.g.dart';
import 'presentation/ui_quality_shell.dart';

void main() => runDartitectApplication<ApplicationGraph>(
  create: ApplicationModule.create,
  loading: const MaterialApp(home: _Status('Bootstrapping')),
  application: (graph) => CanaryApp(graph: graph),
);

final class CanaryApp extends StatelessWidget {
  const CanaryApp({required this.graph, super.key});

  final ApplicationGraph graph;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: MediaQuery.platformBrightnessOf(context),
      ),
      builder: (context, child) =>
          Directionality(textDirection: textDirection, child: child!),
      home: PavedRoadFeatureHost(
        graph: graph,
        factory: const PavedRoadFactory(),
        loading: (_) => const _Status('Loading feature'),
        failure: (_, failure, retry) => _Failure(retry: retry),
        ready: (_, runtime, viewModel) => CanaryScreen(viewModel: viewModel),
      ),
    );
  }
}

final class CanaryScreen extends StatelessWidget {
  const CanaryScreen({required this.viewModel, super.key});

  final CanaryViewModel viewModel;

  @override
  Widget build(BuildContext context) => CanaryUiShell(
    body: Center(
      child: ListenableBuilder(
        listenable: viewModel.doubled,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('value ${viewModel.counter.value}'),
            Text('lazy ${viewModel.doubled.value}'),
            CommandStateBuilder<void, String>(
              command: viewModel.incrementCommand,
              idle: _incrementButton,
              running: (context, state) => Semantics(
                label: 'Incrementing local state',
                child: CircularProgressIndicator.adaptive(),
              ),
              success: _incrementButton,
              failure: _incrementButton,
              cancelled: _incrementButton,
              crashed: _incrementButton,
            ),
            Semantics(
              label: 'Use adaptive behavior',
              child: Switch.adaptive(value: true, onChanged: null),
            ),
            _PlatformConventionAction(
              onPressed: viewModel.incrementCommand.execute,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _incrementButton(BuildContext context, Object state) => FilledButton(
    onPressed: viewModel.incrementCommand.execute,
    child: const Text('Increment local state'),
  );
}

final class _PlatformConventionAction extends StatelessWidget {
  const _PlatformConventionAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      // A text-style action is an established Apple convention.
      return CupertinoButton(
        onPressed: onPressed,
        child: const Text('Apple-style secondary action'),
      );
    }
    return TextButton(
      onPressed: onPressed,
      child: const Text('Secondary action'),
    );
  }
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
