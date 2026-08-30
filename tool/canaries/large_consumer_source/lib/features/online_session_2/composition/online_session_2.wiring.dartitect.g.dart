// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/session_module.wiring.dartitect.g.dart';

import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the OnlineSession2 feature profile.
final class OnlineSession2Infrastructure {
  const OnlineSession2Infrastructure({required this.sessionApi});

  final SessionTransport sessionApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class OnlineSession2Runtime {
  const OnlineSession2Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.remotePort,
    required this.mapper,
  });

  final OnlineSession2Factory factory;
  final OnlineSession2Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<OnlineSession2Runtime> create(
    SessionGraph graph,
    OnlineSession2Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = OnlineSession2Infrastructure(
      sessionApi: graph.sessionApi,
    );
    final remotePort = factory.createRemotePort(infrastructure.sessionApi);
    final mapper = factory.createMapper();
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(remotePort, mapper),
      (value) => value.disposeAsync(),
      label: 'feature.online_session_2.repository',
    );
    return OnlineSession2Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      remotePort: remotePort,
      mapper: mapper,
    );
  }
}

/// Material-neutral generated owner for the OnlineSession2 feature.
final class OnlineSession2FeatureHost extends StatelessWidget {
  const OnlineSession2FeatureHost({
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
  final OnlineSession2Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<OnlineSession2Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<SessionGraph, OnlineSession2Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            OnlineSession2Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class OnlineSession2FeatureWiring {
  static const String profile = 'online';
  static const String scope = 'session';
  static const String transport = 'session_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['forms'];
  static const List<String> openApiOperations = <String>[];
}
