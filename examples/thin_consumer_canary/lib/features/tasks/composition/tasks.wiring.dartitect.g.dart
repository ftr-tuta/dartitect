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
import 'package:thin_consumer_canary/composition/context_factories.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_local_store.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_mutation.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_remote_port.dart';
import 'package:thin_consumer_canary/features/tasks/composition/tasks_factory.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_model.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';
import 'package:thin_consumer_canary/features/tasks/infrastructure/tasks_dio.wiring.dartitect.g.dart';
import 'package:thin_consumer_canary/features/tasks/infrastructure/tasks_mapper.dart';
import 'package:thin_consumer_canary/features/tasks/presentation/tasks_view_model.dart';

/// Exact contexts selected by the Tasks feature profile.
final class TasksInfrastructure {
  const TasksInfrastructure({required this.primary, required this.api});

  final PrimaryStorage primary;
  final TasksDioModule api;
}

/// Concrete feature runtime with no public generic capability slots.
final class TasksRuntime {
  const TasksRuntime({
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

  final TasksFactory factory;
  final TasksInfrastructure infrastructure;
  final OfflineTasksRepository repository;
  final TasksLocalStore localPort;
  final TasksRemotePort remotePort;
  final TasksMapper mapper;
  final MutationOutboxStore<String, TasksMutation, TasksFailure> outboxStore;
  final MutationIdempotencyPolicy<String, TasksMutation> idempotencyPolicy;
  final MutationConflictPolicy<Task> conflictPolicy;
  final SyncDataset<String, int, TasksFailure> dataset;
  final PrimaryCheckpointStore checkpointStore;
  final PullReactiveSource<List<Task>, TasksFailure> localAuthority;
  final SyncEngine<String, int, TasksFailure> syncEngine;
  final MutationCommand<TasksMutation, String, void, TasksFailure>
  mutationCommand;

  /// Creates consumer-owned presentation state from the typed runtime.
  TasksViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<TasksRuntime> create(
    ApplicationGraph graph,
    TasksFactory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = TasksInfrastructure(
      primary: graph.primary,
      api: graph.api,
    );
    final localPort = factory.createLocalPort(infrastructure.primary);
    final remotePort = factory.createRemotePort(infrastructure.api);
    final mapper = factory.createMapper();
    final outboxStore = factory.createOutboxStore(infrastructure.primary);
    final idempotencyPolicy = factory.createIdempotencyPolicy();
    final conflictPolicy = factory.createConflictPolicy();
    final dataset = factory.createDataset();
    final checkpointStore = factory.createCheckpointStore(
      infrastructure.primary,
    );
    final localAuthority = PullReactiveSource<List<Task>, TasksFailure>(
      triggers: <PullInvalidationTrigger>[() => factory.watch(localPort)],
      pull: (cancellation) => factory.read(localPort, cancellation),
    );
    final syncEngine = transaction.own<SyncEngine<String, int, TasksFailure>>(
      SyncEngine<String, int, TasksFailure>(
        datasets: <SyncDataset<String, int, TasksFailure>>[dataset],
        graph: SyncDependencyGraph<String>(keys: <String>[dataset.key]),
        checkpoints: checkpointStore,
      ),
      (value) => value.disposeAsync(),
      label: 'feature.tasks.sync',
    );
    final mutationCommand = transaction
        .own<MutationCommand<TasksMutation, String, void, TasksFailure>>(
          MutationCommand<TasksMutation, String, void, TasksFailure>(
            store: outboxStore,
            synchronize: (operation, cancellation) => factory
                .synchronizeMutation(remotePort, operation, cancellation),
            createIdempotencyKey: (key, argument) =>
                idempotencyPolicy.create(key, argument),
            classifyFailure: (failure) =>
                factory.classifyMutationFailure(failure),
          ),
          (value) => value.disposeAsync(),
          label: 'feature.tasks.mutations',
        );
    final repository = transaction.own<OfflineTasksRepository>(
      factory.createRepository(localPort, remotePort, mapper),
      (value) => value.disposeAsync(),
      label: 'feature.tasks.repository',
    );
    return TasksRuntime(
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

/// Material-neutral generated owner for the Tasks feature.
final class TasksFeatureHost extends StatelessWidget {
  const TasksFeatureHost({
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
  final TasksFactory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<TasksRuntime, TasksViewModel> ready;
  final FeatureViewModelStarter<TasksViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, TasksRuntime, TasksViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            TasksRuntime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class TasksFeatureWiring {
  static const String profile = 'offline-full';
  static const String scope = 'application';
  static const String storageContext = 'primary';
  static const String transport = 'api';
  static const List<String> targets = <String>[];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const String scheduler = 'workmanager';
  static const List<String> headlessTargets = <String>[
    'android',
    'ios',
    'macos',
    'linux',
    'web',
  ];
  static const List<String> capabilities = <String>[
    'attachments',
    'credentials',
    'forms',
    'queries',
  ];
  static const List<String> openApiOperations = <String>[];
}
