// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Capability-closed typed assembly for the Tasks feature graph.
final class TasksFeatureAssembly<
  Repository extends Object,
  Storage extends Object,
  Transport extends Object,
  LocalAuthority extends Object,
  Pagination extends Object,
  Outbox extends Object,
  SyncDataset extends Object,
  HeadlessJob extends Object,
  Diagnostics extends Object,
  Attachments extends Object,
  Credentials extends Object,
  Forms extends Object,
  Queries extends Object,
  ViewModel extends Object
>
    implements AsyncDisposable {
  TasksFeatureAssembly._(this._graph, this.createViewModel);

  /// Acquires exactly the owned or borrowed bindings selected by config v2.
  static Future<
    TasksFeatureAssembly<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Outbox,
      SyncDataset,
      HeadlessJob,
      Diagnostics,
      Attachments,
      Credentials,
      Forms,
      Queries,
      ViewModel
    >
  >
  create<
    Repository extends Object,
    Storage extends Object,
    Transport extends Object,
    LocalAuthority extends Object,
    Pagination extends Object,
    Outbox extends Object,
    SyncDataset extends Object,
    HeadlessJob extends Object,
    Diagnostics extends Object,
    Attachments extends Object,
    Credentials extends Object,
    Forms extends Object,
    Queries extends Object,
    ViewModel extends Object
  >({
    required DartitectAssemblyBinding<Repository> repository,
    required DartitectAssemblyBinding<Storage> storage,
    required DartitectAssemblyBinding<Transport> transport,
    required DartitectAssemblyBinding<LocalAuthority> localAuthority,
    required DartitectAssemblyBinding<Pagination> pagination,
    required DartitectAssemblyBinding<Outbox> outbox,
    required DartitectAssemblyBinding<SyncDataset> syncDataset,
    required DartitectAssemblyBinding<HeadlessJob> headlessJob,
    required DartitectAssemblyBinding<Diagnostics> diagnostics,
    required DartitectAssemblyBinding<Attachments> attachments,
    required DartitectAssemblyBinding<Credentials> credentials,
    required DartitectAssemblyBinding<Forms> forms,
    required DartitectAssemblyBinding<Queries> queries,
    required ViewModel Function(
      TasksFeatureAssembly<
        Repository,
        Storage,
        Transport,
        LocalAuthority,
        Pagination,
        Outbox,
        SyncDataset,
        HeadlessJob,
        Diagnostics,
        Attachments,
        Credentials,
        Forms,
        Queries,
        ViewModel
      >
      assembly,
    )
    createViewModel,
  }) async {
    final graph = await ResourceTransaction.create(
      (transaction) =>
          _TasksFeatureBindings<
            Repository,
            Storage,
            Transport,
            LocalAuthority,
            Pagination,
            Outbox,
            SyncDataset,
            HeadlessJob,
            Diagnostics,
            Attachments,
            Credentials,
            Forms,
            Queries
          >(
            repository: repository.bind(transaction),
            storage: storage.bind(transaction),
            transport: transport.bind(transaction),
            localAuthority: localAuthority.bind(transaction),
            pagination: pagination.bind(transaction),
            outbox: outbox.bind(transaction),
            syncDataset: syncDataset.bind(transaction),
            headlessJob: headlessJob.bind(transaction),
            diagnostics: diagnostics.bind(transaction),
            attachments: attachments.bind(transaction),
            credentials: credentials.bind(transaction),
            forms: forms.bind(transaction),
            queries: queries.bind(transaction),
          ),
      label: 'tasks-feature-assembly',
    );
    return TasksFeatureAssembly<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Outbox,
      SyncDataset,
      HeadlessJob,
      Diagnostics,
      Attachments,
      Credentials,
      Forms,
      Queries,
      ViewModel
    >._(graph, createViewModel);
  }

  final OwnedGraph<
    _TasksFeatureBindings<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Outbox,
      SyncDataset,
      HeadlessJob,
      Diagnostics,
      Attachments,
      Credentials,
      Forms,
      Queries
    >
  >
  _graph;

  Repository get repository => _graph.root.repository;
  Storage get storage => _graph.root.storage;
  Transport get transport => _graph.root.transport;
  LocalAuthority get localAuthority => _graph.root.localAuthority;
  Pagination get pagination => _graph.root.pagination;
  Outbox get outbox => _graph.root.outbox;
  SyncDataset get syncDataset => _graph.root.syncDataset;
  HeadlessJob get headlessJob => _graph.root.headlessJob;
  Diagnostics get diagnostics => _graph.root.diagnostics;
  Attachments get attachments => _graph.root.attachments;
  Credentials get credentials => _graph.root.credentials;
  Forms get forms => _graph.root.forms;
  Queries get queries => _graph.root.queries;

  /// Constructs presentation state from this exact typed assembly.
  final ViewModel Function(
    TasksFeatureAssembly<
      Repository,
      Storage,
      Transport,
      LocalAuthority,
      Pagination,
      Outbox,
      SyncDataset,
      HeadlessJob,
      Diagnostics,
      Attachments,
      Credentials,
      Forms,
      Queries,
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
      throw StateError('Tasks feature assembly is disposed.');
    }
    return createViewModel(this);
  }

  @override
  Future<void> disposeAsync() => _graph.disposeAsync();
}

final class _TasksFeatureBindings<
  Repository extends Object,
  Storage extends Object,
  Transport extends Object,
  LocalAuthority extends Object,
  Pagination extends Object,
  Outbox extends Object,
  SyncDataset extends Object,
  HeadlessJob extends Object,
  Diagnostics extends Object,
  Attachments extends Object,
  Credentials extends Object,
  Forms extends Object,
  Queries extends Object
>({
  required final Repository repository,
  required final Storage storage,
  required final Transport transport,
  required final LocalAuthority localAuthority,
  required final Pagination pagination,
  required final Outbox outbox,
  required final SyncDataset syncDataset,
  required final HeadlessJob headlessJob,
  required final Diagnostics diagnostics,
  required final Attachments attachments,
  required final Credentials credentials,
  required final Forms forms,
  required final Queries queries,
});

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

  /// Creates the public application-host factory while keeping graph ownership
  /// and atomic publication inside generated code.
  static BootstrapCoordinator<ViewModel> Function() application<
    Repository extends Object,
    Storage extends Object,
    Transport extends Object,
    LocalAuthority extends Object,
    Pagination extends Object,
    Outbox extends Object,
    SyncDataset extends Object,
    HeadlessJob extends Object,
    Diagnostics extends Object,
    Attachments extends Object,
    Credentials extends Object,
    Forms extends Object,
    Queries extends Object,
    ViewModel extends Object
  >({
    required FutureOr<
      TasksFeatureAssembly<
        Repository,
        Storage,
        Transport,
        LocalAuthority,
        Pagination,
        Outbox,
        SyncDataset,
        HeadlessJob,
        Diagnostics,
        Attachments,
        Credentials,
        Forms,
        Queries,
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
                TasksFeatureAssembly<
                  Repository,
                  Storage,
                  Transport,
                  LocalAuthority,
                  Pagination,
                  Outbox,
                  SyncDataset,
                  HeadlessJob,
                  Diagnostics,
                  Attachments,
                  Credentials,
                  Forms,
                  Queries,
                  ViewModel
                >
              >(
                await createAssembly(),
                (value) => value.disposeAsync(),
                label: 'tasks-feature-assembly',
              );
          context.throwIfUnavailable();
          return assembly.buildViewModel();
        },
      );
}
