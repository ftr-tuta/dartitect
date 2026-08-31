// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect/dartitect.dart';

import 'application_module.wiring.dartitect.g.dart';

import 'package:large_consumer_canary/large_factories.dart';

/// Opaque replayable description; authentication payload remains app-owned.
final class DartitectSessionDescription {
  const DartitectSessionDescription(this.generation);
  final String generation;
}

/// Concrete authenticated-session graph.
final class SessionGraph {
  const SessionGraph({
    required this.application,
    required this.sessionStorage,
    required this.sessionApi,
    required this.session,
  });

  final ApplicationGraph application;
  AppStorage get appStorage => application.appStorage;
  final SessionStorage sessionStorage;
  AppTransport get appApi => application.appApi;
  final SessionTransport sessionApi;
  final LargeSession session;
}

/// Opens one fresh session graph per authenticated generation.
abstract final class SessionModule {
  static Future<SessionGraph> create(
    ApplicationGraph application,
    ResourceTransaction transaction,
  ) async {
    final sessionFactory = LargeSessionFactory();
    final sessionStorageFactory = SessionStorageFactory();
    final sessionStorage = transaction.own<SessionStorage>(
      await sessionStorageFactory.open(),
      sessionStorageFactory.dispose,
      label: 'session.session_storage',
    );
    final sessionApiFactory = SessionTransportFactory();
    final sessionApi = transaction.own<SessionTransport>(
      sessionApiFactory.open(),
      sessionApiFactory.dispose,
      label: 'session.session_api',
    );
    final session = sessionFactory.create();
    return SessionGraph(
      application: application,
      sessionStorage: sessionStorage,
      sessionApi: sessionApi,
      session: session,
    );
  }
}
