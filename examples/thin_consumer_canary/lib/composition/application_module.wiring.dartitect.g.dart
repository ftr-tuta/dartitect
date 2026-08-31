// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect/dartitect.dart';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_workmanager/dartitect_workmanager.dart';
import 'package:thin_consumer_canary/composition/context_factories.dart';
import 'package:thin_consumer_canary/features/tasks/infrastructure/tasks_dio.wiring.dartitect.g.dart';

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph {
  const ApplicationGraph({
    required this.primary,
    required this.api,
    required this.scheduler,
    required this.observability,
  });

  final PrimaryStorage primary;
  final TasksDioModule api;
  final DartitectWorkmanagerScheduler scheduler;
  final ObservabilityRuntime observability;
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph> create() =>
      BootstrapCoordinator<ApplicationGraph>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) async {
          final primaryFactory = PrimaryStorageFactory();
          final primary = transaction.own<PrimaryStorage>(
            await primaryFactory.open(),
            primaryFactory.dispose,
            label: 'application.primary',
          );
          final apiFactory = ApiTransportFactory();
          final api = transaction.own<TasksDioModule>(
            apiFactory.open(),
            apiFactory.dispose,
            label: 'application.api',
          );
          final scheduler = DartitectWorkmanagerScheduler();
          final observability = transaction.own(
            ObservabilityRuntime(),
            (runtime) => runtime.disposeAsync(),
            label: 'application.observability',
          );
          return ApplicationGraph(
            primary: primary,
            api: api,
            scheduler: scheduler,
            observability: observability,
          );
        },
      );
}
