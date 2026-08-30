// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../../composition/application_module.wiring.dartitect.g.dart';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:large_consumer_canary/large_factories.dart';

/// Exact contexts selected by the LocalApplication2 feature profile.
final class LocalApplication2Infrastructure {
  const LocalApplication2Infrastructure({required this.appStorage});

  final AppStorage appStorage;
}

/// Concrete feature runtime with no public generic capability slots.
final class LocalApplication2Runtime {
  const LocalApplication2Runtime({
    required this.factory,
    required this.infrastructure,
    required this.repository,
    required this.localPort,
    required this.localAuthority,
  });

  final LocalApplication2Factory factory;
  final LocalApplication2Infrastructure infrastructure;
  final LargeRepository repository;
  final LargeLocalPort localPort;
  final PullReactiveSource<List<String>, LargeFailure> localAuthority;

  /// Creates consumer-owned presentation state from the typed runtime.
  LargeViewModel createViewModel() => factory.createViewModel(repository);

  /// Constructs the exact profile closure inside the host transaction.
  static Future<LocalApplication2Runtime> create(
    ApplicationGraph graph,
    LocalApplication2Factory factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = LocalApplication2Infrastructure(
      appStorage: graph.appStorage,
    );
    final localPort = factory.createLocalPort(infrastructure.appStorage);
    final localAuthority = PullReactiveSource<List<String>, LargeFailure>(
      triggers: <PullInvalidationTrigger>[() => factory.watch(localPort)],
      pull: (cancellation) => factory.read(localPort, cancellation),
    );
    final repository = transaction.own<LargeRepository>(
      factory.createRepository(localPort, localAuthority),
      (value) => value.disposeAsync(),
      label: 'feature.local_application_2.repository',
    );
    return LocalApplication2Runtime(
      factory: factory,
      infrastructure: infrastructure,
      repository: repository,
      localPort: localPort,
      localAuthority: localAuthority,
    );
  }
}

/// Material-neutral generated owner for the LocalApplication2 feature.
final class LocalApplication2FeatureHost extends StatelessWidget {
  const LocalApplication2FeatureHost({
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
  final LocalApplication2Factory factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<LocalApplication2Runtime, LargeViewModel> ready;
  final FeatureViewModelStarter<LargeViewModel>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<ApplicationGraph, LocalApplication2Runtime, LargeViewModel>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            LocalApplication2Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class LocalApplication2FeatureWiring {
  static const String profile = 'local';
  static const String scope = 'application';
  static const String storageContext = 'app_storage';
  static const List<String> targets = <String>['linux', 'web'];
  static const String pagination = 'none';
  static const String diagnostics = 'full';
  static const List<String> headlessTargets = <String>[];
  static const List<String> capabilities = <String>['attachments'];
  static const List<String> openApiOperations = <String>[];
}
