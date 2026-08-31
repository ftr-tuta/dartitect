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
    this.dataset,
    this.transport,
    FeatureLocalAuthorityStrategy? localAuthority,
    Set<DartitectPlatform> targets = const <DartitectPlatform>{},
    this.pagination = FeaturePagination.none,
    Set<DartitectPlatform> headlessTargets = const <DartitectPlatform>{},
    this.diagnostics = FeatureDiagnosticsLevel.basic,
    Set<DartitectCapability> capabilities = const <DartitectCapability>{},
  }) : localAuthority =
           localAuthority ??
           (storageContext == null
               ? FeatureLocalAuthorityStrategy.custom
               : FeatureLocalAuthorityStrategy.generatedPull),
       targets = Set<DartitectPlatform>.unmodifiable(targets),
       headlessTargets = Set<DartitectPlatform>.unmodifiable(headlessTargets),
       capabilities = Set<DartitectCapability>.unmodifiable(capabilities) {
    DartitectFeatureDeclaration(
      profile: profile,
      scope: scope,
      factorySource: DartitectFactorySourceConfig(
        source: 'lib/features/feature/composition/feature_factory.dart',
        declaration: 'FeatureFactory',
      ),
      localAuthority: this.localAuthority,
      storageContext: storageContext,
      dataset: storageContext == null
          ? null
          : dataset ?? DartitectStorageDatasetConfig.forFeature('feature'),
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

  /// Explicit operational dataset facts, or create-feature defaults.
  final DartitectStorageDatasetConfig? dataset;

  /// Consumer-selected named transport.
  final String? transport;

  /// Generated-pull or consumer-custom local authority.
  final FeatureLocalAuthorityStrategy localAuthority;

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
            'lib/features/${name.snake}/composition/${name.snake}_factory.dart',
        content: _featureFactory(name, options),
        rendererId: 'scaffold.feature-factory',
      ),
      FileGenerationOperation(
        relativePath:
            'lib/features/${name.snake}/domain/${name.snake}_model.dart',
        content: _immutableModel(name),
        rendererId: 'scaffold.feature-model',
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
          rendererId: 'scaffold.cursor-page',
        ),
      if (options.headlessTargets.isNotEmpty)
        FileGenerationOperation(
          relativePath:
              'lib/features/${name.snake}/composition/${name.snake}_headless_sync.dart',
          content: _headlessSync(name),
          rendererId: 'scaffold.headless-sync',
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
      rendererId: 'scaffold.config',
    ),
  ];

  /// Local, concise instructions for coding agents.
  List<FileGenerationOperation> agents() => <FileGenerationOperation>[
    const FileGenerationOperation(
      relativePath: 'AGENTS.md',
      content: '''# Dartitect architecture contract

- Validate with `flutter analyze`, `flutter test`, `dart run dartitect_cli:dartitect inspect --json`, and `dart run dartitect_cli:dartitect inspect --consumer-tax --json`.
- Use constructor injection and explicit composition roots.
- Domain must not import Flutter, data implementations, or adapters.
- Presentation and ViewModels must not import Dio or ObjectBox.
- Do not use service locators, architecture/state frameworks, or private `src/` imports.
- `ViewModelHost.create` owns its value; `ViewModelHost.value` borrows it.
- Keep routing and UI effects in Widgets.
- Before adding infrastructure, ask: É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?
- It belongs in Dartitect only when all three answers are yes; otherwise use a typed project-local extension or keep business behavior in the application.
''',
      rendererId: 'scaffold.agents',
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
        rendererId: 'scaffold.repository-contract',
      ),
      FileGenerationOperation(
        relativePath:
            'test/support/features/${name.snake}/memory_${name.snake}_repository.dart',
        content: _memoryRepository(name, contractLayer: contractLayer),
        rendererId: 'scaffold.memory-repository',
      ),
      FileGenerationOperation(
        relativePath: '$root/presentation/${name.snake}_view_model.dart',
        content: _featureViewModel(name, contractLayer: contractLayer),
        rendererId: 'scaffold.view-model',
      ),
      FileGenerationOperation(
        relativePath: '$root/presentation/${name.snake}_view.dart',
        content: _view(name, contractLayer: contractLayer),
        rendererId: 'scaffold.view',
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_view_model_test.dart',
        content: _featureViewModelTest(name, contractLayer: contractLayer),
        rendererId: 'scaffold.view-model-test',
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_repository_contract_test.dart',
        content: _repositoryContractTest(name),
        rendererId: 'scaffold.repository-contract-test',
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_view_test.dart',
        content: _viewTest(name),
        rendererId: 'scaffold.view-test',
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
        rendererId: 'scaffold.standalone-view-model',
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_view_model_test.dart',
        content: _standaloneViewModelTest(name),
        rendererId: 'scaffold.standalone-view-model-test',
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
        rendererId: 'scaffold.repository-contract',
      ),
      FileGenerationOperation(
        relativePath:
            'test/support/features/${name.snake}/memory_${name.snake}_repository.dart',
        content: _memoryRepository(name, contractLayer: 'domain'),
        rendererId: 'scaffold.memory-repository',
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_repository_contract_test.dart',
        content: _repositoryContractTest(name),
        rendererId: 'scaffold.repository-contract-test',
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
        rendererId: 'scaffold.service',
      ),
    ];
  }

  List<FileGenerationOperation> _remoteReadBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_remote_port.dart',
        content: _remotePort(name),
        rendererId: 'scaffold.remote-port',
      ),
      FileGenerationOperation(
        relativePath: '$root/infrastructure/${name.snake}_remote_dto.dart',
        content: _remoteDto(name),
        rendererId: 'scaffold.remote-dto',
      ),
      FileGenerationOperation(
        relativePath: '$root/infrastructure/${name.snake}_mapper.dart',
        content: _remoteMapper(name),
        rendererId: 'scaffold.mapper',
      ),
      FileGenerationOperation(
        relativePath:
            'test/features/${name.snake}/${name.snake}_mapping_test.dart',
        content: _mappingTest(name),
        rendererId: 'scaffold.mapping-test',
      ),
    ];
  }

  List<FileGenerationOperation> _localFirstBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_local_store.dart',
        content: _localStorePort(name),
        rendererId: 'scaffold.local-store',
      ),
    ];
  }

  List<FileGenerationOperation> _offlineMutationBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_mutation.dart',
        content: _mutationContract(name),
        rendererId: 'scaffold.mutation',
      ),
    ];
  }

  List<FileGenerationOperation> _syncDatasetBlueprint(ScaffoldName name) {
    final root = 'lib/features/${name.snake}';
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath: '$root/application/${name.snake}_sync_dataset.dart',
        content: _syncDataset(name),
        rendererId: 'scaffold.sync-dataset',
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

  String _featureFactory(ScaffoldName name, FeatureScaffoldOptions options) {
    final hasStorage = options.storageContext != null;
    final hasTransport = options.transport != null;
    final generatedPull =
        hasStorage &&
        options.localAuthority == FeatureLocalAuthorityStrategy.generatedPull;
    final synchronized =
        options.profile == FeatureProfile.replica ||
        options.profile == FeatureProfile.offlineFull;
    final offline = options.profile == FeatureProfile.offlineFull;
    final imports = <String>[
      "import 'package:dartitect/dartitect.dart';",
      if (generatedPull)
        "import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';",
      if (synchronized) "import 'package:dartitect_sync/dartitect_sync.dart';",
      '',
      if (generatedPull) "import '../domain/${name.snake}_model.dart';",
      "import '../domain/${name.snake}_repository.dart';",
      if (hasStorage) "import '../application/${name.snake}_local_store.dart';",
      if (hasTransport)
        "import '../application/${name.snake}_remote_port.dart';",
      if (synchronized)
        "import '../application/${name.snake}_sync_dataset.dart';",
      if (offline) "import '../application/${name.snake}_mutation.dart';",
      if (hasTransport) "import '../infrastructure/${name.snake}_mapper.dart';",
      "import '../presentation/${name.snake}_view_model.dart';",
    ];
    final repositoryParameters = <String>[
      if (hasStorage) '${name.pascal}LocalStore localPort',
      if (hasTransport) '${name.pascal}RemotePort remotePort',
      if (hasTransport) '${name.pascal}Mapper mapper',
      if (generatedPull)
        'PullReactiveSource<List<${name.pascal}Model>, ${name.pascal}Failure> localAuthority',
    ];
    final repositorySignature = repositoryParameters.isEmpty
        ? '()'
        : '(\n    ${repositoryParameters.join(',\n    ')},\n  )';
    final localMethods = !hasStorage
        ? ''
        : '''
  ${name.pascal}LocalStore createLocalPort() => throw UnimplementedError(
    'Implement the ${name.pascal} local port with the selected storage context.',
  );

${generatedPull ? '''  Stream<void> watch(${name.pascal}LocalStore localPort) =>
      localPort.watch();

  Future<Result<List<${name.pascal}Model>, ${name.pascal}Failure>> read(
    ${name.pascal}LocalStore localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
''' : '''  ${name.pascal}LocalStore createLocalAuthority(
    ${name.pascal}LocalStore localPort,
  ) => localPort;
'''}''';
    final transportMethods = !hasTransport
        ? ''
        : '''
  ${name.pascal}RemotePort createRemotePort() => throw UnimplementedError(
    'Implement the ${name.pascal} remote port with the selected transport.',
  );

  ${name.pascal}Mapper createMapper() => const ${name.pascal}Mapper();
''';
    final datasetMethod = !synchronized
        ? ''
        : '''
  SyncDataset<String, int, ${name.pascal}Failure> createDataset() =>
      create${name.pascal}Dataset();

  SyncCheckpointStore<String, int> createCheckpointStore() =>
      throw UnimplementedError(
        'Adapt the selected storage context to SyncCheckpointStore.',
      );
''';
    final policyMethods = !offline
        ? ''
        : '''
  MutationOutboxStore<String, ${name.pascal}Mutation, ${name.pascal}Failure>
  createOutboxStore(${name.pascal}LocalStore localPort) =>
      throw UnimplementedError(
        'Adapt the selected storage context to MutationOutboxStore.',
      );

  MutationIdempotencyPolicy<String, ${name.pascal}Mutation>
  createIdempotencyPolicy() =>
      const ${name.pascal}IdempotencyPolicy();

  MutationConflictPolicy<${name.pascal}Model> createConflictPolicy() =>
      const ${name.pascal}ConflictPolicy();

  Future<Result<void, ${name.pascal}Failure>> synchronizeMutation(
    ${name.pascal}RemotePort remotePort,
    OutboxOperation<String, ${name.pascal}Mutation> operation,
    CancellationSignal cancellation,
  ) => throw UnimplementedError(
    'Implement remote delivery with explicit status semantics.',
  );

  MutationFailurePolicy classifyMutationFailure(
    ${name.pascal}Failure failure,
  ) => const MutationFailurePolicy.queued();
''';
    final policyTypes = !offline
        ? ''
        : '''
/// Consumer-owned idempotency semantics; Dartitect owns their orchestration.
final class ${name.pascal}IdempotencyPolicy
    implements MutationIdempotencyPolicy<String, ${name.pascal}Mutation> {
  const ${name.pascal}IdempotencyPolicy();

  @override
  String create(String key, ${name.pascal}Mutation argument) =>
      '${name.snake}:\$key:\${argument.aggregateId}';
}

/// Consumer-owned conflict semantics; Dartitect owns their orchestration.
final class ${name.pascal}ConflictPolicy
    implements MutationConflictPolicy<${name.pascal}Model> {
  const ${name.pascal}ConflictPolicy();

  @override
  ${name.pascal}Model resolve(
    ${name.pascal}Model local,
    ${name.pascal}Model remote,
  ) => local;
}
''';
    return '''${imports.join('\n')}

/// Consumer-owned domain seams selected by generated graph composition.
@DartitectFeatureFactory('${name.snake}')
final class ${name.pascal}Factory {
  const ${name.pascal}Factory();

  ${name.pascal}Repository createRepository$repositorySignature =>
      throw UnimplementedError(
        'Implement ${name.pascal}Repository with the typed seams above.',
      );
$localMethods$transportMethods$datasetMethod$policyMethods
  ${name.pascal}ViewModel createViewModel(
    ${name.pascal}Repository repository,
  ) => ${name.pascal}ViewModel(repository);
}
$policyTypes''';
  }

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

/// Consumer-owned DTO-to-domain policy selected by the feature factory.
final class ${name.pascal}Mapper {
  const ${name.pascal}Mapper();

  ${name.pascal}Model map(${name.pascal}RemoteDto dto) =>
      ${name.pascal}Model(id: dto.id, labels: <String>[dto.label]);
}

${name.pascal}Model map${name.pascal}RemoteDto(
  ${name.pascal}RemoteDto dto,
) => const ${name.pascal}Mapper().map(dto);
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

  String _standaloneViewModel(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';

/// Constructor-injected native state for the ${name.pascal} feature.
final class ${name.pascal}ViewModel(
  Future<Result<void, String>> Function() start,
) extends DartitectViewModel {
  /// Owns the command for this ViewModel lifetime.
  this {
    startCommand = ownCommand(
      Command0<void, String>(start),
      label: 'startCommand',
    );
  }

  late final Command0<void, String> startCommand;

  Future<void> start() async {
    await startCommand.execute();
  }
}
''';

  String _featureViewModel(
    ScaffoldName name, {
    required String contractLayer,
  }) =>
      '''import 'package:dartitect_flutter/dartitect_flutter.dart';

import '../$contractLayer/${name.snake}_repository.dart';

/// Native MVVM state that depends only on the repository contract.
final class ${name.pascal}ViewModel(${name.pascal}Repository repository)
    extends DartitectViewModel {
  /// Owns the repository command for this ViewModel lifetime.
  this {
    loadCommand = ownCommand(
      Command0<List<String>, ${name.pascal}Failure>(repository.load),
      label: 'loadCommand',
    );
  }

  late final Command0<List<String>, ${name.pascal}Failure> loadCommand;

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
}
''';

  String _view(ScaffoldName name, {required String contractLayer}) =>
      '''import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '../$contractLayer/${name.snake}_repository.dart';
import '${name.snake}_view_model.dart';

/// Composition boundary for the ${name.pascal} feature.
final class ${name.pascal}Page extends StatelessWidget {
  const ${name.pascal}Page({required this.repository, super.key});

  final ${name.pascal}Repository repository;

  @override
  Widget build(BuildContext context) => ViewModelHost<${name.pascal}ViewModel>.create(
    create: () => ${name.pascal}ViewModel(repository),
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
import 'package:$packageName/features/${name.snake}/$contractLayer/${name.snake}_repository.dart';

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

  String _repositoryContractTest(ScaffoldName name) =>
      '''import 'package:dartitect/dartitect.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/features/${name.snake}/memory_${name.snake}_repository.dart';

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

import '../../support/features/${name.snake}/memory_${name.snake}_repository.dart';

void main() {
  testWidgets('page owns its ViewModel and renders local data', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ${name.pascal}Page(
          repository: Memory${name.pascal}Repository(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('First ${name.pascal}'), findsOneWidget);
  });
}
''';
}
