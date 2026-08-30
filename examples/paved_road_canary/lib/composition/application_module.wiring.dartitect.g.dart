// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect/dartitect.dart';

import 'package:paved_road_canary/composition/canary_factories.dart';

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph {
  const ApplicationGraph({required this.localStore, required this.synthetic});

  final CanaryPersistence localStore;
  final CanaryTransport synthetic;
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph> create() =>
      BootstrapCoordinator<ApplicationGraph>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) async {
          final localStoreFactory = LocalStoreFactory();
          final localStore = transaction.own<CanaryPersistence>(
            localStoreFactory.open(),
            localStoreFactory.dispose,
            label: 'application.local_store',
          );
          final syntheticFactory = SyntheticTransportFactory();
          final synthetic = transaction.own<CanaryTransport>(
            syntheticFactory.open(),
            syntheticFactory.dispose,
            label: 'application.synthetic',
          );
          return ApplicationGraph(localStore: localStore, synthetic: synthetic);
        },
      );
}
