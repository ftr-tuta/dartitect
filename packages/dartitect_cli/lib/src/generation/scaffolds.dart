import 'package:dartitect/dartitect.dart' show FeatureProfile;

import '../config/dartitect_config.dart';
import 'generation_engine.dart';

/// Validated options for paved-road feature generation.
final class FeatureScaffoldOptions {
  /// Creates profile/provider options and validates their compatibility.
  FeatureScaffoldOptions({
    required this.profile,
    required this.scope,
    this.storageContext,
    this.transport,
    Set<DartitectPlatform> targets = const <DartitectPlatform>{},
    this.pagination = FeaturePagination.none,
    Set<DartitectPlatform> headlessTargets = const <DartitectPlatform>{},
    this.diagnostics = FeatureDiagnosticsLevel.basic,
    Set<DartitectCapability> capabilities = const <DartitectCapability>{},
  }) : targets = Set<DartitectPlatform>.unmodifiable(targets),
       headlessTargets = Set<DartitectPlatform>.unmodifiable(headlessTargets),
       capabilities = Set<DartitectCapability>.unmodifiable(capabilities) {
    DartitectFeatureDeclaration(
      profile: profile,
      scope: scope,
      storageContext: storageContext,
      transport: transport,
      targets: targets,
      pagination: pagination,
      diagnostics: diagnostics,
      headlessTargets: headlessTargets,
      capabilities: capabilities,
    );
  }

  /// Public behavior profile.
  final FeatureProfile profile;

  /// Application or session graph lifetime.
  final FeatureScope scope;

  /// Consumer-selected named storage context.
  final String? storageContext;

  /// Consumer-selected named transport.
  final String? transport;

  /// Feature target restriction; empty inherits application targets.
  final Set<DartitectPlatform> targets;

  /// Generated pagination policy.
  final FeaturePagination pagination;

  /// Platforms that opt in to headless execution.
  final Set<DartitectPlatform> headlessTargets;

  /// Generated payload-free diagnostics level.
  final FeatureDiagnosticsLevel diagnostics;

  /// Stable opt-in workflows.
  final Set<DartitectCapability> capabilities;
}

/// Validated Dart identifier naming pair.
final class ScaffoldName {
  /// Validates an ASCII snake_case scaffold name.
  factory ScaffoldName(String input) {
    if (!RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(input)) {
      throw FormatException(
        'Name "$input" must be an ASCII snake_case identifier.',
      );
    }
    final pascal = input
        .split('_')
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join();
    return ScaffoldName._(input, pascal);
  }

  const ScaffoldName._(this.snake, this.pascal);

  /// File/directory form.
  final String snake;

  /// Dart symbol form.
  final String pascal;
}

/// Renders bounded, generated-once Native MVVM scaffolds.
final class ScaffoldFactory {
  /// Creates a scaffold renderer for one package.
  const ScaffoldFactory({required this.packageName});

  /// Consumer package used in generated test imports.
  final String packageName;

  /// Renders one public paved-road profile plus generated-once wiring.
  List<FileGenerationOperation> profile(
    FeatureScaffoldOptions options,
    String input,
  ) {
    final name = ScaffoldName(input);
    final base = <FileGenerationOperation>[
      ...feature(input, includeDomain: true),
      FileGenerationOperation(
        relativePath:
            'lib/features/${name.snake}/domain/${name.snake}_model.dart',
        content: _immutableModel(name),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_architecture_test.dart',
        content: _architectureTest(name),
      ),
    ];
    final operations = switch (options.profile) {
      FeatureProfile.local => <FileGenerationOperation>[...base],
      FeatureProfile.online => <FileGenerationOperation>[
        ...base,
        ..._remoteReadBlueprint(name),
      ],
      FeatureProfile.cache => <FileGenerationOperation>[
        ...base,
        ..._remoteReadBlueprint(name),
        ..._localFirstBlueprint(name),
      ],
      FeatureProfile.replica => <FileGenerationOperation>[
        ...base,
        ..._remoteReadBlueprint(name),
        ..._localFirstBlueprint(name),
        ..._syncDatasetBlueprint(name),
      ],
      FeatureProfile.offlineFull => <FileGenerationOperation>[
        ...base,
        ..._remoteReadBlueprint(name),
        ..._localFirstBlueprint(name),
        ..._offlineMutationBlueprint(name),
        ..._syncDatasetBlueprint(name),
      ],
    };
    return <FileGenerationOperation>[
      ...operations,
      if (options.pagination == FeaturePagination.cursor)
        FileGenerationOperation(
          relativePath:
              'lib/features/${name.snake}/application/${name.snake}_cursor_page.dart',
          content: _cursorPage(name),
        ),
      if (options.headlessTargets.isNotEmpty)
        FileGenerationOperation(
          relativePath:
              'lib/features/${name.snake}/composition/${name.snake}_headless_sync.dart',
          content: _headlessSync(name),
        ),
    ];
  }

