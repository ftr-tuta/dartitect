// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';


/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph {
  const ApplicationGraph({
    required this.sessions,
    required this.scheduler,
    required this.observability,

  });

  final SessionRuntimeController<Object, Object> sessions;
  final String scheduler;
  final String observability;

}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph> create() =>
      BootstrapCoordinator<ApplicationGraph>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) async {
          final sessions = transaction.own(
            SessionRuntimeController<Object, Object>(),
            (controller) => controller.disposeAsync(),
          );

          return ApplicationGraph(
            sessions: sessions,
            scheduler: "workmanager",
            observability: "developer",

          );
        },
      );
}
