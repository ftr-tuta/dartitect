import 'dart:convert';
import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:dartitect/dartitect.dart';

import '../config/dartitect_config.dart';
import '../extensions/local_extension_compiler.dart';
import 'generation_engine.dart';

/// Deterministic preview or apply receipt for managed feature wiring.
final class DartitectWiringReport {
  /// Creates a wiring report.
  const DartitectWiringReport({
    required this.plan,
    required this.applied,
    required this.writes,
  });

  /// Revalidated generation plan.
  final GenerationPlan plan;

  /// Whether the managed namespace was applied.
  final bool applied;

  /// Number of output writes or deletions performed.
  final int writes;

  /// Whether all managed outputs are current.
  bool get isFresh => applied || !plan.hasChanges && !plan.pendingRecovery;

  /// Stable machine-readable representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'wiring sync',
    'applied': applied,
    'fresh': isFresh,
    'pendingRecovery': plan.pendingRecovery,
    'writes': writes,
    'operations': <Object?>[
      for (final operation in plan.operations)
        <String, Object?>{
          'path': operation.operation.relativePath,
          'disposition': operation.disposition.name,
        },
    ],
  };
}

/// Converges direct-constructor feature wiring from strict config v2.
final class DartitectWiringService {
  /// Creates a service for one project root.
  DartitectWiringService(Directory root) : root = root.absolute;

  /// Project root whose managed namespace is synchronized.
  final Directory root;

  static const GenerationNamespace _namespace = GenerationNamespace(
    'wiring',
    fullyGeneratedSuffix: '.wiring.dartitect.g.dart',
  );

  /// Produces a read-only deterministic preview.
  Future<DartitectWiringReport> inspect({DartitectConfig? config}) async {
    final resolved = config ?? await _loadConfig();
    final extensions = await DartitectLocalExtensionCompiler(root)
        .compile(resolved.extensionSources);
    final plan = await GenerationEngine(
      root,
      namespace: _namespace,
    ).plan(_operations(resolved, extensions), manageFullyGenerated: true);
    return DartitectWiringReport(plan: plan, applied: false, writes: 0);
  }

  /// Recovers and atomically converges the complete managed namespace.
  Future<DartitectWiringReport> apply({DartitectConfig? config}) async {
    final resolved = config ?? await _loadConfig();
    final extensions = await DartitectLocalExtensionCompiler(root)
        .compile(resolved.extensionSources);
    final result = await GenerationEngine(
      root,
      namespace: _namespace,
    ).apply(_operations(resolved, extensions), manageFullyGenerated: true);
    return DartitectWiringReport(
      plan: result.plan,
      applied: true,
      writes:
          result.createdPaths.length +
          result.updatedPaths.length +
          result.deletedPaths.length,
    );
  }

  Future<DartitectConfig> _loadConfig() async {
    final file = File(_join(root.path, 'dartitect.json'));
    if (!await file.exists()) {
      throw const DartitectConfigException(
        '/features',
        'dartitect.json is required for wiring sync',
      );
    }
    return DartitectConfig.load(file);
  }

  static List<FileGenerationOperation> _operations(
    DartitectConfig config,
    List<DartitectLocalExtensionIr> extensions,
  ) {
    final entries = config.features.declarations.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <FileGenerationOperation>[
      ..._applicationOperations(config, extensions),
      for (final entry in entries) ...<FileGenerationOperation>[
        FileGenerationOperation(
          relativePath:
              'lib/features/${entry.key}/composition/'
              '${entry.key}.wiring.dartitect.g.dart',
          content: _formatDart(
            _render(entry.key, entry.value, config.scheduler.provider),
            '${entry.key}.wiring.dartitect.g.dart',
          ),
          ownership: GeneratedOwnership.fullyGenerated,
          sourcePath: 'dartitect.json',
          rendererVersion: 2,
          semanticSchemaVersion: 1,
          inputSignature: jsonEncode(<String, Object?>{
            'name': entry.key,
            'scheduler': config.scheduler.toJson(),
            'declaration': entry.value.toJson(),
          }),
        ),
        if (entry.value.storageContext case final String storageName
            when config.storageContexts[storageName]?.provider == 'drift')
          _managedOperation(
            entry.key,
            entry.value,
            'infrastructure/${entry.key}_drift.wiring.dartitect.g.dart',
            _renderDrift(entry.key),
          ),
        if (entry.value.storageContext case final String storageName
            when config.storageContexts[storageName]?.provider == 'objectbox')
          _managedOperation(
            entry.key,
            entry.value,
            'infrastructure/${entry.key}_objectbox.wiring.dartitect.g.dart',
            _renderObjectBox(entry.key),
          ),
        if (entry.value.transport case final String transportName
            when config.transports[transportName]?.provider == 'dio')
          _managedOperation(
            entry.key,
            entry.value,
            'infrastructure/${entry.key}_dio.wiring.dartitect.g.dart',
            _renderDio(entry.key),
          ),
        if (config.scheduler.provider == 'workmanager' &&
            entry.value.headlessTargets.isNotEmpty)
          _managedOperation(
            entry.key,
            entry.value,
            'composition/${entry.key}_workmanager.wiring.dartitect.g.dart',
            _renderWorkmanager(entry.key),
          ),
      ],
    ];
  }

