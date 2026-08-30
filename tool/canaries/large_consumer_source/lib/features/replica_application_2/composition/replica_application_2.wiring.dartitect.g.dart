// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/application_module.wiring.dartitect.g.dart';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the ReplicaApplication2 feature profile.
final class ReplicaApplication2Infrastructure {
  const ReplicaApplication2Infrastructure({
    required this.appStorage,
    required this.appApi,
  });

  final AppStorage appStorage;
  final AppTransport appApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class ReplicaApplication2Runtime {
  const ReplicaApplication2Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.remotePort,
    required this.mapper,
    required this.dataset,
    required this.checkpointStore,
    required this.localAuthority,
    required this.syncEngine,
  });

  final ReplicaApplication2Factory factory;
  final ReplicaApplication2Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeLocalPort localPort;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;
  final SyncDataset<String, int, LargeFailure> dataset;
  final SyncCheckpointStore<String, int> checkpointStore;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;
  final SyncEngine<String, int, LargeFailure> syncEngine;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<ReplicaApplication2Runtime> create(
    ApplicationGraph graph,
    ReplicaApplication2Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = ReplicaApplication2Infrastructure(
      appStorage: graph.appStorage,
      appApi: graph.appApi,
    );
    final localPort = factory.createLocalPort(infrastructure.appStorage);
    final remotePort = factory.createRemotePort(infrastructure.appApi);
    final mapper = factory.createMapper();
    final dataset = factory.createDataset();
    final checkpointStore = factory.createCheckpointStore(
      infrastructure.appStorage,
    );
    final localAuthority = PullReactiveSource<List<String>, LargeFailure>(
      triggers: <PullInvalidationTrigger>[() => factory.watch(localPort)],
      pull: (cancellation) => factory.read(localPort, cancellation),
    );
    final syncEngine = transaction.own<SyncEngine<String, int, LargeFailure>>(
      SyncEngine<String, int, LargeFailure>(
        datasets: <SyncDataset<String, int, LargeFailure>>[dataset],
        graph: SyncDependencyGraph<String>(keys: <String>[dataset.key]),
        checkpoints: checkpointStore,
      ),
      (value) => value.disposeAsync(),
      label: 'feature.replica_application_2.sync',
    );
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(
        localPort,
        remotePort,
        mapper,
        localAuthority,
        syncEngine,
      ),
      (value) => value.disposeAsync(),
      label: 'feature.replica_application_2.repository',
    );
    return ReplicaApplication2Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      localPort: localPort,
      remotePort: remotePort,
      mapper: mapper,
      dataset: dataset,
      checkpointStore: checkpointStore,
      localAuthority: localAuthority,
      syncEngine: syncEngine,
    );
  }
}

/// Material-neutral generated owner for the ReplicaApplication2 feature.
final class ReplicaApplication2FeatureHost extends StatelessWidget {
  const ReplicaApplication2FeatureHost({
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
  final ReplicaApplication2Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<ReplicaApplication2Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, ReplicaApplication2Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            ReplicaApplication2Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class ReplicaApplication2FeatureWiring {
  static const String profile = 'replica';
  static const String scope = 'application';
  static const String storageContext = 'app_storage';
  static const String transport = 'app_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'full';
  static const String scheduler = 'workmanager';
  static const List<String> headlessTargets = <String>['linux', 'web'];
  static const List<String> capabilities = <String>['queries'];
  static const List<String> openApiOperations = <String>[];
}
