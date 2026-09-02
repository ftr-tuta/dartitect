// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/application_module.wiring.dartitect.g.dart';

import 'package:dartitect_reference_app/app/app_runtime.dart';
import 'package:dartitect_reference_app/composition/reference_factories.dart';
import 'package:dartitect_reference_app/features/tasks/application/offline_first_task_session.dart';
import 'package:dartitect_reference_app/features/tasks/composition/tasks_factory.dart';
import 'package:dartitect_reference_app/features/tasks/presentation/tasks_view_model.dart';

/// Exact contexts selected by the Tasks feature profile.
final class TasksInfrastructure {
  const TasksInfrastructure({
    required this.referenceRuntime,
    required this.referenceTransport,
  });

  final AppRuntime referenceRuntime;
  final ReferenceTransport referenceTransport;
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
    required this.localAuthority,
  });

  final TasksFactory factory;
  final TasksInfrastructure infrastructure;
  final LocalFirstTaskRepository repository;
  final ReferenceTasksLocalPort localPort;
  final ReferenceTasksRemotePort remotePort;
  final ReferenceTasksMapper mapper;
  final ReferenceTasksLocalAuthority localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  TasksViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<TasksRuntime> create(
    ApplicationGraph graph,
    TasksFactory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = TasksInfrastructure(
      referenceRuntime: graph.referenceRuntime,
      referenceTransport: graph.referenceTransport,
    );
    final localPort = factory.createLocalPort(infrastructure.referenceRuntime);
    final remotePort = factory.createRemotePort(
      infrastructure.referenceTransport,
    );
    final mapper = factory.createMapper();
    final localAuthority = factory.createLocalAuthority(localPort);
    final repository = transaction.own<LocalFirstTaskRepository>(
      factory.createRepository(localPort),
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
      localAuthority: localAuthority,
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
  static const String profile = 'cache';
  static const String scope = 'application';
  static const String storageContext = 'reference_runtime';
  static const String transport = 'reference_transport';
  static const List<String> targets = <String>[];
  static const String pagination = 'cursor';
  static const String diagnostics = 'full';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>[];
  static const List<String> openApiOperations = <String>[];
}
