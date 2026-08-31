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

/// Exact contexts selected by the OfflineFullApplication3 feature profile.
final class OfflineFullApplication3Infrastructure {
  const OfflineFullApplication3Infrastructure({
    required this.appStorage,
    required this.appApi,
  });

  final AppStorage appStorage;
  final AppTransport appApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class OfflineFullApplication3Runtime {
  const OfflineFullApplication3Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.remotePort,
    required this.mapper,
    required this.outboxStore,
    required this.idempotencyPolicy,
    required this.conflictPolicy,
    required this.dataset,
    required this.checkpointStore,
    required this.localAuthority,
    required this.syncEngine,
    required this.mutationCommand,
  });

  final OfflineFullApplication3Factory factory;
  final OfflineFullApplication3Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeLocalPort localPort;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;
  final MutationOutboxStore<String, LargeMutation, LargeFailure> outboxStore;
  final MutationIdempotencyPolicy<String, LargeMutation> idempotencyPolicy;
  final MutationConflictPolicy<String> conflictPolicy;
  final SyncDataset<String, int, LargeFailure> dataset;
  final SyncCheckpointStore<String, int> checkpointStore;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;
  final SyncEngine<String, int, LargeFailure> syncEngine;
  final MutationCommand<LargeMutation, String, void, LargeFailure>
  mutationCommand;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<OfflineFullApplication3Runtime> create(
    ApplicationGraph graph,
    OfflineFullApplication3Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = OfflineFullApplication3Infrastructure(
      appStorage: graph.appStorage,
      appApi: graph.appApi,
    );
    final localPort = factory.createLocalPort(infrastructure.appStorage);
    final remotePort = factory.createRemotePort(infrastructure.appApi);
    final mapper = factory.createMapper();
    final outboxStore = factory.createOutboxStore(infrastructure.appStorage);
    final idempotencyPolicy = factory.createIdempotencyPolicy();
    final conflictPolicy = factory.createConflictPolicy();
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
      label: 'feature.offline_full_application_3.sync',
    );
    final mutationCommand = transaction
        .own<MutationCommand<LargeMutation, String, void, LargeFailure>>(
          MutationCommand<LargeMutation, String, void, LargeFailure>(
            store: outboxStore,
            synchronize: (operation, cancellation) => factory
                .synchronizeMutation(remotePort, operation, cancellation),
            createIdempotencyKey: (key, argument) =>
                idempotencyPolicy.create(key, argument),
            classifyFailure: (failure) =>
                factory.classifyMutationFailure(failure),
          ),
          (value) => value.disposeAsync(),
          label: 'feature.offline_full_application_3.mutations',
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
      label: 'feature.offline_full_application_3.repository',
    );
    return OfflineFullApplication3Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      localPort: localPort,
      remotePort: remotePort,
      mapper: mapper,
      outboxStore: outboxStore,
      idempotencyPolicy: idempotencyPolicy,
      conflictPolicy: conflictPolicy,
      dataset: dataset,
      checkpointStore: checkpointStore,
      localAuthority: localAuthority,
      syncEngine: syncEngine,
      mutationCommand: mutationCommand,
    );
  }
}

/// Material-neutral generated owner for the OfflineFullApplication3 feature.
final class OfflineFullApplication3FeatureHost extends StatelessWidget {
  const OfflineFullApplication3FeatureHost({
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
  final OfflineFullApplication3Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<OfflineFullApplication3Runtime, LargeViewModel>
  ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<
        ApplicationGraph,
        OfflineFullApplication3Runtime,
        LargeViewModel
      >(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            OfflineFullApplication3Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class OfflineFullApplication3FeatureWiring {
  static const String profile = 'offline-full';
  static const String scope = 'application';
  static const String storageContext = 'app_storage';
  static const String transport = 'app_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const String scheduler = 'workmanager';
  static const List<String> headlessTargets = <String>['linux', 'web'];
  static const List<String> capabilities = <String>['forms'];
  static const List<String> openApiOperations = <String>[];
}
