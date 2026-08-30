// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/application_module.wiring.dartitect.g.dart';
import '../../../contracts/app_api.contracts.dartitect.g.dart'
    as contract_app_api;

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the CacheApplication1 feature profile.
final class CacheApplication1Infrastructure {
  const CacheApplication1Infrastructure({
    required this.appStorage,
    required this.appApi,
  });

  final AppStorage appStorage;
  final AppTransport appApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class CacheApplication1Runtime {
  const CacheApplication1Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.appApiGetProbe,
    required this.localPort,
    required this.remotePort,
    required this.mapper,
    required this.localAuthority,
  });

  final CacheApplication1Factory factory;
  final CacheApplication1Infrastructure infrastructure;
  final LargeRepository repository;
  final contract_app_api.GetProbeOperation appApiGetProbe;
  final LargeLocalPort localPort;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<CacheApplication1Runtime> create(
    ApplicationGraph graph,
    CacheApplication1Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = CacheApplication1Infrastructure(
      appStorage: graph.appStorage,
      appApi: graph.appApi,
    );
    final appApiGetProbe = contract_app_api.GetProbeOperation(
      AppTransportFactory().client(infrastructure.appApi),
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
      label: 'feature.cache_application_1.repository',
    );
    return CacheApplication1Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      appApiGetProbe: appApiGetProbe,
      localPort: localPort,
      remotePort: remotePort,
      mapper: mapper,
      localAuthority: localAuthority,
    );
  }
}

/// Material-neutral generated owner for the CacheApplication1 feature.
final class CacheApplication1FeatureHost extends StatelessWidget {
  const CacheApplication1FeatureHost({
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
  final CacheApplication1Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<CacheApplication1Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, CacheApplication1Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            CacheApplication1Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class CacheApplication1FeatureWiring {
  static const String profile = 'cache';
  static const String scope = 'application';
  static const String storageContext = 'app_storage';
  static const String transport = 'app_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['credentials'];
  static const List<String> openApiOperations = <String>['app_api:getProbe'];
}
