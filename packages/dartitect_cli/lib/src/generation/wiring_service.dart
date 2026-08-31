import 'dart:convert';
import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:dartitect/dartitect.dart' show FeatureProfile;

import '../config/dartitect_config.dart';
import '../contracts/openapi_contract_service.dart';
import '../contracts/openapi_graph_compiler.dart';
import '../extensions/local_extension_compiler.dart';
import '../factories/semantic_factory_compiler.dart';
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

/// Converges concrete application/session/feature graphs from strict config v3.
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
    final contracts = await DartitectOpenApiGraphCompiler(root)
        .compile(resolved);
    final extensions = await DartitectLocalExtensionCompiler(root)
        .compile(resolved.extensionSources);
    final factories = await DartitectSemanticFactoryCompiler(root)
        .compile(resolved);
    final plan = await GenerationEngine(root, namespace: _namespace).plan(
      _operations(resolved, extensions, factories, contracts),
      manageFullyGenerated: true,
    );
    return DartitectWiringReport(plan: plan, applied: false, writes: 0);
  }

  /// Previews wiring against generated-once seams in an isolated project copy.
  ///
  /// This is the first phase of feature creation: consumer-owned factory seams
  /// are materialized only in [Directory.systemTemp], analyzed with [config],
  /// and removed before this method completes. The real project remains
  /// read-only until its reviewed plan is applied.
  Future<DartitectWiringReport> inspectStagedFeature({
    required DartitectConfig config,
    required List<FileGenerationOperation> seams,
  }) async {
    final staging = await Directory.systemTemp.createTemp(
      'dartitect-feature-stage-',
    );
    try {
      await _copyForFeatureStaging(root, staging);
      await GenerationEngine(
        staging,
        namespace: GenerationNamespace.scaffolding,
      ).apply(seams);
      await File(_join(staging.path, 'dartitect.json'))
          .writeAsString(config.encode(), flush: true);
      await _stagePackageConfig(root, staging);
      return await DartitectWiringService(staging).inspect(config: config);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Recovers and atomically converges the complete managed namespace.
  Future<DartitectWiringReport> apply({DartitectConfig? config}) async {
    final resolved = config ?? await _loadConfig();
    final contracts = await DartitectOpenApiGraphCompiler(root)
        .compile(resolved);
    final extensions = await DartitectLocalExtensionCompiler(root)
        .compile(resolved.extensionSources);
    final factories = await DartitectSemanticFactoryCompiler(root)
        .compile(resolved);
    final result = await GenerationEngine(root, namespace: _namespace).apply(
      _operations(resolved, extensions, factories, contracts),
      manageFullyGenerated: true,
    );
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

  static Future<void> _copyForFeatureStaging(
    Directory source,
    Directory destination,
  ) async {
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (name == '.git' || name == '.dart_tool' || name == 'build') continue;
      final target = _join(destination.path, name);
      if (entity is Directory) {
        final child = Directory(target);
        await child.create(recursive: true);
        await _copyForFeatureStaging(entity, child);
      } else if (entity is File) {
        await entity.copy(target);
      } else if (entity is Link) {
        await Link(target).create(await entity.target(), recursive: true);
      }
    }
  }

  static Future<void> _stagePackageConfig(
    Directory source,
    Directory staging,
  ) async {
    final original = File(_join(source.path, '.dart_tool/package_config.json'));
    if (!await original.exists()) return;
    final decoded = jsonDecode(await original.readAsString());
    if (decoded is! Map<String, Object?> || decoded['packages'] is! List) {
      throw const GenerationException(
        '.dart_tool/package_config.json is not a valid package config.',
      );
    }
    final packages = decoded['packages']! as List<Object?>;
    for (final item in packages) {
      if (item is! Map<String, Object?> || item['rootUri'] is! String) continue;
      final resolved = original.uri.resolve(item['rootUri']! as String);
      final resolvedPath = File.fromUri(resolved).absolute.path;
      if (_isWithinDirectory(resolvedPath, source.absolute.path)) {
        final suffix = resolvedPath.substring(source.absolute.path.length);
        item['rootUri'] = Directory('${staging.absolute.path}$suffix').uri
            .toString();
      } else {
        item['rootUri'] = resolved.toString();
      }
    }
    final staged = File(_join(staging.path, '.dart_tool/package_config.json'));
    await staged.parent.create(recursive: true);
    await staged.writeAsString(jsonEncode(decoded), flush: true);
  }

  static bool _isWithinDirectory(String candidate, String parent) {
    final normalizedCandidate = candidate.endsWith(Platform.pathSeparator)
        ? candidate.substring(0, candidate.length - 1)
        : candidate;
    final normalizedParent = parent.endsWith(Platform.pathSeparator)
        ? parent.substring(0, parent.length - 1)
        : parent;
    final comparableCandidate = Platform.isWindows
        ? normalizedCandidate.toLowerCase()
        : normalizedCandidate;
    final comparableParent = Platform.isWindows
        ? normalizedParent.toLowerCase()
        : normalizedParent;
    return comparableCandidate == comparableParent ||
        comparableCandidate.startsWith(
          '$comparableParent${Platform.pathSeparator}',
        );
  }

  static List<FileGenerationOperation> _operations(
    DartitectConfig config,
    List<DartitectLocalExtensionIr> extensions,
    List<DartitectSemanticFactoryIr> factories,
    Map<String, OpenApiContractReport> contracts,
  ) {
    final entries = config.features.declarations.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <FileGenerationOperation>[
      ..._applicationOperations(config, extensions, factories),
      ..._storageContextOperations(config),
      for (final entry in entries) ...<FileGenerationOperation>[
        FileGenerationOperation(
          relativePath:
              'lib/features/${entry.key}/composition/'
              '${entry.key}.wiring.dartitect.g.dart',
          content: _formatDart(
            _render(
              entry.key,
              entry.value,
              config,
              _factory(
                factories,
                DartitectSemanticFactoryRole.feature,
                entry.key,
              ),
              factories,
              contracts,
            ),
            '${entry.key}.wiring.dartitect.g.dart',
          ),
          rendererId: 'wiring.feature',
          ownership: GeneratedOwnership.fullyGenerated,
          sourcePath: 'dartitect.json',
          rendererVersion: 3,
          semanticSchemaVersion: 1,
          inputSignature: jsonEncode(<String, Object?>{
            'name': entry.key,
            'scheduler': config.scheduler.toJson(),
            'declaration': entry.value.toJson(),
          }),
        ),
        FileGenerationOperation(
          relativePath:
              'test/support/${entry.key}_feature_harness.wiring.dartitect.g.dart',
          content: _formatDart(
            _renderFeatureHarness(entry.key, entry.value),
            '${entry.key}_feature_harness.wiring.dartitect.g.dart',
          ),
          rendererId: 'wiring.feature-harness',
          ownership: GeneratedOwnership.fullyGenerated,
          sourcePath: 'dartitect.json',
          rendererVersion: 1,
          semanticSchemaVersion: 1,
          inputSignature: jsonEncode(<String, Object?>{
            'name': entry.key,
            'profile': entry.value.profile.wireName,
            'capabilities': entry.value.capabilities
                .map((capability) => capability.wireName)
                .toList(),
          }),
        ),
        if (entry.value.transport case final String transportName
            when config.transports[transportName]?.provider == 'dio')
          _managedOperation(
            entry.key,
            entry.value,
            'wiring.dio',
            'infrastructure/${entry.key}_dio.wiring.dartitect.g.dart',
            _renderDio(entry.key),
          ),
        if (config.scheduler.provider == 'workmanager' &&
            entry.value.headlessTargets.isNotEmpty)
          _managedOperation(
            entry.key,
            entry.value,
            'wiring.workmanager',
            'composition/${entry.key}_workmanager.wiring.dartitect.g.dart',
            _renderWorkmanager(entry.key),
          ),
      ],
    ];
  }

  static List<FileGenerationOperation> _storageContextOperations(
    DartitectConfig config,
  ) {
    final contexts = config.storageContexts.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <FileGenerationOperation>[
      for (final context in contexts)
        if (context.value.provider == 'drift' ||
            context.value.provider == 'objectbox')
          _managedStorageOperation(
            context.key,
            context.value,
            _datasetsForContext(config, context.key),
          ),
    ];
  }

  static List<MapEntry<String, DartitectStorageDatasetConfig>>
  _datasetsForContext(DartitectConfig config, String context) {
    final registrations = <MapEntry<String, DartitectStorageDatasetConfig>>[
      for (final feature in config.features.declarations.entries)
        if (feature.value.storageContext == context)
          MapEntry(feature.key, feature.value.dataset!),
    ];
    registrations.sort((left, right) => left.key.compareTo(right.key));
    return registrations;
  }

  static FileGenerationOperation _managedStorageOperation(
    String name,
    DartitectStorageContextConfig context,
    List<MapEntry<String, DartitectStorageDatasetConfig>> datasets,
  ) {
    final provider = context.provider;
    final suffix = '${name}_$provider.wiring.dartitect.g.dart';
    return FileGenerationOperation(
      relativePath: 'lib/infrastructure/storage/$suffix',
      content: _formatDart(
        provider == 'drift'
            ? _renderDrift(name, datasets)
            : _renderObjectBox(name, datasets),
        suffix,
      ),
      rendererId: 'wiring.storage',
      ownership: GeneratedOwnership.fullyGenerated,
      sourcePath: 'dartitect.json',
      rendererVersion: 4,
      semanticSchemaVersion: 2,
      inputSignature: jsonEncode(<String, Object?>{
        'context': name,
        'storage': context.toJson(),
        'datasets': <Object?>[
          for (final dataset in datasets)
            <String, Object?>{
              'feature': dataset.key,
              ...dataset.value.toJson(),
            },
        ],
      }),
    );
  }

  static List<FileGenerationOperation> _applicationOperations(
    DartitectConfig config,
    List<DartitectLocalExtensionIr> extensions,
    List<DartitectSemanticFactoryIr> factories,
  ) {
    final observabilityProvider = config.observability.provider;
    final signature = jsonEncode(<String, Object?>{
      'scheduler': config.scheduler.toJson(),
      'observability': observabilityProvider,
      'extensions': extensions.map((extension) => extension.toJson()).toList(),
      'factories': factories.map((factory) => factory.toJson()).toList(),
    });
    return <FileGenerationOperation>[
      FileGenerationOperation(
        relativePath:
            'lib/composition/application_module.wiring.dartitect.g.dart',
        content: _formatDart(
          _renderApplicationModule(
            config: config,
            extensions: extensions,
            factories: factories,
          ),
          'application_module.wiring.dartitect.g.dart',
        ),
        rendererId: 'wiring.application',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'dartitect.json',
        rendererVersion: 3,
        semanticSchemaVersion: 2,
        inputSignature: signature,
      ),
      FileGenerationOperation(
        relativePath: 'lib/composition/session_module.wiring.dartitect.g.dart',
        content: _formatDart(
          _renderSessionModule(config, factories),
          'session_module.wiring.dartitect.g.dart',
        ),
        rendererId: 'wiring.session',
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: 'dartitect.json',
        rendererVersion: 3,
        semanticSchemaVersion: 2,
        inputSignature: signature,
      ),
    ];
  }

  static FileGenerationOperation _managedOperation(
    String name,
    DartitectFeatureDeclaration declaration,
    String rendererId,
    String suffix,
    String content,
  ) => FileGenerationOperation(
    relativePath: 'lib/features/$name/$suffix',
    content: _formatDart(content, suffix),
    rendererId: rendererId,
    ownership: GeneratedOwnership.fullyGenerated,
    sourcePath: 'dartitect.json',
    rendererVersion: 3,
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
    DartitectConfig config,
    DartitectSemanticFactoryIr factory,
    List<DartitectSemanticFactoryIr> factories,
    Map<String, OpenApiContractReport> contractReports,
  ) {
    final type = _pascal(name);
    final parentType = declaration.scope == FeatureScope.application
        ? 'ApplicationGraph'
        : 'SessionGraph';
    final parentImport = declaration.scope == FeatureScope.application
        ? '../../../composition/application_module.wiring.dartitect.g.dart'
        : '../../../composition/session_module.wiring.dartitect.g.dart';
    final imports = <String>{
      factory.libraryUri,
      for (final method in factory.methods.values) ...method.libraryUris,
    };
    final contractImportAliases = <String, String>{};
    final infrastructure = <_AvailableValue>[];
    DartitectSemanticFactoryIr? transportFactory;
    if (declaration.storageContext case final context?) {
      final contextFactory = _factory(
        factories,
        DartitectSemanticFactoryRole.storage,
        context,
      );
      imports
        ..add(contextFactory.libraryUri)
        ..addAll(contextFactory.methods['open']!.libraryUris);
      infrastructure.add(
        _AvailableValue(
          name: _fieldName(context),
          type: contextFactory.methods['open']!.valueType,
          expression: 'graph.${_fieldName(context)}',
        ),
      );
    }
    if (declaration.transport case final context?) {
      final contextFactory = _factory(
        factories,
        DartitectSemanticFactoryRole.transport,
        context,
      );
      transportFactory = contextFactory;
      imports
        ..add(contextFactory.libraryUri)
        ..addAll(contextFactory.methods['open']!.libraryUris);
      infrastructure.add(
        _AvailableValue(
          name: _fieldName(context),
          type: contextFactory.methods['open']!.valueType,
          expression: 'graph.${_fieldName(context)}',
        ),
      );
    }
    final available = <_AvailableValue>[
      for (final value in infrastructure)
        _AvailableValue(
          name: value.name,
          type: value.type,
          expression: 'infrastructure.${value.name}',
        ),
    ];
    final creation = <String>[];
    final runtimeValues = <_AvailableValue>[];
    for (final selection in declaration.operations) {
      final contract = config.contracts[selection.contract]!;
      final report = contractReports[selection.contract]!;
      final operationType = report.operationTypes[selection.operationId]!;
      final prefix = 'contract_${selection.contract}';
      final outputFromLib = contract.output.substring('lib/'.length);
      contractImportAliases['../../../$outputFromLib'] = prefix;
      final clientMethod = transportFactory!.methods['client']!;
      final field = _fieldName(
        '${selection.contract}_${_safeIdentifier(selection.operationId)}',
      );
      final renderedType = '$prefix.$operationType';
      creation.add(
        '    final $field = $renderedType('
        '${_invoke('${transportFactory.declarationType}()', clientMethod, available)}'
        ');',
      );
      final value = _AvailableValue(
        name: field,
        type: renderedType,
        matchType: operationType,
        expression: field,
      );
      available.add(value);
      runtimeValues.add(value);
    }
    for (final methodName in const <String>[
      'createLocalPort',
      'createRemotePort',
      'createMapper',
      'createOutboxStore',
      'createIdempotencyPolicy',
      'createConflictPolicy',
      'createDataset',
      'createCheckpointStore',
      'createLocalAuthority',
    ]) {
      final method = factory.methods[methodName];
      if (method == null) continue;
      final field = _factoryField(methodName);
      creation.add(
        _renderFactoryValue(
          field,
          method,
          _invoke('factory', method, available),
          label: 'feature.$name.$field',
        ),
      );
      final value = _AvailableValue(
        name: field,
        type: method.valueType,
        expression: field,
      );
      available.add(value);
      runtimeValues.add(value);
    }
    if (declaration.localAuthority ==
        FeatureLocalAuthorityStrategy.generatedPull) {
      final watch = factory.methods['watch']!;
      final read = factory.methods['read']!;
      final resultTypes = _resultTypes(read.valueType);
      imports.add('package:dartitect_flutter/dartitect_flutter_reactive.dart');
      final localAuthority = _AvailableValue(
        name: 'localAuthority',
        type: 'PullReactiveSource<${resultTypes.$1}, ${resultTypes.$2}>',
        expression: 'localAuthority',
      );
      creation.add(
        '''    final localAuthority = PullReactiveSource<${resultTypes.$1}, ${resultTypes.$2}>(
      triggers: <PullInvalidationTrigger>[
        () => ${_invoke('factory', watch, available)},
      ],
      pull: (cancellation) => ${_invoke('factory', read, <_AvailableValue>[...available, const _AvailableValue(name: 'cancellation', type: 'CancellationSignal', expression: 'cancellation')])},
    );''',
      );
      available.add(localAuthority);
      runtimeValues.add(localAuthority);
    }
    if (factory.methods['createDataset'] case final datasetMethod?) {
      final datasetTypes = _typeArguments(
        datasetMethod.valueType,
        'SyncDataset',
        3,
      );
      final syncEngine = _AvailableValue(
        name: 'syncEngine',
        type:
            'SyncEngine<${datasetTypes[0]}, ${datasetTypes[1]}, ${datasetTypes[2]}>',
        expression: 'syncEngine',
      );
      creation.add('''    final syncEngine =
        transaction.own<${syncEngine.type}>(
          ${syncEngine.type}(
            datasets: <${datasetMethod.valueType}>[dataset],
            graph: SyncDependencyGraph<${datasetTypes[0]}>(
              keys: <${datasetTypes[0]}>[dataset.key],
            ),
            checkpoints: checkpointStore,
          ),
          (value) => value.disposeAsync(),
          label: 'feature.$name.sync',
        );''');
      available.add(syncEngine);
      runtimeValues.add(syncEngine);
    }
    if (factory.methods['createOutboxStore'] case final outboxMethod?) {
      final outboxTypes = _typeArguments(
        outboxMethod.valueType,
        'MutationOutboxStore',
        3,
      );
      final idempotencyMethod = factory.methods['createIdempotencyPolicy']!;
      final idempotencyTypes = _typeArguments(
        idempotencyMethod.valueType,
        'MutationIdempotencyPolicy',
        2,
      );
      if (idempotencyTypes[0] != outboxTypes[0] ||
          idempotencyTypes[1] != outboxTypes[1]) {
        throw const DartitectConfigException(
          '/factorySource',
          'idempotency policy types must match createOutboxStore()',
        );
      }
      final synchronize = factory.methods['synchronizeMutation']!;
      final synchronizedTypes = _resultTypes(synchronize.valueType);
      if (synchronizedTypes.$2 != outboxTypes[2]) {
        throw const DartitectConfigException(
          '/factorySource',
          'synchronizeMutation() failure must match createOutboxStore()',
        );
      }
      final commandType =
          'MutationCommand<${outboxTypes[1]}, ${outboxTypes[0]}, '
          '${synchronizedTypes.$1}, ${outboxTypes[2]}>';
      final operationType =
          'OutboxOperation<${outboxTypes[0]}, ${outboxTypes[1]}>';
      final synchronizeInvocation = _invoke(
        'factory',
        synchronize,
        <_AvailableValue>[
          ...available,
          _AvailableValue(
            name: 'operation',
            type: operationType,
            expression: 'operation',
          ),
          const _AvailableValue(
            name: 'cancellation',
            type: 'CancellationSignal',
            expression: 'cancellation',
          ),
        ],
      );
      final classify = factory.methods['classifyMutationFailure']!;
      final classifyInvocation = _invoke('factory', classify, <_AvailableValue>[
        ...available,
        _AvailableValue(
          name: 'failure',
          type: outboxTypes[2],
          expression: 'failure',
        ),
      ]);
      final mutationCommand = _AvailableValue(
        name: 'mutationCommand',
        type: commandType,
        expression: 'mutationCommand',
      );
      creation.add('''    final mutationCommand = transaction.own<$commandType>(
      $commandType(
        store: outboxStore,
        synchronize: (operation, cancellation) => $synchronizeInvocation,
        createIdempotencyKey: (key, argument) =>
            idempotencyPolicy.create(key, argument),
        classifyFailure: (failure) => $classifyInvocation,
      ),
      (value) => value.disposeAsync(),
      label: 'feature.$name.mutations',
    );''');
      available.add(mutationCommand);
      runtimeValues.add(mutationCommand);
    }
    final repositoryMethod = factory.methods['createRepository']!;
    creation.add(
      _renderFactoryValue(
        'repository',
        repositoryMethod,
        _invoke('factory', repositoryMethod, available),
        label: 'feature.$name.repository',
      ),
    );
    final repository = _AvailableValue(
      name: 'repository',
      type: repositoryMethod.valueType,
      expression: 'repository',
    );
    available.add(repository);
    runtimeValues.insert(0, repository);
    final viewModelMethod = factory.methods['createViewModel']!;
    final viewModelType = viewModelMethod.valueType;
    final viewModelInvocation = _invoke(
      'factory',
      viewModelMethod,
      <_AvailableValue>[
        ...available,
        _AvailableValue(
          name: 'runtime',
          type: '${type}Runtime',
          expression: 'this',
        ),
      ],
    );
    final infrastructureFields = infrastructure
        .map((value) => '    required this.${value.name},')
        .join('\n');
    final infrastructureDeclarations = infrastructure
        .map((value) => '  final ${value.type} ${value.name};')
        .join('\n');
    final infrastructureArguments = infrastructure
        .map((value) => '      ${value.name}: ${value.expression},')
        .join('\n');
    final infrastructureConstructor = infrastructure.isEmpty
        ? '  const ${type}Infrastructure();'
        : '''  const ${type}Infrastructure({
$infrastructureFields
  });''';
    final runtimeParameters = runtimeValues
        .map((value) => '    required this.${value.name},')
        .join('\n');
    final runtimeFields = runtimeValues
        .map((value) => '  final ${value.type} ${value.name};')
        .join('\n');
    final runtimeArguments = runtimeValues
        .map((value) => '      ${value.name}: ${value.expression},')
        .join('\n');
    imports
      ..remove('package:dartitect/dartitect.dart')
      ..remove('package:dartitect_flutter/dartitect_flutter.dart');
    final renderedImports = imports.toList()..sort();
    final importSource = renderedImports
        .map((uri) => "import '$uri';")
        .join('\n');
    final contractImportSource = contractImportAliases.entries
        .map((entry) => "import '${entry.key}' as ${entry.value};")
        .join('\n');
    final storageFact = declaration.storageContext == null
        ? ''
        : "  static const String storageContext = '${declaration.storageContext}';\n";
    final transportFact = declaration.transport == null
        ? ''
        : "  static const String transport = '${declaration.transport}';\n";
    final schedulerFact = declaration.headlessTargets.isEmpty
        ? ''
        : "  static const String scheduler = '${config.scheduler.provider}';\n";
    final headless = _renderStringList(
      declaration.headlessTargets.map((target) => target.wireName),
    );
    final targets = _renderStringList(
      declaration.targets.map((target) => target.wireName),
    );
    final capabilities = _renderStringList(
      declaration.capabilities.map((capability) => capability.wireName),
    );
    final openApiOperations = _renderStringList(
      declaration.operations.map(
        (operation) => '${operation.contract}:${operation.operationId}',
      ),
    );
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

import '$parentImport';
$contractImportSource
$importSource

/// Exact contexts selected by the $type feature profile.
final class ${type}Infrastructure {
$infrastructureConstructor

$infrastructureDeclarations
}

/// Concrete feature runtime with no public generic capability slots.
final class ${type}Runtime {
  const ${type}Runtime({
    required this.factory,
    required this.infrastructure,
$runtimeParameters
  });

  final ${factory.declarationType} factory;
  final ${type}Infrastructure infrastructure;
$runtimeFields

  /// Creates consumer-owned presentation state from the typed runtime.
  $viewModelType createViewModel() => $viewModelInvocation;

  /// Constructs the exact profile closure inside the host transaction.
  static Future<${type}Runtime> create(
    $parentType graph,
    ${factory.declarationType} factory,
    ResourceTransaction transaction,
  ) async {
    final infrastructure = ${type}Infrastructure(
$infrastructureArguments
    );
${creation.join('\n')}
    return ${type}Runtime(
      factory: factory,
      infrastructure: infrastructure,
$runtimeArguments
    );
  }
}

/// Material-neutral generated owner for the $type feature.
final class ${type}FeatureHost extends StatelessWidget {
  const ${type}FeatureHost({
    required this.graph,
    required this.factory,
    required this.loading,
    required this.failure,
    required this.ready,
    this.start,
    this.onDisposed,
    super.key,
  });

  final $parentType graph;
  final ${factory.declarationType} factory;
  final WidgetBuilder loading;
  final FeatureFailureBuilder failure;
  final FeatureReadyBuilder<${type}Runtime, $viewModelType> ready;
  final FeatureViewModelStarter<$viewModelType>? start;
  final FutureOr<void> Function()? onDisposed;

  @override
  Widget build(BuildContext context) =>
      FeatureHost<$parentType, ${type}Runtime, $viewModelType>(
        parent: graph,
        generationKey: factory,
        createGraph: (parent, transaction) =>
            ${type}Runtime.create(parent, factory, transaction),
        createViewModel: (runtime) => runtime.createViewModel(),
        start: start,
        onDisposed: onDisposed,
        loading: loading,
        failure: failure,
        ready: ready,
      );
}

/// Closed generated facts used by composition and capability reporting.
abstract final class ${type}FeatureWiring {
  static const String profile = '${declaration.profile.wireName}';
  static const String scope = '${declaration.scope.wireName}';
$storageFact$transportFact  static const List<String> targets = $targets;
  static const String pagination = '${declaration.pagination.wireName}';
  static const String diagnostics = '${declaration.diagnostics.wireName}';
$schedulerFact  static const List<String> headlessTargets = $headless;
  static const List<String> capabilities = $capabilities;
  static const List<String> openApiOperations = $openApiOperations;

}
''';
  }

  static String _renderFeatureHarness(
    String name,
    DartitectFeatureDeclaration declaration,
  ) {
    final type = _pascal(name);
    final constructor = switch (declaration.profile) {
      FeatureProfile.local => 'local',
      FeatureProfile.online => 'online',
      FeatureProfile.cache => 'cache',
      FeatureProfile.replica => 'replica',
      FeatureProfile.offlineFull => 'offlineFull',
    };
    final capabilities = _renderStringList(
      declaration.capabilities.map((capability) => capability.wireName),
    );
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect_testing/dartitect_testing.dart';

/// Fully managed contract harness selected from the $type feature profile.
final class ${type}FeatureHarness<T extends OnlineFeatureContractDriver> {
  const ${type}FeatureHarness({required this.fixtures});

  /// Consumer fixtures and domain assertions; infrastructure is matrix-owned.
  final FeatureContractFixtures<T> fixtures;

  /// Declared stable capability closure.
  static const List<String> capabilities = $capabilities;

  /// Exact profile matrix for this generated feature.
  FeatureContractMatrix<T> get matrix =>
      FeatureContractMatrix<T>.$constructor(fixtures: fixtures);

  /// Executes every required row with a fresh graph and zero-residual census.
  Future<List<FeatureContractResult>> run() => matrix.run();
}
''';
  }

  static String _renderApplicationModule({
    required DartitectConfig config,
    required List<DartitectLocalExtensionIr> extensions,
    required List<DartitectSemanticFactoryIr> factories,
  }) {
    final scheduler = config.scheduler.provider;
    final observability = config.observability.provider;
    final constructorParameters = <String>[];
    final fields = <String>[];
    final createParameters = <String>[];
    final construction = <String>[];
    final arguments = <String>[];
    final imports = <String>{
      for (final extension in extensions) extension.libraryUri,
      for (final extension in extensions) ...extension.bindingLibraryUris,
    };

    for (final entry in config.storageContexts.entries) {
      if (entry.value.scope != FeatureScope.application) continue;
      _addApplicationContext(
        entry.key,
        _factory(factories, DartitectSemanticFactoryRole.storage, entry.key),
        constructorParameters,
        fields,
        construction,
        arguments,
        imports,
      );
    }
    for (final entry in config.transports.entries) {
      if (entry.value.scope != FeatureScope.application) continue;
      _addApplicationContext(
        entry.key,
        _factory(factories, DartitectSemanticFactoryRole.transport, entry.key),
        constructorParameters,
        fields,
        construction,
        arguments,
        imports,
      );
    }
    if (config.session != null) {
      constructorParameters.add('    required this.sessions,');
      fields.add(
        '  final SessionRuntimeController<SessionGraph, '
        'DartitectSessionDescription> sessions;',
      );
      construction.add('''          final sessions = transaction.own(
            SessionRuntimeController<SessionGraph, DartitectSessionDescription>(),
            (controller) => controller.disposeAsync(),
            label: 'application.sessions',
          );''');
      arguments.add('            sessions: sessions,');
      imports.add('package:dartitect_flutter/dartitect_flutter.dart');
    }

    if (scheduler == 'workmanager') {
      imports.add('package:dartitect_workmanager/dartitect_workmanager.dart');
      constructorParameters.add('    required this.scheduler,');
      fields.add('  final DartitectWorkmanagerScheduler scheduler;');
      construction.add(
        '          final scheduler = DartitectWorkmanagerScheduler();',
      );
      arguments.add('            scheduler: scheduler,');
    } else if (scheduler != 'none') {
      throw DartitectConfigException(
        '/scheduler/provider',
        'custom schedulers require a typed local extension in config v3',
      );
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
      throw DartitectConfigException(
        '/observability/provider',
        'custom observability requires a typed local extension in config v3',
      );
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
    final createSignature = createParameters.isEmpty
        ? '()'
        : '({\n${createParameters.join('\n')}\n  })';
    final asyncImport = createParameters.isEmpty
        ? ''
        : "import 'dart:async';\n\n";
    final applicationConstructor = constructorParameters.isEmpty
        ? '  const ApplicationGraph();'
        : '''  const ApplicationGraph({
${constructorParameters.join('\n')}
  });''';
    final flutterImport = config.session == null
        ? ''
        : "import 'package:dartitect_flutter/dartitect_flutter.dart';\n";
    final sessionImport = config.session == null
        ? ''
        : "import 'session_module.wiring.dartitect.g.dart';\n";
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

$asyncImport
import 'package:dartitect/dartitect.dart';
$flutterImport$sessionImport
${extensionImports.isEmpty ? '' : extensionImports}

/// Directly constructed application graph; it is not a service locator.
final class ApplicationGraph {
$applicationConstructor

${fields.join('\n')}
}

/// Tooling-materialized application composition module.
abstract final class ApplicationModule {
  static BootstrapCoordinator<ApplicationGraph>
  create$createSignature =>
      BootstrapCoordinator<ApplicationGraph>(
        stages: const <BootstrapStage>[],
        buildRoot: (transaction, _) async {
${construction.join('\n')}
          return ApplicationGraph(
${arguments.join('\n')}
          );
        },
      );
}
''';
  }

  static String _renderSessionModule(
    DartitectConfig config,
    List<DartitectSemanticFactoryIr> factories,
  ) {
    final imports = <String>{};
    final parameters = <String>['    required this.application,'];
    final fields = <String>['  final ApplicationGraph application;'];
    final construction = <String>[];
    final arguments = <String>['      application: application,'];
    final available = <_AvailableValue>[];
    for (final entry in config.storageContexts.entries) {
      final ir = _factory(
        factories,
        DartitectSemanticFactoryRole.storage,
        entry.key,
      );
      final type = ir.methods['open']!.valueType;
      imports
        ..add(ir.libraryUri)
        ..addAll(ir.methods['open']!.libraryUris);
      if (entry.value.scope == FeatureScope.application) {
        final field = _fieldName(entry.key);
        fields.add('  $type get $field => application.$field;');
        available.add(
          _AvailableValue(
            name: field,
            type: type,
            expression: 'application.$field',
          ),
        );
      } else {
        _addSessionContext(
          entry.key,
          ir,
          parameters,
          fields,
          construction,
          arguments,
          available,
          imports,
        );
      }
    }
    for (final entry in config.transports.entries) {
      final ir = _factory(
        factories,
        DartitectSemanticFactoryRole.transport,
        entry.key,
      );
      final type = ir.methods['open']!.valueType;
      imports
        ..add(ir.libraryUri)
        ..addAll(ir.methods['open']!.libraryUris);
      if (entry.value.scope == FeatureScope.application) {
        final field = _fieldName(entry.key);
        fields.add('  $type get $field => application.$field;');
        available.add(
          _AvailableValue(
            name: field,
            type: type,
            expression: 'application.$field',
          ),
        );
      } else {
        _addSessionContext(
          entry.key,
          ir,
          parameters,
          fields,
          construction,
          arguments,
          available,
          imports,
        );
      }
    }
    if (config.session case final session?) {
      final sessionFactory = _factory(
        factories,
        DartitectSemanticFactoryRole.session,
        'session',
      );
      imports
        ..add(sessionFactory.libraryUri)
        ..addAll(sessionFactory.methods['create']!.libraryUris);
      final create = sessionFactory.methods['create']!;
      construction.add(
        '    final session = '
        '${_awaitIfAsync(create, _invoke('sessionFactory', create, available))};',
      );
      parameters.add('    required this.session,');
      fields.add('  final ${create.valueType} session;');
      arguments.add('      session: session,');
      construction.insert(
        0,
        '    final sessionFactory = ${session.factorySource.declaration}();',
      );
    }
    final renderedImports = imports.toList()..sort();
    final importSource = renderedImports
        .map((uri) => "import '$uri';")
        .join('\n');
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect/dartitect.dart';

import 'application_module.wiring.dartitect.g.dart';
$importSource

/// Opaque replayable description; authentication payload remains app-owned.
final class DartitectSessionDescription {
  const DartitectSessionDescription(this.generation);
  final String generation;
}

/// Concrete authenticated-session graph.
final class SessionGraph {
  const SessionGraph({
${parameters.join('\n')}
  });

${fields.join('\n')}
}

/// Opens one fresh session graph per authenticated generation.
abstract final class SessionModule {
  static Future<SessionGraph> create(
    ApplicationGraph application,
    ResourceTransaction transaction,
  ) async {
${construction.join('\n')}
    return SessionGraph(
${arguments.join('\n')}
    );
  }
}
''';
  }

  static DartitectSemanticFactoryIr _factory(
    List<DartitectSemanticFactoryIr> factories,
    DartitectSemanticFactoryRole role,
    String name,
  ) {
    final matches = factories.where(
      (factory) => factory.role == role && factory.bindingName == name,
    );
    if (matches.length != 1) {
      throw DartitectConfigException(
        '/factorySource',
        'expected exactly one compiled ${role.name} factory for $name',
      );
    }
    return matches.single;
  }

  static void _addApplicationContext(
    String name,
    DartitectSemanticFactoryIr factory,
    List<String> constructorParameters,
    List<String> fields,
    List<String> construction,
    List<String> arguments,
    Set<String> imports,
  ) {
    final open = factory.methods['open']!;
    final field = _fieldName(name);
    final factoryVariable = '${field}Factory';
    imports
      ..add(factory.libraryUri)
      ..addAll(open.libraryUris)
      ..addAll(factory.methods['dispose']!.libraryUris);
    constructorParameters.add('    required this.$field,');
    fields.add('  final ${open.valueType} $field;');
    construction.add(
      '''          final $factoryVariable = ${factory.declarationType}();
          final $field = transaction.own<${open.valueType}>(
            ${_awaitIfAsync(open, '$factoryVariable.open()')},
            $factoryVariable.dispose,
            label: 'application.$name',
          );''',
    );
    arguments.add('            $field: $field,');
  }

  static void _addSessionContext(
    String name,
    DartitectSemanticFactoryIr factory,
    List<String> parameters,
    List<String> fields,
    List<String> construction,
    List<String> arguments,
    List<_AvailableValue> available,
    Set<String> imports,
  ) {
    final open = factory.methods['open']!;
    final field = _fieldName(name);
    final factoryVariable = '${field}Factory';
    imports
      ..add(factory.libraryUri)
      ..addAll(open.libraryUris)
      ..addAll(factory.methods['dispose']!.libraryUris);
    parameters.add('    required this.$field,');
    fields.add('  final ${open.valueType} $field;');
    construction.add(
      '''    final $factoryVariable = ${factory.declarationType}();
    final $field = transaction.own<${open.valueType}>(
      ${_awaitIfAsync(open, '$factoryVariable.open()')},
      $factoryVariable.dispose,
      label: 'session.$name',
    );''',
    );
    arguments.add('      $field: $field,');
    available.add(
      _AvailableValue(name: field, type: open.valueType, expression: field),
    );
  }

  static String _invoke(
    String target,
    DartitectFactoryMethodIr method,
    List<_AvailableValue> available,
  ) {
    final arguments = <String>[];
    for (final parameter in method.parameters) {
      final byName = available.where(
        (value) =>
            value.matchType == parameter.type && value.name == parameter.name,
      );
      final byType = available.where(
        (value) => value.matchType == parameter.type,
      );
      final matches = byName.isNotEmpty ? byName : byType;
      if (matches.length != 1) {
        throw DartitectConfigException(
          '/factorySource',
          '${method.name} parameter ${parameter.name} (${parameter.type}) '
              'must resolve to exactly one selected graph value',
        );
      }
      final expression = matches.single.expression;
      arguments.add(
        parameter.named ? '${parameter.name}: $expression' : expression,
      );
    }
    return '$target.${method.name}(${arguments.join(', ')})';
  }

  static String _renderFactoryValue(
    String field,
    DartitectFactoryMethodIr method,
    String invocation, {
    required String label,
  }) => switch (method.disposalKind) {
    DartitectFactoryDisposalKind.none =>
      '    final $field = ${_awaitIfAsync(method, invocation)};',
    DartitectFactoryDisposalKind.synchronous =>
      '''    final $field =
        transaction.own<${method.valueType}>(
          ${_awaitIfAsync(method, invocation)},
          (value) => value.dispose(),
          label: '$label',
        );''',
    DartitectFactoryDisposalKind.asynchronous =>
      '''    final $field =
        transaction.own<${method.valueType}>(
          ${_awaitIfAsync(method, invocation)},
          (value) => value.disposeAsync(),
          label: '$label',
        );''',
  };

  static String _awaitIfAsync(
    DartitectFactoryMethodIr method,
    String invocation,
  ) =>
      method.returnType.startsWith('Future<') ||
          method.returnType.startsWith('FutureOr<')
      ? 'await $invocation'
      : invocation;

  static String _fieldName(String value) {
    final parts = value.split('_').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'value';
    return parts.first +
        parts
            .skip(1)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join();
  }

  static String _safeIdentifier(String value) {
    final normalized = value.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    return RegExp(r'^[A-Za-z_]').hasMatch(normalized)
        ? normalized
        : 'operation_$normalized';
  }

  static String _factoryField(String method) {
    final stem = method.startsWith('create')
        ? method.substring('create'.length)
        : method;
    return stem[0].toLowerCase() + stem.substring(1);
  }

  static (String, String) _resultTypes(String type) {
    if (!type.startsWith('Result<') || !type.endsWith('>')) {
      throw const DartitectConfigException(
        '/factorySource',
        'generated_pull read() must return Future<Result<T, F>>',
      );
    }
    final body = type.substring('Result<'.length, type.length - 1);
    var depth = 0;
    for (var index = 0; index < body.length; index += 1) {
      final character = body[index];
      if (character == '<' || character == '(' || character == '[') depth += 1;
      if (character == '>' || character == ')' || character == ']') depth -= 1;
      if (character == ',' && depth == 0) {
        final value = body.substring(0, index).trim();
        final failure = body.substring(index + 1).trim();
        if (value.isNotEmpty && failure.isNotEmpty) return (value, failure);
      }
    }
    throw const DartitectConfigException(
      '/factorySource',
      'generated_pull read() must return Future<Result<T, F>>',
    );
  }

  static List<String> _typeArguments(String type, String base, int expected) {
    if (!type.startsWith('$base<') || !type.endsWith('>')) {
      throw DartitectConfigException(
        '/factorySource',
        'expected $base with $expected concrete type arguments',
      );
    }
    final body = type.substring(base.length + 1, type.length - 1);
    final arguments = <String>[];
    var start = 0;
    var depth = 0;
    for (var index = 0; index < body.length; index += 1) {
      final character = body[index];
      if (character == '<' || character == '(' || character == '[') depth += 1;
      if (character == '>' || character == ')' || character == ']') depth -= 1;
      if (character == ',' && depth == 0) {
        arguments.add(body.substring(start, index).trim());
        start = index + 1;
      }
    }
    arguments.add(body.substring(start).trim());
    if (arguments.length != expected ||
        arguments.any((value) => value.isEmpty)) {
      throw DartitectConfigException(
        '/factorySource',
        'expected $base with $expected concrete type arguments',
      );
    }
    return arguments;
  }

  static String _renderDrift(
    String name,
    List<MapEntry<String, DartitectStorageDatasetConfig>> datasets,
  ) {
    final type = _pascal(name);
    final registrations = _renderOperationalDatasets(datasets);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Operational schema only; domain tables and queries remain consumer-owned.
// ignore_for_file: public_member_api_docs

import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

const int ${_fieldName(name)}DartitectDriftSchemaVersion = 2;

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

/// Include these tables in the consumer-owned Drift database declaration.
abstract final class ${type}DartitectDriftFragment {
  static const List<Type> tables = <Type>[
    ${type}DartitectOutboxRows,
    ${type}DartitectCheckpointRows,
    ${type}DartitectJournalRows,
    ${type}DartitectLeaseRows,
    ${type}DartitectReceiptRows,
    ${type}DartitectTransferCheckpointRows,
  ];

  static final OperationalStorageContextManifest manifest =
      OperationalStorageContextManifest(
        context: '$name',
        provider: 'drift',
        schemaVersion: ${_fieldName(name)}DartitectDriftSchemaVersion,
        datasets: <OperationalDatasetRegistration>[
$registrations
        ],
        migrations: <OperationalStorageMigration>[
          OperationalStorageMigration(
            fromVersion: 1,
            toVersion: 2,
            id: 'context_scoped_operational_tables',
          ),
        ],
      );
}
''';
  }

  static String _renderObjectBox(
    String name,
    List<MapEntry<String, DartitectStorageDatasetConfig>> datasets,
  ) {
    final type = _pascal(name);
    int uid(String value) => _stableUid('$name/$value');
    final registrations = _renderOperationalDatasets(datasets);
    final uids = <String, int>{
      for (final value in <String>[
        'outbox',
        'outbox/operationId',
        'outbox/dataset',
        'outbox/idempotencyKey',
        'outbox/payload',
        'outbox/state',
        'outbox/attempt',
        'checkpoint',
        'checkpoint/dataset',
        'checkpoint/value',
        'checkpoint/fencing',
        'journal',
        'journal/attemptId',
        'journal/sequence',
        'journal/fact',
        'journal/recordedAt',
        'lease',
        'lease/dataset',
        'lease/owner',
        'lease/fencing',
        'lease/expiry',
        'receipt',
        'receipt/operationId',
        'receipt/status',
        'receipt/recordedAt',
        'transfer',
        'transfer/id',
        'transfer/offset',
        'transfer/revision',
      ])
        value: uid(value),
    };
    final uidManifest = uids.entries
        .map((entry) => "    '${entry.key}': ${entry.value},")
        .join('\n');
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Provider exception: mutable ObjectBox 5.3.2 entities require classic fields.
// UIDs are deterministic and must remain preserved by wiring sync.
// ignore_for_file: public_member_api_docs

import 'package:dartitect_objectbox/dartitect_objectbox.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

const int ${name}DartitectObjectBoxSchemaVersion = 2;

/// Frozen provider UIDs; adding datasets must never change existing values.
const Map<String, int> ${name}DartitectObjectBoxUids = <String, int>{
$uidManifest
};

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

/// Operational-only manifest for inclusion in the consumer ObjectBox model.
abstract final class ${type}DartitectObjectBoxFragment {
  static const List<Type> entities = <Type>[
    ${type}DartitectOutboxEntity,
    ${type}DartitectCheckpointEntity,
    ${type}DartitectJournalEntity,
    ${type}DartitectLeaseEntity,
    ${type}DartitectReceiptEntity,
    ${type}DartitectTransferCheckpointEntity,
  ];

  static final OperationalStorageContextManifest manifest =
      OperationalStorageContextManifest(
        context: '$name',
        provider: 'objectbox',
        schemaVersion: ${name}DartitectObjectBoxSchemaVersion,
        datasets: <OperationalDatasetRegistration>[
$registrations
        ],
        migrations: <OperationalStorageMigration>[
          OperationalStorageMigration(
            fromVersion: 1,
            toVersion: 2,
            id: 'context_scoped_operational_entities',
          ),
        ],
      );
}
''';
  }

  static String _renderOperationalDatasets(
    List<MapEntry<String, DartitectStorageDatasetConfig>> datasets,
  ) => datasets
      .map(
        (entry) =>
            '''          OperationalDatasetRegistration(
            feature: '${entry.key}',
            dataset: '${entry.value.dataset}',
            partition: '${entry.value.partition}',
            codec: '${entry.value.codec}',
            retention: '${entry.value.retention}',
            transactionBoundary: '${entry.value.transactionBoundary}',
          ),''',
      )
      .join('\n');

  static String _renderDio(String name) {
    final type = _pascal(name);
    return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// ignore_for_file: public_member_api_docs

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
// ignore_for_file: public_member_api_docs

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

final class _AvailableValue {
  const _AvailableValue({
    required this.name,
    required this.type,
    String? matchType,
    required this.expression,
  }) : matchType = matchType ?? type;

  final String name;
  final String type;
  final String matchType;
  final String expression;
}
