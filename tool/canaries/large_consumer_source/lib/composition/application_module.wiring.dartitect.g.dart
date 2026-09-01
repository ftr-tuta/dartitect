// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';

import 'session_module.wiring.dartitect.g.dart';

import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_workmanager/dartitect_workmanager.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph {
  const ApplicationGraph({
    required this.appStorage,
    required this.appApi,
    required this.sessions,
    required this.scheduler,
    required this.observability,
  });

  final AppStorage appStorage;
  final AppTransport appApi;
  final SessionRuntimeController<SessionGraph, DartitectSessionDescription>
  sessions;
  final DartitectWorkmanagerScheduler scheduler;
  final DestinationAwareObservabilityRuntime observability;
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph>
  create() => BootstrapCoordinator<ApplicationGraph>(
    stages: const <BootstrapStage>[],
    buildRoot: (transaction, _) async {
      final appStorageFactory = AppStorageFactory();
      final appStorage = transaction.own<AppStorage>(
        await appStorageFactory.open(),
        appStorageFactory.dispose,
        label: 'application.app_storage',
      );
      final appApiFactory = AppTransportFactory();
      final appApi = transaction.own<AppTransport>(
        appApiFactory.open(),
        appApiFactory.dispose,
        label: 'application.app_api',
      );
      final sessions = transaction.own(
        SessionRuntimeController<SessionGraph, DartitectSessionDescription>(),
        (controller) => controller.disposeAsync(),
        label: 'application.sessions',
      );
      final scheduler = DartitectWorkmanagerScheduler();
      final observability = transaction.own(
        ObservabilityRuntime.withPrivacy(
          privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
            profile: ObservabilityPrivacyProfile.balanced,
          ),
          destinations: <ObservabilityDestinationRegistration>[
            ObservabilityDestinationRegistration.local(
              logSinks: <PreparedLogSinkRegistration>[
                const PreparedLogSinkRegistration.owned(
                  PreparedDeveloperLogSink(),
                ),
              ],
            ),
          ],
        ),
        (runtime) => runtime.disposeAsync(),
        label: 'application.observability',
      );
      return ApplicationGraph(
        appStorage: appStorage,
        appApi: appApi,
        sessions: sessions,
        scheduler: scheduler,
        observability: observability,
      );
    },
  );
}
