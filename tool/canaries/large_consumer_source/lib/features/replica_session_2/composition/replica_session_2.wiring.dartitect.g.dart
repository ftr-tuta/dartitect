// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/session_module.wiring.dartitect.g.dart';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the ReplicaSession2 feature profile.
final class ReplicaSession2Infrastructure {
  const ReplicaSession2Infrastructure({
    required this.sessionStorage,
    required this.sessionApi,
  });

  final SessionStorage sessionStorage;
  final SessionTransport sessionApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class ReplicaSession2Runtime {
  const ReplicaSession2Runtime({
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

  final ReplicaSession2Factory factory;
  final ReplicaSession2Infrastructure infrastructure;
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
  static Future<ReplicaSession2Runtime> create(
    SessionGraph graph,
    ReplicaSession2Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = ReplicaSession2Infrastructure(
      sessionStorage: graph.sessionStorage,
      sessionApi: graph.sessionApi,
    );
    final localPort = factory.createLocalPort(infrastructure.sessionStorage);
    final remotePort = factory.createRemotePort(infrastructure.sessionApi);
    final mapper = factory.createMapper();
    final dataset = factory.createDataset();
    final checkpointStore = factory.createCheckpointStore(
      infrastructure.sessionStorage,
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
      label: 'feature.replica_session_2.sync',
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
      label: 'feature.replica_session_2.repository',
    );
    return ReplicaSession2Runtime(
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

/// Material-neutral generated owner for the ReplicaSession2 feature.
final class ReplicaSession2FeatureHost extends StatelessWidget {
  const ReplicaSession2FeatureHost({
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
  final ReplicaSession2Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<ReplicaSession2Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<SessionGraph, ReplicaSession2Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            ReplicaSession2Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class ReplicaSession2FeatureWiring {
  static const String profile = 'replica';
  static const String scope = 'session';
  static const String storageContext = 'session_storage';
  static const String transport = 'session_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const String scheduler = 'workmanager';
  static const List<String> headlessTargets = <String>['linux', 'web'];
  static const List<String> capabilities = <String>['forms'];
  static const List<String> openApiOperations = <String>[];
}
