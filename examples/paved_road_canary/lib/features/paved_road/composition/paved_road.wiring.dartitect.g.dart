// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/application_module.wiring.dartitect.g.dart';

import 'package:paved_road_canary/composition/canary_factories.dart';

/// Exact contexts selected by the PavedRoad feature profile.
final class PavedRoadInfrastructure {
  const PavedRoadInfrastructure({
    required this.localStore,
    required this.synthetic,
  });

  final CanaryPersistence localStore;
  final CanaryTransport synthetic;
}

/// Concrete feature runtime with no public generic capability slots.
final class PavedRoadRuntime {
  const PavedRoadRuntime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.remotePort,
    required this.mapper,
    required this.localAuthority,
  });

  final PavedRoadFactory factory;
  final PavedRoadInfrastructure infrastructure;
  final CanaryRepository repository;
  final CanaryLocalPort localPort;
  final CanaryRemotePort remotePort;
  final CanaryMapper mapper;
  final CanaryLocalAuthority localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  CanaryViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<PavedRoadRuntime> create(
    ApplicationGraph graph,
    PavedRoadFactory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = PavedRoadInfrastructure(
      localStore: graph.localStore,
      synthetic: graph.synthetic,
    );
    final localPort = factory.createLocalPort();
    final remotePort = factory.createRemotePort();
    final mapper = factory.createMapper();
    final localAuthority = factory.createLocalAuthority();
    final repository = transaction.own<CanaryRepository>(
      factory.createRepository(localAuthority),
      (value) => value.disposeAsync(),
      label: 'feature.paved_road.repository',
    );
    return PavedRoadRuntime(
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

/// Material-neutral generated owner for the PavedRoad feature.
final class PavedRoadFeatureHost extends StatelessWidget {
  const PavedRoadFeatureHost({
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
  final PavedRoadFactory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<PavedRoadRuntime, CanaryViewModel> ready;
  final FeatureViewModelStarter<CanaryViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, PavedRoadRuntime, CanaryViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            PavedRoadRuntime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class PavedRoadFeatureWiring {
  static const String profile = 'cache';
  static const String scope = 'application';
  static const String storageContext = 'local_store';
  static const String transport = 'synthetic';
  static const List<String> targets = <String>[];
  static const String pagination = 'cursor';
  static const String diagnostics = 'full';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>[];
  static const List<String> openApiOperations = <String>[];
}
