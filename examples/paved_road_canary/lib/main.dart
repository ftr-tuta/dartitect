import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/material.dart';

import 'features/paved_road/composition/paved_road.wiring.dartitect.g.dart';

void main() => runDartitectApplication<CanaryRuntime>(
  create: PavedRoadFeatureWiring.application(
    createModule: createCanaryFeatureModule,
  ),
  loading: const MaterialApp(home: _Status('Bootstrapping')),
  application: (runtime) => CanaryApp(runtime: runtime),
);

/// Materializes the consumer seams through the generated direct module.
Future<PavedRoadFeatureModule<CanaryRuntime, CanaryRuntime>>
createCanaryFeatureModule() async {
  final runtime = CanaryRuntime.create();
  return PavedRoadFeatureModule<CanaryRuntime, CanaryRuntime>(
    repository: runtime,
    persistenceProvider: const _CanaryPersistence(),
    transportProvider: const _CanaryTransportProvider(),
    resource: runtime.doubled,
    command: null,
    pagination: runtime.history,
    outbox: null,
    syncDataset: null,
    job: null,
    diagnostics: null,
    contractFixture: const _CanaryContractFixture(),
    createViewModel: (repository) => repository,
    dispose: runtime.disposeAsync,
  );
}

/// Owned state exposed only after the generated graph commits.
final class CanaryRuntime implements AsyncDisposable {
  CanaryRuntime._({
    required this.owner,
    required this.counter,
    required this.doubled,
    required this.history,
  });

  factory CanaryRuntime.create() {
    final owner = ReactiveOwner();
    final counter = owner.value<int>(0);
    return CanaryRuntime._(
      owner: owner,
      counter: counter,
      doubled: owner.lazyComputed<int>(
        label: 'canary.counter.doubled',
        dependencies: () => <ReactiveValue<int>>[counter],
        compute: (read) => read.read(counter) * 2,
      ),
      history: BoundedLocalHistory<int>(initialValue: 0, maxEntries: 8),
    );
  }

  final ReactiveOwner owner;
  final ReactiveValue<int> counter;
  final ReactiveLazyComputed<int> doubled;
  final BoundedLocalHistory<int> history;
  var _disposed = false;

  void increment() {
    owner.update<void>((write) => write.set(counter, counter.value + 1));
    history.edit(counter.value);
  }

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    history.dispose();
    owner.dispose();
  }
}

final class CanaryApp extends StatelessWidget {
  const CanaryApp({required this.runtime, super.key});

  final CanaryRuntime runtime;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Dartitect paved-road canary')),
      body: Center(
        child: ListenableBuilder(
          listenable: runtime.doubled,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('value ${runtime.counter.value}'),
              Text('lazy ${runtime.doubled.value}'),
              FilledButton(
                onPressed: runtime.increment,
                child: const Text('Increment local state'),
              ),
            ],
          ),
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

final class _CanaryPersistence {
  const _CanaryPersistence();
}

final class _CanaryTransportProvider {
  const _CanaryTransportProvider();
}

final class _CanaryContractFixture {
  const _CanaryContractFixture();
}