  static List<FileGenerationOperation> _applicationOperations(
    DartitectConfig config,
    List<DartitectLocalExtensionIr> extensions,
  ) {
    final observabilityProvider = config.observability.provider;
    final signature = jsonEncode(<String, Object?>{
      'scheduler': config.scheduler.toJson(),
      'observability': observabilityProvider,
      'extensions': extensions.map((extension) => extension.toJson()).toList(),
    });
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath:
            'lib/composition/application_module.wiring.dartitect.g.dart',
        content: _formatDart(
          _renderApplicationModule(
            scheduler: config.scheduler.provider,
            observability: observabilityProvider,
            extensions: extensions,
          ),
          'application_module.wiring.dartitect.g.dart',
        ),
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'dartitect.json',
        rendererVersion: 2,
        semanticSchemaVersion: 2,
        inputSignature: signature,
      ),
      FileGenerationOperation(
        relativePath: 'lib/composition/session_module.wiring.dartitect.g.dart',
        content: _formatDart(
          _renderSessionModule(),
          'session_module.wiring.dartitect.g.dart',
        ),
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'dartitect.json',
        rendererVersion: 2,
        semanticSchemaVersion: 2,
        inputSignature: signature,
      ),
    ];
  }

  static FileGenerationOperation _managedOperation(
    String name,
    DartitectFeatureDeclaration declaration,
    String suffix,
    String content,
  ) => FileGenerationOperation(
    relativePath: 'lib/features/$name/$suffix',
    content: _formatDart(content, suffix),
    ownership: GeneratedOwnership.fullyGenerated,
    sourcePath: 'dartitect.json',
    rendererVersion: 2,
    semanticSchemaVersion: 1,
    inputSignature: jsonEncode(<String, Object?>{
      'name': name,
      'declaration': declaration.toJson(),
      'output': suffix,
    }),
  );

  static String _render(
    String name,
    DartitectFeatureDeclaration declaration,
    String scheduler,
  ) {
    final type = _pascal(name);
    final slots = _assemblySlots(declaration);
    final typeParameters = <String>[
      for (final slot in slots) '${slot.typeName} extends Object',
      'ViewModel extends Object',
    ].join(', ');
    final typeArguments = <String>[
      for (final slot in slots) slot.typeName,
      'ViewModel',
    ].join(', ');
    final bindingTypeParameters = slots
        .map((slot) => '${slot.typeName} extends Object')
        .join(', ');
    final bindingTypeArguments = slots.map((slot) => slot.typeName).join(', ');
    final bindingParameters = slots
        .map(
          (slot) =>
              '    required DartitectAssemblyBinding<${slot.typeName}> '
              '${slot.fieldName},',
        )
        .join('\n');
    final bindingArguments = slots
        .map(
          (slot) =>
              '          ${slot.fieldName}: '
              '${slot.fieldName}.bind(transaction),',
        )
        .join('\n');
    final getters = slots
        .map(
          (slot) =>
              '  ${slot.typeName} get ${slot.fieldName} => '
              '_graph.root.${slot.fieldName};',
        )
        .join('\n');
    final bindingFields = slots
        .map((slot) => '  required final ${slot.typeName} ${slot.fieldName},')
        .join('\n');
    final storageFact = declaration.storageContext == null
        ? ''
        : "  static const String storageContext = '${declaration.storageContext}';\n";
    final transportFact = declaration.transport == null
        ? ''
        : "  static const String transport = '${declaration.transport}';\n";
    final schedulerFact = declaration.headlessTargets.isEmpty
        ? ''
        : "  static const String scheduler = '$scheduler';\n";
    final headless = _renderStringList(
      declaration.headlessTargets.map((target) => target.wireName),
    );
    final targets = _renderStringList(
      declaration.targets.map((target) => target.wireName),
    );
    final capabilities = _renderStringList(
      declaration.capabilities.map((capability) => capability.wireName),
    );
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Capability-closed typed assembly for the $type feature graph.
final class ${type}FeatureAssembly<$typeParameters> implements AsyncDisposable {
  ${type}FeatureAssembly._(this._graph, this.createViewModel);

  /// Acquires exactly the owned or borrowed bindings selected by config v2.
  static Future<${type}FeatureAssembly<$typeArguments>> create<$typeParameters>({
$bindingParameters
    required ViewModel Function(
      ${type}FeatureAssembly<$typeArguments> assembly,
    ) createViewModel,
  }) async {
    final graph = await ResourceTransaction.create(
      (transaction) => _${type}FeatureBindings<$bindingTypeArguments>(
$bindingArguments
      ),
      label: '$name-feature-assembly',
    );
    return ${type}FeatureAssembly<$typeArguments>._(
      graph,
      createViewModel,
    );
  }

  final OwnedGraph<_${type}FeatureBindings<$bindingTypeArguments>> _graph;

$getters

  /// Constructs presentation state from this exact typed assembly.
  final ViewModel Function(
    ${type}FeatureAssembly<$typeArguments> assembly,
  ) createViewModel;

  /// Whether every owned binding has completed teardown.
  bool get isDisposed => _graph.isDisposed;

  /// Creates the ViewModel while the assembly remains live.
  ViewModel buildViewModel() {
    if (!_graph.isAccepting) {
      throw StateError('$type feature assembly is disposed.');
    }
    return createViewModel(this);
  }

  @override
  Future<void> disposeAsync() => _graph.disposeAsync();
}

final class _${type}FeatureBindings<$bindingTypeParameters>({
$bindingFields
});

/// Closed generated facts used by composition and capability reporting.
abstract final class ${type}FeatureWiring {
  static const String profile = '${declaration.profile.wireName}';
  static const String scope = '${declaration.scope.wireName}';
$storageFact$transportFact  static const List<String> targets = $targets;
  static const String pagination = '${declaration.pagination.wireName}';
  static const String diagnostics = '${declaration.diagnostics.wireName}';
$schedulerFact  static const List<String> headlessTargets = $headless;
  static const List<String> capabilities = $capabilities;

  /// Creates the public application-host factory while keeping graph ownership
  /// and atomic publication inside generated code.
  static BootstrapCoordinator<ViewModel> Function()
  application<$typeParameters>({
    required FutureOr<${type}FeatureAssembly<$typeArguments>> Function()
    createAssembly,
  }) =>
      () => BootstrapCoordinator<ViewModel>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, context) async {
          context.throwIfUnavailable();
          final assembly = transaction.own<
            ${type}FeatureAssembly<$typeArguments>
          >(
            await createAssembly(),
            (value) => value.disposeAsync(),
            label: '$name-feature-assembly',
          );
          context.throwIfUnavailable();
          return assembly.buildViewModel();
        },
      );
}
''';
  }

  static List<_AssemblySlot> _assemblySlots(
    DartitectFeatureDeclaration declaration,
  ) => <_AssemblySlot>[
    const _AssemblySlot('Repository', 'repository'),
    if (declaration.storageContext != null)
      const _AssemblySlot('Storage', 'storage'),
    if (declaration.transport != null)
      const _AssemblySlot('Transport', 'transport'),
    if (declaration.profile == FeatureProfile.cache ||
        declaration.profile == FeatureProfile.replica ||
        declaration.profile == FeatureProfile.offlineFull)
      const _AssemblySlot('LocalAuthority', 'localAuthority'),
    if (declaration.pagination == FeaturePagination.cursor)
      const _AssemblySlot('Pagination', 'pagination'),
    if (declaration.profile == FeatureProfile.offlineFull)
      const _AssemblySlot('Outbox', 'outbox'),
    if (declaration.profile == FeatureProfile.replica ||
        declaration.profile == FeatureProfile.offlineFull)
      const _AssemblySlot('SyncDataset', 'syncDataset'),
    if (declaration.headlessTargets.isNotEmpty)
      const _AssemblySlot('HeadlessJob', 'headlessJob'),
    if (declaration.diagnostics != FeatureDiagnosticsLevel.off)
      const _AssemblySlot('Diagnostics', 'diagnostics'),
    for (final capability in declaration.capabilities)
      _AssemblySlot(_pascal(capability.wireName), capability.wireName),
  ];

  static String _renderApplicationModule({
    required String scheduler,
    required String observability,
    required List<DartitectLocalExtensionIr> extensions,
  }) {
    final typeParameters = <String>[
      'Session extends Object',
      'SessionFailure extends Object',
    ];
    final typeArguments = <String>['Session', 'SessionFailure'];
    final constructorParameters = <String>['    required this.sessions,'];
    final fields = <String>[
      '  final SessionRuntimeController<Session, SessionFailure> sessions;',
    ];
    final createParameters = <String>[];
    final construction = <String>[
      '''          final sessions = transaction.own(
            SessionRuntimeController<Session, SessionFailure>(),
            (controller) => controller.disposeAsync(),
            label: 'application.sessions',
          );''',
    ];
    final arguments = <String>['            sessions: sessions,'];
    final imports = <String>{
      for (final extension in extensions) extension.libraryUri,
      for (final extension in extensions) ...extension.bindingLibraryUris,
    };

    if (scheduler == 'workmanager') {
      imports.add('package:dartitect_workmanager/dartitect_workmanager.dart');
      constructorParameters.add('    required this.scheduler,');
      fields.add('  final DartitectWorkmanagerScheduler scheduler;');
      construction.add(
        '          final scheduler = DartitectWorkmanagerScheduler();',
      );
      arguments.add('            scheduler: scheduler,');
    } else if (scheduler != 'none') {
      typeParameters.add('Scheduler extends Object');
      typeArguments.add('Scheduler');
      constructorParameters.add('    required this.scheduler,');
      fields.add('  final Scheduler scheduler;');
      createParameters.addAll(<String>[
        '    required FutureOr<Scheduler> Function() createScheduler,',
        '    required FutureOr<void> Function(Scheduler) disposeScheduler,',
      ]);
      construction.add(
        '''          final scheduler = transaction.own<Scheduler>(
            await createScheduler(),
            disposeScheduler,
            label: 'application.scheduler',
          );''',
      );
      arguments.add('            scheduler: scheduler,');
    }

    if (observability == 'developer') {
      imports.add(
        'package:dartitect_observability/dartitect_observability.dart',
      );
      constructorParameters.add('    required this.observability,');
      fields.add('  final ObservabilityRuntime observability;');
      construction.add('''          final observability = transaction.own(
            ObservabilityRuntime(),
            (runtime) => runtime.disposeAsync(),
            label: 'application.observability',
          );''');
      arguments.add('            observability: observability,');
    } else if (observability == 'sentry') {
      imports.add(
        'package:dartitect_observability/dartitect_observability.dart',
      );
      constructorParameters.add('    required this.observability,');
      fields.add('  final ObservabilityRuntime observability;');
      createParameters.add(
        '    required FutureOr<ObservabilityRuntime> Function() '
        'createObservability,',
      );
      construction.add('''          final observability = transaction.own(
            await createObservability(),
            (runtime) => runtime.disposeAsync(),
            label: 'application.observability',
          );''');
      arguments.add('            observability: observability,');
    } else if (observability != 'none') {
      typeParameters.add('Observability extends Object');
      typeArguments.add('Observability');
      constructorParameters.add('    required this.observability,');
      fields.add('  final Observability observability;');
      createParameters.addAll(<String>[
        '    required FutureOr<Observability> Function() createObservability,',
        '    required FutureOr<void> Function(Observability) disposeObservability,',
      ]);
      construction.add(
        '''          final observability = transaction.own<Observability>(
            await createObservability(),
            disposeObservability,
            label: 'application.observability',
          );''',
      );
      arguments.add('            observability: observability,');
    }

    imports
      ..remove('package:dartitect/dartitect.dart')
      ..remove('package:dartitect_flutter/dartitect_flutter.dart');
    final orderedImports = imports.toList()..sort();
    final extensionImports = orderedImports
        .map((uri) => "import '$uri';")
        .join('\n');
    for (final extension in extensions) {
      constructorParameters.add('    required this.${extension.fieldName},');
      fields.add('  final ${extension.bindingType} ${extension.fieldName};');
      final declaration = '${extension.fieldName}Declaration';
      construction.add(
        '''          final $declaration = ${extension.declarationType}();
          final ${extension.bindingType} ${extension.fieldName} =
              transaction.own<${extension.bindingType}>(
                await $declaration.build(),
                $declaration.dispose,
                label: 'project-extension.${extension.fieldName}',
              );''',
      );
      arguments.add(
        '            ${extension.fieldName}: ${extension.fieldName},',
      );
    }
    final genericDeclaration = typeParameters.join(', ');
    final genericArguments = typeArguments.join(', ');
    final createSignature = createParameters.isEmpty
        ? '()'
        : '({\n${createParameters.join('\n')}\n  })';
    final asyncImport = createParameters.isEmpty
        ? ''
        : "import 'dart:async';\n\n";
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

$asyncImport
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
${extensionImports.isEmpty ? '' : extensionImports}

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph<$genericDeclaration> {
  const ApplicationGraph({
${constructorParameters.join('\n')}
  });

${fields.join('\n')}
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph<$genericArguments>>
  create<$genericDeclaration>$createSignature =>
      BootstrapCoordinator<ApplicationGraph<$genericArguments>>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) async {
${construction.join('\n')}
          return ApplicationGraph<$genericArguments>(
${arguments.join('\n')}
          );
        },
      );
}
''';
  }

  static String _renderSessionModule() =>
      '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v2.

