// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/application_module.wiring.dartitect.g.dart';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the LocalApplication1 feature profile.
final class LocalApplication1Infrastructure {
  const LocalApplication1Infrastructure({required this.appStorage});

  final AppStorage appStorage;
}

/// Concrete feature runtime with no public generic capability slots.
final class LocalApplication1Runtime {
  const LocalApplication1Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.localAuthority,
  });

  final LocalApplication1Factory factory;
  final LocalApplication1Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeLocalPort localPort;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<LocalApplication1Runtime> create(
    ApplicationGraph graph,
    LocalApplication1Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = LocalApplication1Infrastructure(
      appStorage: graph.appStorage,
    );
    final localPort = factory.createLocalPort(infrastructure.appStorage);
    final localAuthority = PullReactiveSource<List<String>, LargeFailure>(
      triggers: <PullInvalidationTrigger>[() => factory.watch(localPort)],
      pull: (cancellation) => factory.read(localPort, cancellation),
    );
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(localPort, localAuthority),
      (value) => value.disposeAsync(),
      label: 'feature.local_application_1.repository',
    );
    return LocalApplication1Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      localPort: localPort,
      localAuthority: localAuthority,
    );
  }
}

/// Material-neutral generated owner for the LocalApplication1 feature.
final class LocalApplication1FeatureHost extends StatelessWidget {
  const LocalApplication1FeatureHost({
    required this.graph,
    required this.factory,
    required this.loading,
    required this.failure,
    required this.ready,
    this.start,
    this.onDisposed,
    super.key,
  });

  final ApplicationGraph graph;
  final LocalApplication1Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<LocalApplication1Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, LocalApplication1Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            LocalApplication1Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class LocalApplication1FeatureWiring {
  static const String profile = 'local';
  static const String scope = 'application';
  static const String storageContext = 'app_storage';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'none';
  static const String diagnostics = 'basic';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['credentials'];
  static const List<String> openApiOperations = <String>[];
}
