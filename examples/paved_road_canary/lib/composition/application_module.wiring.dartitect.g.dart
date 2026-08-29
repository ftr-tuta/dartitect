// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph<
  Session extends Object,
  SessionFailure extends Object
> {
  const ApplicationGraph({required this.sessions});

  final SessionRuntimeController<Session, SessionFailure> sessions;
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
          return ApplicationGraph<Session, SessionFailure>(sessions: sessions);
        },
      );
}