import 'package:dartitect_flutter/dartitect_flutter.dart';

/// Tooling-materialized session composition module.
abstract final class SessionModule {
  static SessionRuntimeController<R, D> create<R, D extends Object>() =>
      SessionRuntimeController<R, D>();
}
''';

  static String _renderDrift(String name) {
    final type = _pascal(name);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Operational schema only; domain tables and queries remain consumer-owned.

import 'package:dartitect_drift/dartitect_drift.dart';

const int ${name}DartitectDriftSchemaVersion = 1;

class ${type}DartitectOutboxRows extends Table {
  TextColumn get id => text()();
  TextColumn get dataset => text()();
  TextColumn get idempotencyKey => text().unique()();
  BlobColumn get payload => blob()();
  TextColumn get state => text()();
  IntColumn get attempt => integer().withDefault(const Constant<int>(0))();
  IntColumn get createdAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class ${type}DartitectCheckpointRows extends Table {
  TextColumn get dataset => text()();
  BlobColumn get checkpoint => blob()();
  IntColumn get fencingToken => integer().nullable()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class ${type}DartitectJournalRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get attemptId => text()();
  IntColumn get sequence => integer()();
  TextColumn get fact => text()();
  IntColumn get recordedAtMicros => integer()();
}

class ${type}DartitectLeaseRows extends Table {
  TextColumn get dataset => text()();
  TextColumn get owner => text()();
  IntColumn get fencingToken => integer()();
  IntColumn get expiresAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dataset};
}

class ${type}DartitectReceiptRows extends Table {
  TextColumn get operationId => text()();
  TextColumn get status => text()();
  IntColumn get recordedAtMicros => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{operationId};
}

class ${type}DartitectTransferCheckpointRows extends Table {
  TextColumn get transferId => text()();
  IntColumn get committedOffset => integer()();
  IntColumn get revision => integer()();
  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{transferId};
}
''';
  }

  static String _renderObjectBox(String name) {
    final type = _pascal(name);
    int uid(String value) => _stableUid('$name/$value');
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Provider exception: mutable ObjectBox 5.3.2 entities require classic fields.
// UIDs are deterministic and must remain preserved by wiring sync.

import 'package:dartitect_objectbox/dartitect_objectbox.dart';

const int ${name}DartitectObjectBoxSchemaVersion = 1;

@Entity(uid: ${uid('outbox')})
final class ${type}DartitectOutboxEntity {
  ${type}DartitectOutboxEntity({this.id = 0, required this.operationId,
      required this.dataset, required this.idempotencyKey,
      required this.payload, required this.state, this.attempt = 0});
  @Id() int id;
  @Property(uid: ${uid('outbox/operationId')}) String operationId;
  @Property(uid: ${uid('outbox/dataset')}) String dataset;
  @Property(uid: ${uid('outbox/idempotencyKey')}) String idempotencyKey;
  @Property(uid: ${uid('outbox/payload')}) List<int> payload;
  @Property(uid: ${uid('outbox/state')}) String state;
  @Property(uid: ${uid('outbox/attempt')}) int attempt;
}

@Entity(uid: ${uid('checkpoint')})
final class ${type}DartitectCheckpointEntity {
  ${type}DartitectCheckpointEntity({this.id = 0, required this.dataset,
      required this.checkpoint, this.fencingToken = 0});
  @Id() int id;
  @Property(uid: ${uid('checkpoint/dataset')}) String dataset;
  @Property(uid: ${uid('checkpoint/value')}) List<int> checkpoint;
  @Property(uid: ${uid('checkpoint/fencing')}) int fencingToken;
}

@Entity(uid: ${uid('journal')})
final class ${type}DartitectJournalEntity {
  ${type}DartitectJournalEntity({this.id = 0, required this.attemptId,
      required this.sequence, required this.fact,
      required this.recordedAtMicros});
  @Id() int id;
  @Property(uid: ${uid('journal/attemptId')}) String attemptId;
  @Property(uid: ${uid('journal/sequence')}) int sequence;
  @Property(uid: ${uid('journal/fact')}) String fact;
  @Property(uid: ${uid('journal/recordedAt')}) int recordedAtMicros;
}

@Entity(uid: ${uid('lease')})
final class ${type}DartitectLeaseEntity {
  ${type}DartitectLeaseEntity({this.id = 0, required this.dataset,
      required this.owner, required this.fencingToken,
      required this.expiresAtMicros});
  @Id() int id;
  @Property(uid: ${uid('lease/dataset')}) String dataset;
  @Property(uid: ${uid('lease/owner')}) String owner;
  @Property(uid: ${uid('lease/fencing')}) int fencingToken;
  @Property(uid: ${uid('lease/expiry')}) int expiresAtMicros;
}

@Entity(uid: ${uid('receipt')})
final class ${type}DartitectReceiptEntity {
  ${type}DartitectReceiptEntity({this.id = 0, required this.operationId,
      required this.status, required this.recordedAtMicros});
  @Id() int id;
  @Property(uid: ${uid('receipt/operationId')}) String operationId;
  @Property(uid: ${uid('receipt/status')}) String status;
  @Property(uid: ${uid('receipt/recordedAt')}) int recordedAtMicros;
}

@Entity(uid: ${uid('transfer')})
final class ${type}DartitectTransferCheckpointEntity {
  ${type}DartitectTransferCheckpointEntity({this.id = 0,
      required this.transferId, required this.committedOffset,
      required this.revision});
  @Id() int id;
  @Property(uid: ${uid('transfer/id')}) String transferId;
  @Property(uid: ${uid('transfer/offset')}) int committedOffset;
  @Property(uid: ${uid('transfer/revision')}) int revision;
}
''';
  }

  static String _renderDio(String name) {
    final type = _pascal(name);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';

/// Owned Dio client with deadlines, typed failures, tracing hooks, and cancellation.
final class ${type}DioModule implements Disposable {
  ${type}DioModule._(this.owner, this.client);

  factory ${type}DioModule.create({
    required Duration connectTimeout,
    required Duration receiveTimeout,
    Iterable<Interceptor> interceptors = const <Interceptor>[],
  }) {
    final owner = DioOwner.create(
      options: BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
      ),
      interceptors: interceptors,
    );
    return ${type}DioModule._(owner, DefaultDioJsonClient(owner.dio));
  }

  final DioOwner owner;
  final DioJsonClient client;

  CancelToken cancellation(CancellationSignal signal) =>
      bindCancelToken(signal);

  @override
  void dispose() => owner.dispose();
}
''';
  }

  static String _renderWorkmanager(String name) {
    final type = _pascal(name);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.

import 'package:dartitect_workmanager/dartitect_workmanager.dart';

/// Versioned headless envelope factory for the $type feature.
abstract final class ${type}WorkmanagerJob {
  static DartitectWorkmanagerEnvelope create({
    required String jobId,
    required DateTime deadline,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => DartitectWorkmanagerEnvelope(
    jobId: jobId,
    definition: '$name',
    deadline: deadline,
    payload: payload,
  );
}
''';
  }

  static int _stableUid(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String _pascal(String value) => value
      .split('_')
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join();

  static String _renderStringList(Iterable<String> values) {
    final materialized = values.toList(growable: false);
    if (materialized.isEmpty) return '<String>[]';
    return "<String>[\n${materialized.map((value) => "    '$value',").join('\n')}\n  ]";
  }

  static String _formatDart(String source, String uri) => DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    pageWidth: 80,
  ).format(source, uri: uri);

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

final class _AssemblySlot {
  const _AssemblySlot(this.typeName, this.fieldName);

  final String typeName;
  final String fieldName;
}