  /// Default Dartitect configuration file.
  List<FileGenerationOperation> init({
    DartitectConfig? config,
  }) => <FileGenerationOperation>[
    FileGenerationOperation(
      relativePath: 'dartitect.json',
      content: (config ?? DartitectConfig(features: DartitectFeaturesConfig()))
          .encode(),
    ),
  ];

  /// Local, concise instructions for coding agents.
  List<FileGenerationOperation> agents() => <FileGenerationOperation>[
    const FileGenerationOperation(
      relativePath: 'AGENTS.md',
      content: '''# Dartitect architecture contract

- Validate with `flutter analyze`, `flutter test`, and `dart run dartitect_cli:dartitect inspect --json`.
- Use constructor injection and explicit composition roots.
- Domain must not import Flutter, data implementations, or adapters.
- Presentation and ViewModels must not import Dio or ObjectBox.
- Do not use service locators, architecture/state frameworks, or private `src/` imports.
- `ViewModelHost.create` owns its value; `ViewModelHost.value` borrows it.
- Keep routing and UI effects in Widgets.
- Before adding infrastructure, ask: É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?
- It belongs in Dartitect only when all three answers are yes; otherwise use a typed project-local extension or keep business behavior in the application.
''',
    ),
  ];

  /// A complete small feature with optional pure-Dart domain contract.
  List<FileGenerationOperation> feature(
    String input, {
    required bool includeDomain,
  }) {
    final name = ScaffoldName(input);
    final root = 'lib/features/${name.snake}';
    final contractLayer = includeDomain ? 'domain' : 'application';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/$contractLayer/${name.snake}_repository.dart',
        content: _repositoryContract(name),
      ),
      FileGenerationOperation(
        relativePath:
            '$root/infrastructure/memory_${name.snake}_repository.dart',
        content: _memoryRepository(name, contractLayer: contractLayer),
      ),
      FileGenerationOperation(
        relativePath: '$root/composition/${name.snake}_composition.dart',
        content: _composition(name),
      ),
      FileGenerationOperation(
        relativePath: '$root/presentation/${name.snake}_view_model.dart',
        content: _featureViewModel(name, contractLayer: contractLayer),
      ),
      FileGenerationOperation(
        relativePath: '$root/presentation/${name.snake}_view.dart',
        content: _view(name, contractLayer: contractLayer),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_view_model_test.dart',
        content: _featureViewModelTest(name, contractLayer: contractLayer),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_repository_contract_test.dart',
        content: _repositoryContractTest(name),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_view_test.dart',
        content: _viewTest(name),
      ),
    ];
  }

  /// A standalone native ViewModel and test.
  List<FileGenerationOperation> viewModel(String input) {
    final name = ScaffoldName(input);
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath:
            'lib/features/${name.snake}/presentation/${name.snake}_view_model.dart',
        content: _standaloneViewModel(name),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_view_model_test.dart',
        content: _standaloneViewModelTest(name),
      ),
    ];
  }

  /// A pure-Dart repository contract and memory implementation.
  List<FileGenerationOperation> repository(String input) {
    final name = ScaffoldName(input);
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/domain/${name.snake}_repository.dart',
        content: _repositoryContract(name),
      ),
      FileGenerationOperation(
        relativePath:
            '$root/infrastructure/memory_${name.snake}_repository.dart',
        content: _memoryRepository(name, contractLayer: 'domain'),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_repository_contract_test.dart',
        content: _repositoryContractTest(name),
      ),
    ];
  }

  /// A small constructor-injected service.
  List<FileGenerationOperation> service(String input) {
    final name = ScaffoldName(input);
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath:
            'lib/features/${name.snake}/application/${name.snake}_service.dart',
        content:
            '''/// Constructor-injected ${name.pascal} application service.
final class ${name.pascal}Service {
  const ${name.pascal}Service();

  Future<void> execute() async {}
}
''',
      ),
    ];
  }

  List<FileGenerationOperation> _remoteReadBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_remote_port.dart',
        content: _remotePort(name),
      ),
      FileGenerationOperation(
        relativePath: '$root/infrastructure/${name.snake}_remote_dto.dart',
        content: _remoteDto(name),
      ),
      FileGenerationOperation(
        relativePath: '$root/infrastructure/${name.snake}_mapper.dart',
        content: _remoteMapper(name),
      ),
      FileGenerationOperation(
        relativePath: '$root/infrastructure/fake_${name.snake}_remote.dart',
        content: _fakeRemote(name),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_mapping_test.dart',
        content: _mappingTest(name),
      ),
    ];
  }

  List<FileGenerationOperation> _localFirstBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_local_store.dart',
        content: _localStorePort(name),
      ),
      FileGenerationOperation(
        relativePath:
            '$root/infrastructure/fake_${name.snake}_local_store.dart',
        content: _fakeLocalStore(name),
      ),
      FileGenerationOperation(
        relativePath: '$root/infrastructure/${name.snake}_pull_source.dart',
        content: _pullSource(name),
      ),
    ];
  }

  List<FileGenerationOperation> _offlineMutationBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_mutation.dart',
        content: _mutationContract(name),
      ),
      FileGenerationOperation(
        relativePath:
            '$root/infrastructure/fake_${name.snake}_outbox_store.dart',
        content: _fakeOutboxStore(name),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_outbox_contract_test.dart',
        content: _outboxTest(name),
      ),
    ];
  }

  List<FileGenerationOperation> _syncDatasetBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_sync_dataset.dart',
        content: _syncDataset(name),
      ),
      FileGenerationOperation(
        relativePath: '$root/infrastructure/fake_${name.snake}_sync_ports.dart',
        content: _fakeSyncPorts(name),
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_sync_contract_test.dart',
        content: _syncTest(name),
      ),
    ];
  }

  String _cursorPage(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';

/// Consumer-decoded cursor page; cursors remain opaque to Dartitect.
final class ${name.pascal}CursorPage<T>({
  required final List<T> items,
  required final String? nextCursor,
});

/// Consumer-owned cursor transport boundary.
abstract interface class ${name.pascal}CursorReader<T, F extends Object> {
  Future<Result<${name.pascal}CursorPage<T>, F>> read({
    required String? cursor,
    required CancellationSignal cancellation,
  });
}
''';

  String _headlessSync(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';

/// Consumer-owned payload accepted by the generated headless composition.
final class ${name.pascal}HeadlessPayload {
  const ${name.pascal}HeadlessPayload();
}

/// Composition seam adapted to dartitect_jobs by application wiring.
abstract interface class ${name.pascal}HeadlessSync {
  Future<void> run(
    ${name.pascal}HeadlessPayload payload,
    CancellationSignal cancellation,
  );
}
''';

  String _immutableModel(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';

/// Immutable domain value generated without product schema assumptions.
final class ${name.pascal}Model({
  /// Stable consumer-owned model identifier.
  required final String id,
  Iterable<String> labels = const <String>[],
}) extends ValueEquality {
  /// Creates a model while defensively copying collection input.
  this : labels = immutableListCopy(labels);

  /// Immutable labels retained by the generated model.
  final List<String> labels;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, labels];
}
''';

  String _architectureTest(ScaffoldName name) =>
      '''import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated slice keeps providers out of presentation and domain', () {
    final feature = Directory(
      '\${_packageRoot('$packageName').path}/lib/features/${name.snake}',
    );
    final files = feature
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      if (file.path.contains('/presentation/') ||
          file.path.contains('/domain/')) {
        expect(source, isNot(contains('package:dio/')));
        expect(source, isNot(contains('package:objectbox/')));
      }
      expect(source, isNot(contains('GetIt')));
    }
  });
}

