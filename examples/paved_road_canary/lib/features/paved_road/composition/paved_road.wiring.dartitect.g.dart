// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Capability-closed typed assembly for the PavedRoad feature graph.
final class PavedRoadFeatureAssembly<
  Repository extends Object,
  Storage extends Object,
  Transport extends Object,
  LocalAuthority extends Object,
  Pagination extends Object,
  Diagnostics extends Object,
  ViewModel extends Object
>
    implements AsyncDisposable {
  PavedRoadFeatureAssembly._(this._graph, this.createViewModel);

  /// Acquires exactly the owned or borrowed bindings selected by config v2.
  static Future<
    PavedRoadFeatureAssembly<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Diagnostics,
      ViewModel
    >
  >
  create<
    Repository extends Object,
    Storage extends Object,
    Transport extends Object,
    LocalAuthority extends Object,
    Pagination extends Object,
    Diagnostics extends Object,
    ViewModel extends Object
  >({
    required DartitectAssemblyBinding<Repository> repository,
    required DartitectAssemblyBinding<Storage> storage,
    required DartitectAssemblyBinding<Transport> transport,
    required DartitectAssemblyBinding<LocalAuthority> localAuthority,
    required DartitectAssemblyBinding<Pagination> pagination,
    required DartitectAssemblyBinding<Diagnostics> diagnostics,
    required ViewModel Function(
      PavedRoadFeatureAssembly<
        Repository,
        Storage,
        Transport,
        LocalAuthority,
        Pagination,
        Diagnostics,
        ViewModel
      >
      assembly,
    )
    createViewModel,
  }) async {
    final graph = await ResourceTransaction.create(
      (transaction) =>
          _PavedRoadFeatureBindings<
            Repository,
            Storage,
            Transport,
            LocalAuthority,
            Pagination,
            Diagnostics
          >(
            repository: repository.bind(transaction),
            storage: storage.bind(transaction),
            transport: transport.bind(transaction),
            localAuthority: localAuthority.bind(transaction),
            pagination: pagination.bind(transaction),
            diagnostics: diagnostics.bind(transaction),
          ),
      label: 'paved_road-feature-assembly',
    );
    return PavedRoadFeatureAssembly<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Diagnostics,
      ViewModel
    >._(graph, createViewModel);
  }

  final OwnedGraph<
    _PavedRoadFeatureBindings<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Diagnostics
    >
  >
  _graph;

  Repository get repository => _graph.root.repository;
  Storage get storage => _graph.root.storage;
  Transport get transport => _graph.root.transport;
  LocalAuthority get localAuthority => _graph.root.localAuthority;
  Pagination get pagination => _graph.root.pagination;
  Diagnostics get diagnostics => _graph.root.diagnostics;

  /// Constructs presentation state from this exact typed assembly.
  final ViewModel Function(
    PavedRoadFeatureAssembly<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Diagnostics,
      ViewModel
    >
    assembly,
  )
  createViewModel;

  /// Whether every owned binding has completed teardown.
  bool get isDisposed => _graph.isDisposed;

  /// Creates the ViewModel while the assembly remains live.
  ViewModel buildViewModel() {
    if (!_graph.isAccepting) {
      throw StateError('PavedRoad feature assembly is disposed.');
    }
    return createViewModel(this);
  }

  @override
  Future<void> disposeAsync() => _graph.disposeAsync();
}

final class _PavedRoadFeatureBindings<
  Repository extends Object,
  Storage extends Object,
  Transport extends Object,
  LocalAuthority extends Object,
  Pagination extends Object,
  Diagnostics extends Object
>({
  required final Repository repository,
  required final Storage storage,
  required final Transport transport,
  required final LocalAuthority localAuthority,
  required final Pagination pagination,
  required final Diagnostics diagnostics,
});

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

  /// Creates the public application-host factory while keeping graph ownership
  /// and atomic publication inside generated code.
  static BootstrapCoordinator<ViewModel> Function() application<
    Repository extends Object,
    Storage extends Object,
    Transport extends Object,
    LocalAuthority extends Object,
    Pagination extends Object,
    Diagnostics extends Object,
    ViewModel extends Object
  >({
    required FutureOr<
      PavedRoadFeatureAssembly<
        Repository,
        Storage,
        Transport,
        LocalAuthority,
        Pagination,
        Diagnostics,
        ViewModel
      >
    >
    Function()
    createAssembly,
  }) =>
      () => BootstrapCoordinator<ViewModel>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, context) async {
          context.throwIfUnavailable();
          final assembly = transaction
              .own<
                PavedRoadFeatureAssembly<
                  Repository,
                  Storage,
                  Transport,
                  LocalAuthority,
                  Pagination,
                  Diagnostics,
                  ViewModel
                >
              >(
                await createAssembly(),
                (value) => value.disposeAsync(),
                label: 'paved_road-feature-assembly',
              );
          context.throwIfUnavailable();
          return assembly.buildViewModel();
        },
      );
}
