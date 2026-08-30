// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_workmanager/dartitect_workmanager.dart';

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph<
  Session extends Object,
  SessionFailure extends Object
> {
  const ApplicationGraph({
    required this.sessions,
    required this.scheduler,
    required this.observability,
  });

  final SessionRuntimeController<Session, SessionFailure> sessions;
  final DartitectWorkmanagerScheduler scheduler;
  final ObservabilityRuntime observability;
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph<Session, SessionFailure>>
  create<Session extends Object, SessionFailure extends Object>() =>
      BootstrapCoordinator<ApplicationGraph<Session, SessionFailure>>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) async {
          final sessions = transaction.own(
            SessionRuntimeController<Session, SessionFailure>(),
            (controller) => controller.disposeAsync(),
            label: 'application.sessions',
          );
          final scheduler = DartitectWorkmanagerScheduler();
          final observability = transaction.own(
            ObservabilityRuntime(),
            (runtime) => runtime.disposeAsync(),
            label: 'application.observability',
          );
          return ApplicationGraph<Session, SessionFailure>(
            sessions: sessions,
            scheduler: scheduler,
            observability: observability,
          );
        },
      );
}
