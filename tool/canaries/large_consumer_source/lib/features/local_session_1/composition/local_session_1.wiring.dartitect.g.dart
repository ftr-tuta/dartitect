// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/session_module.wiring.dartitect.g.dart';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the LocalSession1 feature profile.
final class LocalSession1Infrastructure {
  const LocalSession1Infrastructure({required this.sessionStorage});

  final SessionStorage sessionStorage;
}

/// Concrete feature runtime with no public generic capability slots.
final class LocalSession1Runtime {
  const LocalSession1Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.localAuthority,
  });

  final LocalSession1Factory factory;
  final LocalSession1Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeLocalPort localPort;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<LocalSession1Runtime> create(
    SessionGraph graph,
    LocalSession1Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = LocalSession1Infrastructure(
      sessionStorage: graph.sessionStorage,
    );
    final localPort = factory.createLocalPort(infrastructure.sessionStorage);
    final localAuthority = PullReactiveSource<List<String>, LargeFailure>(
      triggers: <PullInvalidationTrigger>[() => factory.watch(localPort)],
      pull: (cancellation) => factory.read(localPort, cancellation),
    );
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(localPort, localAuthority),
      (value) => value.disposeAsync(),
      label: 'feature.local_session_1.repository',
    );
    return LocalSession1Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      localPort: localPort,
      localAuthority: localAuthority,
    );
  }
}

/// Material-neutral generated owner for the LocalSession1 feature.
final class LocalSession1FeatureHost extends StatelessWidget {
  const LocalSession1FeatureHost({
    required this.graph,
    required this.factory,
    required this.loading,
    required this.failure,
    required this.ready,
    this.start,
    this.onDisposed,
    super.key,
  });

  final SessionGraph graph;
  final LocalSession1Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<LocalSession1Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<SessionGraph, LocalSession1Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            LocalSession1Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class LocalSession1FeatureWiring {
  static const String profile = 'local';
  static const String scope = 'session';
  static const String storageContext = 'session_storage';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'none';
  static const String diagnostics = 'full';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['queries'];
  static const List<String> openApiOperations = <String>[];
}
