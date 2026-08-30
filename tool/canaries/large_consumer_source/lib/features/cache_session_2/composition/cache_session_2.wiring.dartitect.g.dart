// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/session_module.wiring.dartitect.g.dart';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the CacheSession2 feature profile.
final class CacheSession2Infrastructure {
  const CacheSession2Infrastructure({
    required this.sessionStorage,
    required this.sessionApi,
  });

  final SessionStorage sessionStorage;
  final SessionTransport sessionApi;
}

/// Concrete feature runtime with no public generic capability slots.
final class CacheSession2Runtime {
  const CacheSession2Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.remotePort,
    required this.mapper,
    required this.localAuthority,
  });

  final CacheSession2Factory factory;
  final CacheSession2Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeLocalPort localPort;
  final LargeRemotePort remotePort;
  final LargeMapper mapper;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<CacheSession2Runtime> create(
    SessionGraph graph,
    CacheSession2Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = CacheSession2Infrastructure(
      sessionStorage: graph.sessionStorage,
      sessionApi: graph.sessionApi,
    );
    final localPort = factory.createLocalPort(infrastructure.sessionStorage);
    final remotePort = factory.createRemotePort(infrastructure.sessionApi);
    final mapper = factory.createMapper();
    final localAuthority = PullReactiveSource<List<String>, LargeFailure>(
      triggers: <PullInvalidationTrigger>[() => factory.watch(localPort)],
      pull: (cancellation) => factory.read(localPort, cancellation),
    );
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(localPort, remotePort, mapper, localAuthority),
      (value) => value.disposeAsync(),
      label: 'feature.cache_session_2.repository',
    );
    return CacheSession2Runtime(
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

/// Material-neutral generated owner for the CacheSession2 feature.
final class CacheSession2FeatureHost extends StatelessWidget {
  const CacheSession2FeatureHost({
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
  final CacheSession2Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<CacheSession2Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<SessionGraph, CacheSession2Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            CacheSession2Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class CacheSession2FeatureWiring {
  static const String profile = 'cache';
  static const String scope = 'session';
  static const String storageContext = 'session_storage';
  static const String transport = 'session_api';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'cursor';
  static const String diagnostics = 'basic';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['credentials'];
  static const List<String> openApiOperations = <String>[];
}
