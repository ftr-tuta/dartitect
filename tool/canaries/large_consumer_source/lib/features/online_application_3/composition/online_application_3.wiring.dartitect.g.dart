// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/application_module.wiring.dartitect.g.dart';

import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the OnlineApplication3 feature profile.
final class OnlineApplication3Infrastructure {
  const OnlineApplication3Infrastructure({required this.appApi});

  final AppTransport appApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class OnlineApplication3Runtime {
  const OnlineApplication3Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.remotePort,
    required this.mapper,
  });

  final OnlineApplication3Factory factory;
  final OnlineApplication3Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<OnlineApplication3Runtime> create(
    ApplicationGraph graph,
    OnlineApplication3Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = OnlineApplication3Infrastructure(
      appApi: graph.appApi,
    );
    final remotePort = factory.createRemotePort(infrastructure.appApi);
    final mapper = factory.createMapper();
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(remotePort, mapper),
      (value) => value.disposeAsync(),
      label: 'feature.online_application_3.repository',
    );
    return OnlineApplication3Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      remotePort: remotePort,
      mapper: mapper,
    );
  }
}

/// Material-neutral generated owner for the OnlineApplication3 feature.
final class OnlineApplication3FeatureHost extends StatelessWidget {
  const OnlineApplication3FeatureHost({
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
  final OnlineApplication3Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<OnlineApplication3Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, OnlineApplication3Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            OnlineApplication3Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class OnlineApplication3FeatureWiring {
  static const String profile = 'online';
  static const String scope = 'application';
  static const String transport = 'app_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['credentials'];
  static const List<String> openApiOperations = <String>[];
}
