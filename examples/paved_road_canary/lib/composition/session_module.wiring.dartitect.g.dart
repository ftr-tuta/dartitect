// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect/dartitect.dart';

import 'application_module.wiring.dartitect.g.dart';

import 'package:paved_road_canary/composition/canary_factories.dart';

/// Opaque replayable description; authentication payload remains app-owned.
final class DartitectSessionDescription {
  const DartitectSessionDescription(this.generation);
  final String generation;
}

/// Concrete authenticated-session graph.
final class SessionGraph {
  const SessionGraph({required this.application});

  final ApplicationGraph application;
  CanaryPersistence get localStore => application.localStore;
  CanaryTransport get synthetic => application.synthetic;
}

/// Opens one fresh session graph per authenticated generation.
abstract final class SessionModule {
  static Future<SessionGraph> create(
    ApplicationGraph application,
    ResourceTransaction transaction,
  ) async {
    return SessionGraph(application: application);
  }
}
