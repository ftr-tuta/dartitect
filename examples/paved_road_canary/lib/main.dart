import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/material.dart';

import 'features/paved_road/composition/paved_road.wiring.dartitect.g.dart';

void main() => runDartitectApplication<CanaryRuntime>(
  create: createCanaryApplication(),
  loading: const MaterialApp(home: _Status('Bootstrapping')),
  application: (runtime) => CanaryApp(runtime: runtime),
);

typedef _CanaryFeatureAssembly =
    PavedRoadFeatureAssembly<
      CanaryRuntime,
      _CanaryPersistence,
      _CanaryTransportProvider,
      ReactiveLazyComputed<int>,
      BoundedLocalHistory<int>,
      _CanaryDiagnostics,
      CanaryRuntime
    >;

/// Creates the fully typed generated application factory.
BootstrapCoordinator<CanaryRuntime> Function() createCanaryApplication() =>
    PavedRoadFeatureWiring.application(
      createAssembly: _createCanaryFeatureAssembly,
    );

Future<_CanaryFeatureAssembly> _createCanaryFeatureAssembly() async {
  final runtime = CanaryRuntime.create();
  return PavedRoadFeatureAssembly.create<
    CanaryRuntime,
    _CanaryPersistence,
    _CanaryTransportProvider,
    ReactiveLazyComputed<int>,
    BoundedLocalHistory<int>,
    _CanaryDiagnostics,
    CanaryRuntime
  >(
    repository: DartitectAssemblyBinding<CanaryRuntime>.owned(
      runtime,
      release: (value) => value.disposeAsync(),
      label: 'canary.runtime',
    ),
    storage: DartitectAssemblyBinding<_CanaryPersistence>.borrowed(
      const _CanaryPersistence(),
    ),
    transport: DartitectAssemblyBinding<_CanaryTransportProvider>.borrowed(
      const _CanaryTransportProvider(),
    ),
    localAuthority:
        DartitectAssemblyBinding<ReactiveLazyComputed<int>>.borrowed(
          runtime.doubled,
        ),
    pagination: DartitectAssemblyBinding<BoundedLocalHistory<int>>.borrowed(
      runtime.history,
    ),
    diagnostics: DartitectAssemblyBinding<_CanaryDiagnostics>.borrowed(
      const _CanaryDiagnostics(),
    ),
    createViewModel: (assembly) => assembly.repository,
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

final class _CanaryDiagnostics {
  const _CanaryDiagnostics();
}