Directory _packageRoot(String packageName) {
  var directory = Directory.current.absolute;
  while (true) {
    final config = File('\${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      final packages = json['packages']! as List<Object?>;
      final entry = packages.cast<Map<String, Object?>>().singleWhere(
        (candidate) => candidate['name'] == packageName,
      );
      return Directory.fromUri(config.uri.resolve(entry['rootUri']! as String));
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Dart package configuration was not found.');
    }
    directory = directory.parent;
  }
}
''';

  String _remotePort(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';

import '../domain/${name.snake}_model.dart';
import '../domain/${name.snake}_repository.dart';

abstract interface class ${name.pascal}RemotePort {
  Future<Result<List<${name.pascal}Model>, ${name.pascal}Failure>> read(
    CancellationSignal cancellation,
  );
}
''';

  String _remoteDto(ScaffoldName name) =>
      '''/// Infrastructure-only wire value; replace decoding at the provider edge.
final class const ${name.pascal}RemoteDto({
  required final String id,
  required final String label,
});
''';

  String _remoteMapper(ScaffoldName name) =>
      '''import '../domain/${name.snake}_model.dart';
import '${name.snake}_remote_dto.dart';

${name.pascal}Model map${name.pascal}RemoteDto(
  ${name.pascal}RemoteDto dto,
) => ${name.pascal}Model(id: dto.id, labels: <String>[dto.label]);
''';

  String _fakeRemote(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';

import '../application/${name.snake}_remote_port.dart';
import '../domain/${name.snake}_model.dart';
import '../domain/${name.snake}_repository.dart';

final class Fake${name.pascal}Remote implements ${name.pascal}RemotePort {
  @override
  Future<Result<List<${name.pascal}Model>, ${name.pascal}Failure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<List<${name.pascal}Model>>(
      <${name.pascal}Model>[${name.pascal}Model(id: 'fixture')],
    );
  }
}
''';

  String _mappingTest(ScaffoldName name) =>
      '''import 'package:$packageName/features/${name.snake}/infrastructure/${name.snake}_mapper.dart';
