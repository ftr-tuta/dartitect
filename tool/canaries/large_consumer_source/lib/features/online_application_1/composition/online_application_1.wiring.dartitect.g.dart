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

import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the OnlineApplication1 feature profile.
final class OnlineApplication1Infrastructure {
  const OnlineApplication1Infrastructure({required this.appApi});

  final AppTransport appApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class OnlineApplication1Runtime {
  const OnlineApplication1Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.appApiGetProbe,
    required this.remotePort,
    required this.mapper,
  });

  final OnlineApplication1Factory factory;
  final OnlineApplication1Infrastructure infrastructure;
  final LargeRepository repository;
  final contract_app_api.GetProbeOperation appApiGetProbe;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<OnlineApplication1Runtime> create(
    ApplicationGraph graph,
    OnlineApplication1Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = OnlineApplication1Infrastructure(
      appApi: graph.appApi,
    );
    final appApiGetProbe = contract_app_api.GetProbeOperation(
      AppTransportFactory().client(infrastructure.appApi),
    );
    final remotePort = factory.createRemotePort(infrastructure.appApi);
    final mapper = factory.createMapper();
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(remotePort, mapper),
      (value) => value.disposeAsync(),
      label: 'feature.online_application_1.repository',
    );
    return OnlineApplication1Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      appApiGetProbe: appApiGetProbe,
      remotePort: remotePort,
      mapper: mapper,
    );
  }
}

/// Material-neutral generated owner for the OnlineApplication1 feature.
final class OnlineApplication1FeatureHost extends StatelessWidget {
  const OnlineApplication1FeatureHost({
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
  final OnlineApplication1Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<OnlineApplication1Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, OnlineApplication1Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            OnlineApplication1Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class OnlineApplication1FeatureWiring {
  static const String profile = 'online';
  static const String scope = 'application';
  static const String transport = 'app_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['forms'];
  static const List<String> openApiOperations = <String>['app_api:getProbe'];
}
