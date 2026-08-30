// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect/dartitect.dart';

import 'package:dartitect_reference_app/app/app_runtime.dart';
import 'package:dartitect_reference_app/composition/reference_factories.dart';

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph {
  const ApplicationGraph({
    required this.referenceRuntime,
    required this.referenceTransport,
  });

  final AppRuntime referenceRuntime;
  final ReferenceTransport referenceTransport;
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph> create() =>
      BootstrapCoordinator<ApplicationGraph>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) async {
          final referenceRuntimeFactory = ReferenceRuntimeFactory();
          final referenceRuntime = transaction.own<AppRuntime>(
            await referenceRuntimeFactory.open(),
            referenceRuntimeFactory.dispose,
            label: 'application.reference_runtime',
          );
          final referenceTransportFactory = ReferenceTransportFactory();
          final referenceTransport = transaction.own<ReferenceTransport>(
            referenceTransportFactory.open(),
            referenceTransportFactory.dispose,
            label: 'application.reference_transport',
          );
          return ApplicationGraph(
            referenceRuntime: referenceRuntime,
            referenceTransport: referenceTransport,
          );
        },
      );
}