import 'package:$packageName/features/${name.snake}/infrastructure/${name.snake}_remote_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps infrastructure DTO into immutable domain value', () {
    final value = map${name.pascal}RemoteDto(
      const ${name.pascal}RemoteDto(id: '1', label: 'A'),
    );
    expect(value.id, '1');
    expect(value.labels, <String>['A']);
  });
}
''';

  String _localStorePort(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';

import '../domain/${name.snake}_model.dart';
import '../domain/${name.snake}_repository.dart';

abstract interface class ${name.pascal}LocalStore {
  Stream<void> watch();
  Future<Result<List<${name.pascal}Model>, ${name.pascal}Failure>> read(
    CancellationSignal cancellation,
  );
}
''';

  String _fakeLocalStore(ScaffoldName name) =>
      '''import 'dart:async';

import 'package:dartitect/dartitect.dart';

import '../application/${name.snake}_local_store.dart';
import '../domain/${name.snake}_model.dart';
import '../domain/${name.snake}_repository.dart';

final class Fake${name.pascal}LocalStore implements ${name.pascal}LocalStore {
  final StreamController<void> changes = StreamController<void>.broadcast();
  final List<${name.pascal}Model> values = <${name.pascal}Model>[];

  @override
  Stream<void> watch() => changes.stream;

  @override
  Future<Result<List<${name.pascal}Model>, ${name.pascal}Failure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<List<${name.pascal}Model>>(List.unmodifiable(values));
  }

  Future<void> dispose() => changes.close();
}
''';

  String _pullSource(ScaffoldName name) =>
      '''import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';

import '../application/${name.snake}_local_store.dart';
import '../domain/${name.snake}_model.dart';
import '../domain/${name.snake}_repository.dart';

PullReactiveSource<List<${name.pascal}Model>, ${name.pascal}Failure>
create${name.pascal}PullSource(${name.pascal}LocalStore store) =>
    PullReactiveSource(
      triggers: <PullInvalidationTrigger>[store.watch],
      pull: store.read,
    );
''';

  String _mutationContract(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/${name.snake}_repository.dart';

final class const ${name.pascal}Mutation({
  /// Consumer-owned aggregate identifier.
  required final String aggregateId,
}) extends ValueEquality {
  /// Completes the primary constructor without adding runtime behavior.
  this;

  @override
  Iterable<Object?> get equalityFields => <Object?>[aggregateId];
}

typedef ${name.pascal}MutationLane =
    MutationLane<String, ${name.pascal}Mutation, void, ${name.pascal}Failure>;
''';

  String _fakeOutboxStore(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../application/${name.snake}_mutation.dart';
import '../domain/${name.snake}_repository.dart';

final class Fake${name.pascal}OutboxStore
    implements MutationOutboxStore<String, ${name.pascal}Mutation, ${name.pascal}Failure> {
  final Map<String, OutboxOperation<String, ${name.pascal}Mutation>> rows =
      <String, OutboxOperation<String, ${name.pascal}Mutation>>{};

  @override
  Future<Result<void, ${name.pascal}Failure>> applyLocalAndEnqueue(
    OutboxOperation<String, ${name.pascal}Mutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    rows[operation.idempotencyKey] = operation;
    return const Ok<void>(null);
  }

  @override
  Future<Result<void, ${name.pascal}Failure>> markState(
    OutboxOperation<String, ${name.pascal}Mutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    rows[operation.idempotencyKey] = operation;
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<OutboxOperation<String, ${name.pascal}Mutation>>, ${name.pascal}Failure>>
  loadRecoverable(CancellationSignal signal) async {
    signal.throwIfCancelled();
    return Ok(List.unmodifiable(rows.values));
  }

  @override
  Future<Result<void, ${name.pascal}Failure>> compensate(
    OutboxOperation<String, ${name.pascal}Mutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    rows.remove(operation.idempotencyKey);
    return const Ok<void>(null);
  }
}
''';

  String _outboxTest(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:$packageName/features/${name.snake}/application/${name.snake}_mutation.dart';
import 'package:$packageName/features/${name.snake}/infrastructure/fake_${name.snake}_outbox_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake persists the exact idempotency key', () async {
    final store = Fake${name.pascal}OutboxStore();
    final cancellation = CancellationSource();
    final operation = OutboxOperation<String, ${name.pascal}Mutation>(
      idempotencyKey: 'fixture-1',
      key: 'fixture',
      argument: const ${name.pascal}Mutation(aggregateId: 'fixture'),
    );
    expect(
      await store.applyLocalAndEnqueue(operation, cancellation.signal),
      const Ok<void>(null),
    );
    expect(store.rows, contains('fixture-1'));
    cancellation.dispose();
  });
}
''';

  String _syncDataset(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/${name.snake}_repository.dart';

SyncDataset<String, int, ${name.pascal}Failure> create${name.pascal}Dataset() =>
    SyncDataset(
      key: '${name.snake}',
      synchronize: (context) async {
        context.cancellation.throwIfCancelled();
        return Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        );
      },
    );
''';

  String _fakeSyncPorts(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

final class Fake${name.pascal}Checkpoints
    implements SyncCheckpointStore<String, int> {
  final Map<String, int> values = <String, int>{};

  @override
  Future<int?> read(String key, CancellationSignal signal) async => values[key];

  @override
  Future<void> write(
    String key,
    int checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    values[key] = checkpoint;
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    values.remove(key);
  }
}
''';

  String _syncTest(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:$packageName/features/${name.snake}/application/${name.snake}_sync_dataset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dataset advances an opaque checkpoint', () async {
    final cancellation = CancellationSource();
    final result = await create${name.pascal}Dataset().synchronize(
      SyncDatasetContext(
        key: '${name.snake}',
        runId: 'fixture',
        checkpoint: 1,
        cancellation: cancellation.signal,
        deadline: null,
      ),
    );
    expect((result as Ok<SyncDatasetOutcome<int>>).value.checkpoint, 2);
    cancellation.dispose();
  });
}
''';

  String _standaloneViewModel(ScaffoldName name) =>
      '''import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/foundation.dart';

/// Constructor-injected native state for the ${name.pascal} feature.
final class ${name.pascal}ViewModel extends ChangeNotifier
    implements AsyncDisposable {
  ${name.pascal}ViewModel(
    Future<Result<void, String>> Function() start,
  ) : startCommand = Command0<void, String>(start) {
    startCommand.addListener(notifyListeners);
  }

  final Command0<void, String> startCommand;

  Future<void> start() async {
    await startCommand.execute();
  }

  Future<void>? _disposeFuture;

  @override
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    startCommand.removeListener(notifyListeners);
    await startCommand.disposeAsync();
    super.dispose();
  }

  @override
  // The async path calls ChangeNotifier.dispose after draining the command.
  // ignore: must_call_super
  void dispose() => unawaited(disposeAsync());
}
''';

  String _featureViewModel(
    ScaffoldName name, {
    required String contractLayer,
  }) =>
      '''import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/foundation.dart';

import '../$contractLayer/${name.snake}_repository.dart';

/// Native MVVM state that depends only on the repository contract.
final class ${name.pascal}ViewModel extends ChangeNotifier
    implements AsyncDisposable {
  ${name.pascal}ViewModel(${name.pascal}Repository repository)
      : loadCommand = Command0<List<String>, ${name.pascal}Failure>(
          repository.load,
        ) {
    loadCommand.addListener(notifyListeners);
  }

  final Command0<List<String>, ${name.pascal}Failure> loadCommand;

  List<String> get items => switch (loadCommand.state) {
    CommandSuccessState<List<String>, ${name.pascal}Failure>(:final value) =>
      value,
    CommandCancelledState<List<String>, ${name.pascal}Failure>() =>
      const <String>[],
    _ => const <String>[],
  };

  Future<void> start() async {
    await loadCommand.execute();
  }

  Future<void>? _disposeFuture;

  @override
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    loadCommand.removeListener(notifyListeners);
    await loadCommand.disposeAsync();
    super.dispose();
  }

  @override
  // The async path calls ChangeNotifier.dispose after draining the command.
  // ignore: must_call_super
  void dispose() => unawaited(disposeAsync());
}
''';

  String _view(ScaffoldName name, {required String contractLayer}) =>
      '''import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../$contractLayer/${name.snake}_repository.dart';
import '../composition/${name.snake}_composition.dart';
import '${name.snake}_view_model.dart';

/// Composition boundary for the ${name.pascal} feature.
final class ${name.pascal}Page extends StatelessWidget {
  const ${name.pascal}Page({super.key});

  @override
  Widget build(BuildContext context) => ViewModelHost<${name.pascal}ViewModel>.create(
    create: ${name.pascal}Composition.createViewModel,
    start: (viewModel) => viewModel.start(),
    builder: (context, viewModel) => ${name.pascal}View(viewModel: viewModel),
  );
}

final class ${name.pascal}View extends StatelessWidget {
  const ${name.pascal}View({required this.viewModel, super.key});

  final ${name.pascal}ViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, child) => switch (viewModel.loadCommand.state) {
      CommandIdleState<List<String>, ${name.pascal}Failure>() ||
      CommandRunningState<List<String>, ${name.pascal}Failure>() =>
        const Text('Loading ${name.pascal}'),
      CommandSuccessState<List<String>, ${name.pascal}Failure>(:final value) =>
        Text(value.isEmpty ? 'No ${name.pascal}' : value.join(', ')),
      CommandFailureState<List<String>, ${name.pascal}Failure>() =>
        const Text('${name.pascal} unavailable'),
      CommandCrashState<List<String>, ${name.pascal}Failure>() =>
        const Text('Unexpected ${name.pascal} failure'),
      CommandCancelledState<List<String>, ${name.pascal}Failure>() =>
        const Text('${name.pascal} cancelled'),
    },
  );
}
''';

  String _standaloneViewModelTest(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:$packageName/features/${name.snake}/presentation/${name.snake}_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts through the injected action', () async {
    var calls = 0;
    final viewModel = ${name.pascal}ViewModel(() async {
      calls += 1;
      return const Ok<void>(null);
    });
    await viewModel.start();
    expect(calls, 1);
    await viewModel.disposeAsync();
  });
}
''';

  String _featureViewModelTest(
    ScaffoldName name, {
    required String contractLayer,
  }) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:$packageName/features/${name.snake}/$contractLayer/${name.snake}_repository.dart';
import 'package:$packageName/features/${name.snake}/presentation/${name.snake}_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads through the injected repository contract', () async {
    final repository = _Repository();
    final viewModel = ${name.pascal}ViewModel(repository);
    await viewModel.start();
    expect(viewModel.items, <String>['Injected ${name.pascal}']);
    expect(repository.calls, 1);
    await viewModel.disposeAsync();
  });
}

final class _Repository implements ${name.pascal}Repository {
  var calls = 0;

  @override
  Future<Result<List<String>, ${name.pascal}Failure>> load() async {
    calls += 1;
    return const Ok<List<String>>(<String>['Injected ${name.pascal}']);
  }
}
''';

  String _repositoryContract(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';

/// Expected failure at the ${name.pascal} repository boundary.
final class ${name.pascal}Failure implements Exception {
  const ${name.pascal}Failure(this.code);

  final String code;
}

/// Pure-Dart ${name.pascal} repository contract.
abstract interface class ${name.pascal}Repository {
  Future<Result<List<String>, ${name.pascal}Failure>> load();
}
''';

  String _memoryRepository(
    ScaffoldName name, {
    required String contractLayer,
  }) =>
      '''import 'package:dartitect/dartitect.dart';

import '../$contractLayer/${name.snake}_repository.dart';

/// Deterministic memory implementation owned by the composition root.
final class Memory${name.pascal}Repository implements ${name.pascal}Repository {
  Memory${name.pascal}Repository([
    Iterable<String> values = const <String>['First ${name.pascal}'],
  ]) : _values = List<String>.of(values);

  final List<String> _values;

  @override
  Future<Result<List<String>, ${name.pascal}Failure>> load() async =>
      Ok<List<String>>(List<String>.unmodifiable(_values));
}
''';

  String _composition(ScaffoldName name) =>
      '''import '../infrastructure/memory_${name.snake}_repository.dart';
import '../presentation/${name.snake}_view_model.dart';

/// Explicit provider-aware composition boundary for ${name.pascal}.
abstract final class ${name.pascal}Composition {
  static ${name.pascal}ViewModel createViewModel() {
    final repository = Memory${name.pascal}Repository();
    return ${name.pascal}ViewModel(repository);
  }
}
''';

  String _repositoryContractTest(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:$packageName/features/${name.snake}/infrastructure/memory_${name.snake}_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('memory repository satisfies the public contract', () async {
    final repository = Memory${name.pascal}Repository(const <String>['A']);
    final result = await repository.load();
    expect(result, isA<Ok<List<String>>>());
    expect((result as Ok<List<String>>).value, <String>['A']);
  });
}
''';

  String _viewTest(ScaffoldName name) =>
      '''import 'package:$packageName/features/${name.snake}/presentation/${name.snake}_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page owns its ViewModel and renders local data', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ${name.pascal}Page(),
      ),
    );
    await tester.pump();
    expect(find.text('First ${name.pascal}'), findsOneWidget);
  });
}
''';
}
