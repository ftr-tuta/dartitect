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

/// Exact contexts selected by the CacheApplication3 feature profile.
final class CacheApplication3Infrastructure {
  const CacheApplication3Infrastructure({
    required this.appStorage,
    required this.appApi,
  });

  final AppStorage appStorage;
  final AppTransport appApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class CacheApplication3Runtime {
  const CacheApplication3Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.remotePort,
    required this.mapper,
    required this.localAuthority,
  });

  final CacheApplication3Factory factory;
  final CacheApplication3Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeLocalPort localPort;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<CacheApplication3Runtime> create(
    ApplicationGraph graph,
    CacheApplication3Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = CacheApplication3Infrastructure(
      appStorage: graph.appStorage,
      appApi: graph.appApi,
    );
    final localPort = factory.createLocalPort(infrastructure.appStorage);
    final remotePort = factory.createRemotePort(infrastructure.appApi);
    final mapper = factory.createMapper();
    final localAuthority = PullReactiveSource<List<String>, LargeFailure>(
      triggers: <PullInvalidationTrigger>[() => factory.watch(localPort)],
      pull: (cancellation) => factory.read(localPort, cancellation),
    );
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(localPort, remotePort, mapper, localAuthority),
      (value) => value.disposeAsync(),
      label: 'feature.cache_application_3.repository',
    );
    return CacheApplication3Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      localPort: localPort,
      remotePort: remotePort,
      mapper: mapper,
      localAuthority: localAuthority,
    );
  }
}

/// Material-neutral generated owner for the CacheApplication3 feature.
final class CacheApplication3FeatureHost extends StatelessWidget {
  const CacheApplication3FeatureHost({
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
  final CacheApplication3Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<CacheApplication3Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, CacheApplication3Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            CacheApplication3Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class CacheApplication3FeatureWiring {
  static const String profile = 'cache';
  static const String scope = 'application';
  static const String storageContext = 'app_storage';
  static const String transport = 'app_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['forms'];
  static const List<String> openApiOperations = <String>[];
}
