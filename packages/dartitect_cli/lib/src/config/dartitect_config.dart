import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';

import '../rules/generated_boundary_policy.dart';

/// Current stable on-disk Dartitect configuration version.
const int currentConfigVersion = 3;

/// The only architectural profile supported by Dartitect 1.0.
const String nativeStrictProfile = 'native_strict';

/// A validation failure with an exact JSON Pointer location.
final class DartitectConfigException implements FormatException {
  /// Creates a configuration failure.
  const DartitectConfigException(this.pointer, this.message);

  /// JSON Pointer locating the invalid field.
  final String pointer;

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  String? get source => null;

  @override
  String toString() => 'Invalid dartitect.json at $pointer: $message';
}

/// Reviewed Native Strict suppression.
final class DartitectSuppression {
  /// Creates one narrow suppression.
  const DartitectSuppression({
    required this.code,
    required this.path,
    required this.reason,
    required this.owner,
    required this.expiresAt,
  });

  /// Stable `DTnnnn` code.
  final String code;

  /// Normalized project-relative glob.
  final String path;

  /// Reviewed reason.
  final String reason;

  /// Accountable owner.
  final String owner;

  /// Required UTC expiry date.
  final DateTime expiresAt;

  /// Whether this suppression is expired at [now].
  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt);

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'path': path,
    'reason': reason,
    'owner': owner,
    'expiresAt': expiresAt.toIso8601String().substring(0, 10),
  };
}

/// Closed modeling defaults. Capabilities remain annotation opt-ins.
enum DartitectModelingPreset {
  /// Value semantics only.
  minimal('minimal'),

  /// Complete defaults for new Dartitect-owned values.
  recommended('recommended_complete');

  const DartitectModelingPreset(this.wireName);

  /// Stable JSON name.
  final String wireName;

  /// Suggested independent capabilities.
  List<String> get suggestedCapabilities => switch (this) {
    minimal => const <String>['value'],
    recommended => const <String>['value', 'json', 'projection', 'mapper'],
  };
}

/// Closed generated diagnostics levels for feature wiring.
enum FeatureDiagnosticsLevel {
  /// No feature-level diagnostics wiring.
  off('off'),

  /// Lifecycle counters and closed events.
  basic('basic'),

  /// Full payload-free diagnostics-v2 instrumentation.
  full('full');

  const FeatureDiagnosticsLevel(this.wireName);

  /// Stable CLI and configuration spelling.
  final String wireName;

  /// Parses one supported diagnostics level.
  static FeatureDiagnosticsLevel parse(String value) =>
      _enumByWireName(values, value, 'feature diagnostics level');
}

/// Lifetime of one generated feature graph.
enum FeatureScope {
  /// Owned by the application graph.
  application('application'),

  /// Rebuilt with the authenticated session graph.
  session('session');

  const FeatureScope(this.wireName);

  /// Stable configuration spelling.
  final String wireName;

  /// Parses one supported scope.
  static FeatureScope parse(String value) =>
      _enumByWireName(values, value, 'feature scope');
}

/// A statically resolved consumer factory declaration.
final class DartitectFactorySourceConfig {
  /// Creates a confined source reference to one public concrete declaration.
  DartitectFactorySourceConfig({
    required String source,
    required this.declaration,
  }) : source = _normalizeDartSource(source, '/factorySource/source') {
    if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(declaration)) {
      throw const DartitectConfigException(
        '/factorySource/declaration',
        'expected a public concrete Dart class name',
      );
    }
  }

  /// Confined project-relative Dart source.
  final String source;

  /// Public concrete class declaration in [source].
  final String declaration;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'declaration': declaration,
  };
}

/// Session graph declaration required by session-scoped resources.
final class DartitectSessionConfig {
  /// Creates a session graph declaration.
  const DartitectSessionConfig({required this.factorySource});

  /// Statically analyzed factory for authenticated session roots.
  final DartitectFactorySourceConfig factorySource;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'factorySource': factorySource.toJson(),
  };
}

/// How the local presentation authority is constructed for a feature.
enum FeatureLocalAuthorityStrategy {
  /// Generate `PullReactiveSource` from the factory's typed `watch` and `read`.
  generatedPull('generated_pull'),

  /// Use the concrete local-authority object returned by the feature factory.
  custom('custom');

  const FeatureLocalAuthorityStrategy(this.wireName);

  /// Stable config spelling.
  final String wireName;

  /// Parses one closed strategy.
  static FeatureLocalAuthorityStrategy parse(String value) =>
      _enumByWireName(values, value, 'local-authority strategy');
}

/// One OpenAPI operation selected into a feature graph.
final class DartitectOpenApiOperationConfig {
  /// Creates a typed operation reference.
  DartitectOpenApiOperationConfig({
    required this.contract,
    required this.operationId,
  }) {
    if (!_configName.hasMatch(contract)) {
      throw const DartitectConfigException(
        '/features/declarations/operations/contract',
        'expected a registered snake_case contract name',
      );
    }
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$').hasMatch(operationId)) {
      throw const DartitectConfigException(
        '/features/declarations/operations/operationId',
        'expected a stable OpenAPI operationId',
      );
    }
  }

  /// Contract registry key.
  final String contract;

  /// Exact OpenAPI operationId.
  final String operationId;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'contract': contract,
    'operationId': operationId,
  };
}

/// One bounded local OpenAPI contract registered with a transport context.
final class DartitectContractConfig {
  /// Creates a contract registration.
  DartitectContractConfig({
    required String spec,
    required String output,
    required this.transport,
  }) : spec = _normalizeProjectFile(spec, '/contracts/spec'),
       output = _normalizeGeneratedOutput(output, '/contracts/output') {
    if (!_configName.hasMatch(transport)) {
      throw const DartitectConfigException(
        '/contracts/transport',
        'expected a snake_case transport context name',
      );
    }
  }

  /// Confined local OpenAPI 3.1 JSON or YAML source.
  final String spec;

  /// Confined manifest-owned generated Dart output.
  final String output;

  /// Transport context used by generated clients.
  final String transport;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'spec': spec,
    'output': output,
    'transport': transport,
  };
}

/// Closed target platform identifiers.
enum DartitectPlatform {
  /// Android applications.
  android('android'),

  /// iOS applications.
  ios('ios'),

  /// macOS applications.
  macos('macos'),

  /// Windows applications.
  windows('windows'),

  /// Linux applications.
  linux('linux'),

  /// Web applications.
  web('web');

  const DartitectPlatform(this.wireName);

  /// Stable configuration spelling.
  final String wireName;

  /// Parses one supported platform.
  static DartitectPlatform parse(String value) =>
      _enumByWireName(values, value, 'platform');
}

/// Closed pagination policies materialized by feature wiring.
enum FeaturePagination {
  /// No paginated query contract.
  none('none'),

  /// Consumer-opaque cursor pagination.
  cursor('cursor');

  const FeaturePagination(this.wireName);

  /// Stable configuration spelling.
  final String wireName;

  /// Parses one supported policy.
  static FeaturePagination parse(String value) =>
      _enumByWireName(values, value, 'pagination mode');
}

/// Stable opt-in workflows that tooling may materialize.
enum DartitectCapability {
  /// Credential expiry, refresh, invalidation, and session rebuild wiring.
  credentials('credentials'),

  /// Durable resumable attachment transfer wiring.
  attachments('attachments'),

  /// Restorable form and draft workflow wiring.
  forms('forms'),

  /// Local-authority query-controller wiring.
  queries('queries');

  const DartitectCapability(this.wireName);

  /// Stable configuration spelling.
  final String wireName;

  /// Parses one supported capability.
  static DartitectCapability parse(String value) =>
      _enumByWireName(values, value, 'feature capability');
}

/// Explicit application target block.
final class DartitectTargetsConfig {
  /// Creates a non-empty, deterministic target set.
  DartitectTargetsConfig(Iterable<DartitectPlatform> platforms)
    : platforms = List<DartitectPlatform>.unmodifiable(
        platforms.toSet().toList()
          ..sort((left, right) => left.index.compareTo(right.index)),
      ) {
    if (this.platforms.isEmpty) {
      throw const DartitectConfigException(
        '/targets/platforms',
        'expected at least one supported platform',
      );
    }
  }

  /// Platforms generated and supported by this project.
  final List<DartitectPlatform> platforms;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'platforms': platforms.map((platform) => platform.wireName).toList(),
  };
}

/// Storage durability available to feature assemblies.
enum DartitectStorageMode {
  /// Durable provider-backed operational state.
  durable('durable'),

  /// Process-local state allowed only for development and tests.
  memory('memory');

  const DartitectStorageMode(this.wireName);

  /// Stable configuration spelling.
  final String wireName;
}

/// One explicitly selected storage context shared by features.
final class DartitectStorageContextConfig {
  /// Creates a storage context for an exact target set.
  DartitectStorageContextConfig({
    required this.provider,
    required this.mode,
    this.scope = FeatureScope.application,
    DartitectFactorySourceConfig? factorySource,
    required Iterable<DartitectPlatform> targets,
  }) : factorySource =
           factorySource ??
           DartitectFactorySourceConfig(
             source: 'lib/composition/storage_context_factory.dart',
             declaration: 'StorageContextFactory',
           ),
       targets = _platformSet(targets, '/storageContexts/targets') {
    _validateProviderIdentifier(
      provider,
      pointer: '/storageContexts/provider',
      builtIns: const <String>{'drift', 'objectbox', 'memory'},
    );
    if ((provider == 'memory') != (mode == DartitectStorageMode.memory)) {
      throw const DartitectConfigException(
        '/storageContexts/mode',
        'memory providers require memory mode and durable providers require durable mode',
      );
    }
    if (provider == 'objectbox' &&
        this.targets.contains(DartitectPlatform.web)) {
      throw const DartitectConfigException(
        '/storageContexts/targets',
        'ObjectBox is not implemented on web',
      );
    }
  }

  /// `drift`, `objectbox`, `memory`, or a project-local provider identifier.
  final String provider;

  /// Whether operational state survives a process restart.
  final DartitectStorageMode mode;

  /// Application- or session-owned context lifetime.
  final FeatureScope scope;

  /// Consumer factory that opens this exact provider context.
  final DartitectFactorySourceConfig factorySource;

  /// Exact platforms supported by this context.
  final List<DartitectPlatform> targets;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'mode': mode.wireName,
    'scope': scope.wireName,
    'factorySource': factorySource.toJson(),
    'targets': targets.map((target) => target.wireName).toList(),
  };
}

/// Operational dataset registration within one named storage context.
///
/// The values are structural storage facts only. Domain schemas, semantic
/// mapping, conflict policy, and retention execution remain consumer-owned.
final class DartitectStorageDatasetConfig {
  /// Creates an explicit operational dataset registration.
  DartitectStorageDatasetConfig({
    required this.dataset,
    required this.partition,
    required this.codec,
    required this.retention,
    required this.transactionBoundary,
  }) {
    for (final entry in <String, String>{
      'dataset': dataset,
      'partition': partition,
      'codec': codec,
      'transactionBoundary': transactionBoundary,
    }.entries) {
      if (!_configName.hasMatch(entry.value)) {
        throw DartitectConfigException(
          '/features/declarations/dataset/${entry.key}',
          'expected an ASCII snake_case identifier',
        );
      }
    }
    if (retention != 'indefinite' &&
        !RegExp(r'^P[1-9][0-9]*D$').hasMatch(retention)) {
      throw const DartitectConfigException(
        '/features/declarations/dataset/retention',
        'expected indefinite or an ISO day duration such as P30D',
      );
    }
  }

  /// Creates the explicit defaults emitted by `create feature`.
  factory DartitectStorageDatasetConfig.forFeature(String name) =>
      DartitectStorageDatasetConfig(
        dataset: name,
        partition: 'default_partition',
        codec: '${name}_v1',
        retention: 'indefinite',
        transactionBoundary: '${name}_transaction',
      );

  /// Unique dataset name within its storage context.
  final String dataset;

  /// Consumer-defined partition strategy identifier.
  final String partition;

  /// Consumer-owned codec identifier and version.
  final String codec;

  /// Operational retention declaration, not an automatic deletion policy.
  final String retention;

  /// Consumer-owned atomic transaction boundary identifier.
  final String transactionBoundary;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'dataset': dataset,
    'partition': partition,
    'codec': codec,
    'retention': retention,
    'transactionBoundary': transactionBoundary,
  };
}

/// One explicit transport binding shared by features.
final class DartitectTransportConfig {
  /// Creates a transport binding for an exact target set.
  DartitectTransportConfig({
    required this.provider,
    this.scope = FeatureScope.application,
    DartitectFactorySourceConfig? factorySource,
    required Iterable<DartitectPlatform> targets,
  }) : factorySource =
           factorySource ??
           DartitectFactorySourceConfig(
             source: 'lib/composition/transport_context_factory.dart',
             declaration: 'TransportContextFactory',
           ),
       targets = _platformSet(targets, '/transports/targets') {
    _validateProviderIdentifier(
      provider,
      pointer: '/transports/provider',
      builtIns: const <String>{'dio'},
    );
  }

  /// `dio` or a project-local provider identifier.
  final String provider;

  /// Application- or session-owned transport lifetime.
  final FeatureScope scope;

  /// Consumer factory that opens this exact transport context.
  final DartitectFactorySourceConfig factorySource;

  /// Exact platforms supported by this transport.
  final List<DartitectPlatform> targets;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'scope': scope.wireName,
    'factorySource': factorySource.toJson(),
    'targets': targets.map((target) => target.wireName).toList(),
  };
}

/// Explicit observability selection; no remote destination is implicit.
final class DartitectObservabilityConfig {
  /// Creates an observability block.
  DartitectObservabilityConfig({
    this.provider = 'none',
    Iterable<DartitectPlatform> targets = const <DartitectPlatform>[],
  }) : targets = _optionalPlatformSet(targets) {
    _validateProviderIdentifier(
      provider,
      pointer: '/observability/provider',
      builtIns: const <String>{'none', 'developer', 'sentry'},
    );
  }

  /// `none`, `developer`, `sentry`, or a project-local provider identifier.
  final String provider;

  /// Restricted targets, or empty to inherit application targets.
  final List<DartitectPlatform> targets;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    if (targets.isNotEmpty)
      'targets': targets.map((target) => target.wireName).toList(),
  };
}

/// Explicit scheduler selection; background work is disabled by default.
final class DartitectSchedulerConfig {
  /// Creates a scheduler block.
  DartitectSchedulerConfig({
    this.provider = 'none',
    Iterable<DartitectPlatform> targets = const <DartitectPlatform>[],
  }) : targets = _optionalPlatformSet(targets) {
    _validateProviderIdentifier(
      provider,
      pointer: '/scheduler/provider',
      builtIns: const <String>{'none', 'workmanager'},
    );
    if (provider == 'workmanager' &&
        this.targets.contains(DartitectPlatform.windows)) {
      throw const DartitectConfigException(
        '/scheduler/targets',
        'Workmanager is unsupported on Windows',
      );
    }
  }

  /// `none`, `workmanager`, or a project-local provider identifier.
  final String provider;

  /// Restricted targets, or empty to inherit application targets.
  final List<DartitectPlatform> targets;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    if (targets.isNotEmpty)
      'targets': targets.map((target) => target.wireName).toList(),
  };
}

/// One strict, executable feature declaration.
final class DartitectFeatureDeclaration {
  /// Creates and validates a declaration.
  DartitectFeatureDeclaration({
    required this.profile,
    required this.scope,
    DartitectFactorySourceConfig? factorySource,
    this.localAuthority = FeatureLocalAuthorityStrategy.custom,
    required this.pagination,
    required this.diagnostics,
    this.storageContext,
    this.dataset,
    this.transport,
    Iterable<DartitectPlatform> targets = const <DartitectPlatform>[],
    Iterable<DartitectPlatform> headlessTargets = const <DartitectPlatform>[],
    Iterable<DartitectCapability> capabilities = const <DartitectCapability>[],
    Iterable<DartitectOpenApiOperationConfig> operations =
        const <DartitectOpenApiOperationConfig>[],
  }) : factorySource =
           factorySource ??
           DartitectFactorySourceConfig(
             source: 'lib/features/feature/composition/feature_factory.dart',
             declaration: 'FeatureFactory',
           ),
       targets = _optionalPlatformSet(targets),
       headlessTargets = _optionalPlatformSet(headlessTargets),
       capabilities = List<DartitectCapability>.unmodifiable(
         capabilities.toSet().toList()
           ..sort((left, right) => left.wireName.compareTo(right.wireName)),
       ),
       operations = List<DartitectOpenApiOperationConfig>.unmodifiable(
         operations.toSet().toList()..sort((left, right) {
           final byContract = left.contract.compareTo(right.contract);
           return byContract != 0
               ? byContract
               : left.operationId.compareTo(right.operationId);
         }),
       ) {
    if (storageContext != null && !_configName.hasMatch(storageContext!)) {
      throw const DartitectConfigException(
        '/features/declarations/storageContext',
        'expected an ASCII snake_case storage context name',
      );
    }
    if ((storageContext == null) != (dataset == null)) {
      throw const DartitectConfigException(
        '/features/declarations/dataset',
        'storage contexts and dataset registrations must be declared together',
      );
    }
    if (transport != null && !_configName.hasMatch(transport!)) {
      throw const DartitectConfigException(
        '/features/declarations/transport',
        'expected an ASCII snake_case transport name',
      );
    }
    switch (profile) {
      case FeatureProfile.local:
        if (transport != null || this.headlessTargets.isNotEmpty) {
          throw const DartitectConfigException(
            '/features/declarations',
            'local profiles prohibit transport, sync, and headless execution',
          );
        }
      case FeatureProfile.online:
        if (transport == null || storageContext != null) {
          throw const DartitectConfigException(
            '/features/declarations',
            'online profiles require transport and prohibit persistence',
          );
        }
      case FeatureProfile.cache ||
          FeatureProfile.replica ||
          FeatureProfile.offlineFull:
        if (transport == null || storageContext == null) {
          throw const DartitectConfigException(
            '/features/declarations',
            'cache, replica, and offline-full require explicit transport and storage context',
          );
        }
    }
    final hasGeneratedAuthority =
        localAuthority == FeatureLocalAuthorityStrategy.generatedPull;
    if (hasGeneratedAuthority && storageContext == null) {
      throw const DartitectConfigException(
        '/features/declarations/localAuthority',
        'generated_pull requires a storage context',
      );
    }
    if (profile == FeatureProfile.online &&
        localAuthority != FeatureLocalAuthorityStrategy.custom) {
      throw const DartitectConfigException(
        '/features/declarations/localAuthority',
        'online profiles require custom because they have no local authority',
      );
    }
    if (this.headlessTargets.isNotEmpty &&
        profile != FeatureProfile.replica &&
        profile != FeatureProfile.offlineFull) {
      throw const DartitectConfigException(
        '/features/declarations/headlessTargets',
        'headless execution requires replica or offline-full',
      );
    }
  }

  /// Paved-road behavior profile.
  final FeatureProfile profile;

  /// Application or authenticated-session owner.
  final FeatureScope scope;

  /// Consumer-owned factory selected for this feature.
  final DartitectFactorySourceConfig factorySource;

  /// Generated or custom local-authority construction.
  final FeatureLocalAuthorityStrategy localAuthority;

  /// Named storage context, when this profile uses persistence.
  final String? storageContext;

  /// Operational registration inside [storageContext], when persisted.
  final DartitectStorageDatasetConfig? dataset;

  /// Named transport, when this profile uses remote access.
  final String? transport;

  /// Restricted targets, or empty to inherit application targets.
  final List<DartitectPlatform> targets;

  /// Pagination policy.
  final FeaturePagination pagination;

  /// Payload-free diagnostics wiring level.
  final FeatureDiagnosticsLevel diagnostics;

  /// Exact targets that opt in to headless execution.
  final List<DartitectPlatform> headlessTargets;

  /// Independently opted-in stable workflows.
  final List<DartitectCapability> capabilities;

  /// Exact OpenAPI operations included in this feature graph.
  final List<DartitectOpenApiOperationConfig> operations;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile.wireName,
    'scope': scope.wireName,
    'factorySource': factorySource.toJson(),
    'localAuthority': localAuthority.wireName,
    if (storageContext != null) 'storageContext': storageContext,
    if (dataset != null) 'dataset': dataset!.toJson(),
    if (transport != null) 'transport': transport,
    if (targets.isNotEmpty)
      'targets': targets.map((target) => target.wireName).toList(),
    'pagination': pagination.wireName,
    'diagnostics': diagnostics.wireName,
    'headlessTargets': headlessTargets
        .map((target) => target.wireName)
        .toList(),
    'capabilities': capabilities
        .map((capability) => capability.wireName)
        .toList(),
    'operations': operations.map((operation) => operation.toJson()).toList(),
  };
}

/// Strict feature declaration registry.
final class DartitectFeaturesConfig {
  /// Creates an immutable registry.
  DartitectFeaturesConfig({
    Map<String, DartitectFeatureDeclaration> declarations =
        const <String, DartitectFeatureDeclaration>{},
  }) : declarations = Map<String, DartitectFeatureDeclaration>.unmodifiable(
         declarations,
       ) {
    for (final name in declarations.keys) {
      if (!_featureName.hasMatch(name)) {
        throw DartitectConfigException(
          '/features/declarations/${_pointerToken(name)}',
          'expected an ASCII snake_case feature name',
        );
      }
    }
  }

  /// Feature declarations keyed by snake_case feature name.
  final Map<String, DartitectFeatureDeclaration> declarations;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'declarations': <String, Object?>{
      for (final entry in declarations.entries) entry.key: entry.value.toJson(),
    },
  };
}

/// Additive modeling configuration for stable config v3.
final class DartitectModelingConfig {
  /// Creates an explicit modeling block.
  const DartitectModelingConfig({
    required this.preset,
    this.maxDepth = 64,
    this.maxCollectionItems = 10000,
    this.maxNodes = 100000,
  });

  /// Defaults for new models.
  final DartitectModelingPreset preset;

  /// Untrusted JSON nesting bound.
  final int maxDepth;

  /// Untrusted per-collection item bound.
  final int maxCollectionItems;

  /// Untrusted total decoded-node bound.
  final int maxNodes;

  /// Stable machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'preset': preset.wireName,
    'jsonLimits': <String, Object?>{
      'maxDepth': maxDepth,
      'maxCollectionItems': maxCollectionItems,
      'maxNodes': maxNodes,
    },
  };
}

/// Stable v3 Native Strict configuration.
final class DartitectConfig {
  /// Creates the default strict configuration.
  DartitectConfig({
    this.configVersion = currentConfigVersion,
    this.profile = nativeStrictProfile,
    Map<String, List<String>> layers = DartitectArchitectureRules.defaultLayers,
    List<String> compositionRoots =
        DartitectArchitectureRules.defaultCompositionRoots,
    List<String> generatedInfrastructure =
        DartitectArchitectureRules.defaultGeneratedInfrastructure,
    List<String> generatedSuffixes =
        DartitectArchitectureRules.defaultGeneratedSuffixes,
    List<DartitectSuppression> suppressions = const <DartitectSuppression>[],
    this.modeling,
    DartitectFeaturesConfig? features,
    DartitectTargetsConfig? targets,
    Map<String, DartitectStorageContextConfig> storageContexts =
        const <String, DartitectStorageContextConfig>{},
    Map<String, DartitectTransportConfig> transports =
        const <String, DartitectTransportConfig>{},
    Map<String, DartitectContractConfig> contracts =
        const <String, DartitectContractConfig>{},
    this.session,
    DartitectObservabilityConfig? observability,
    DartitectSchedulerConfig? scheduler,
    Iterable<String> extensionSources = const <String>[],
  }) : layers = _copyLayers(layers),
       compositionRoots = List<String>.unmodifiable(compositionRoots),
       generatedInfrastructure = List<String>.unmodifiable(
         generatedInfrastructure,
       ),
       generatedSuffixes = List<String>.unmodifiable(generatedSuffixes),
       suppressions = List<DartitectSuppression>.unmodifiable(suppressions),
       features = features ?? DartitectFeaturesConfig(),
       targets =
           targets ??
           DartitectTargetsConfig(const <DartitectPlatform>[
             DartitectPlatform.android,
           ]),
       storageContexts = _sortedConfigMap(storageContexts),
       transports = _sortedConfigMap(transports),
       contracts = _sortedConfigMap(contracts),
       observability = observability ?? DartitectObservabilityConfig(),
       scheduler = scheduler ?? DartitectSchedulerConfig(),
       extensionSources = List<String>.unmodifiable(
         extensionSources.map(
           (source) => _normalizeDartSource(source, '/extensionSources'),
         ),
       ) {
    if (configVersion != currentConfigVersion) {
      throw DartitectConfigException(
        '/configVersion',
        'expected stable version $currentConfigVersion',
      );
    }
    if (profile != nativeStrictProfile) {
      throw const DartitectConfigException(
        '/profile',
        'expected native_strict',
      );
    }
    for (final name in <String>{
      ...this.storageContexts.keys,
      ...this.transports.keys,
      ...this.contracts.keys,
    }) {
      if (!_configName.hasMatch(name)) {
        final section = this.storageContexts.containsKey(name)
            ? 'storageContexts'
            : this.transports.containsKey(name)
            ? 'transports'
            : 'contracts';
        throw DartitectConfigException(
          '/$section/${_pointerToken(name)}',
          'expected an ASCII snake_case binding name',
        );
      }
    }
    _validateImplementations();
  }

  /// Parses and validates JSON text.
  factory DartitectConfig.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DartitectConfigException('/', error.message);
    }
    if (decoded is! Map<String, Object?>) {
      throw const DartitectConfigException('/', 'expected a JSON object');
    }
    return DartitectConfig.fromJson(decoded);
  }

  /// Validates a decoded stable-v3 JSON object.
  factory DartitectConfig.fromJson(Map<String, Object?> json) {
    const known = <String>{
      'configVersion',
      'profile',
      'layers',
      'compositionRoots',
      'generatedInfrastructure',
      'generatedSuffixes',
      'suppressions',
      'modeling',
      'features',
      'targets',
      'storageContexts',
      'transports',
      'contracts',
      'session',
      'observability',
      'scheduler',
      'extensionSources',
    };
    _rejectUnknown(json, known, '');
    final version = _requiredInt(json, 'configVersion', '');
    if (version != currentConfigVersion) {
      throw DartitectConfigException(
        '/configVersion',
        'expected stable version $currentConfigVersion; only an explicit '
            'Dartitect-project upgrade may migrate config v1 or v2',
      );
    }
    final profile = _requiredString(json, 'profile', '');
    if (profile != nativeStrictProfile) {
      throw const DartitectConfigException(
        '/profile',
        'expected native_strict',
      );
    }
    return DartitectConfig(
      configVersion: version,
      profile: profile,
      layers: _parseLayers(json['layers']),
      compositionRoots: _globList(
        json['compositionRoots'],
        '/compositionRoots',
      ),
      generatedInfrastructure: _globList(
        json['generatedInfrastructure'],
        '/generatedInfrastructure',
      ),
      generatedSuffixes: _suffixList(json['generatedSuffixes']),
      suppressions: _parseSuppressions(json['suppressions']),
      modeling: _parseModeling(json['modeling']),
      features: _parseFeatures(json['features']),
      targets: _parseTargets(json['targets']),
      storageContexts: _parseStorageContexts(json['storageContexts']),
      transports: _parseTransports(json['transports']),
      contracts: _parseContracts(json['contracts']),
      session: _parseSession(json['session']),
      observability: _parseObservability(json['observability']),
      scheduler: _parseScheduler(json['scheduler']),
      extensionSources: _parseExtensionSources(json['extensionSources']),
    );
  }

  /// Stable schema version. The only accepted value is `3`.
  final int configVersion;

  /// Strict architecture profile. The only accepted value is `native_strict`.
  final String profile;

  /// Named normalized layer globs.
  final Map<String, List<String>> layers;

  /// Globs where concrete graph composition is allowed.
  final List<String> compositionRoots;

  /// Globs where provider-generated infrastructure may exist.
  final List<String> generatedInfrastructure;

  /// Generated source suffixes accepted with a standard generated header.
  final List<String> generatedSuffixes;

  /// Reviewed, narrow architecture suppressions.
  final List<DartitectSuppression> suppressions;

  /// Optional modeling policy.
  final DartitectModelingConfig? modeling;

  /// Strict feature declarations.
  final DartitectFeaturesConfig features;

  /// Explicit application target platforms.
  final DartitectTargetsConfig targets;

  /// Named storage contexts shared across feature assemblies.
  final Map<String, DartitectStorageContextConfig> storageContexts;

  /// Named transport bindings shared across feature assemblies.
  final Map<String, DartitectTransportConfig> transports;

  /// Bounded local OpenAPI contracts keyed by snake_case name.
  final Map<String, DartitectContractConfig> contracts;

  /// Session graph factory, required by session-scoped declarations.
  final DartitectSessionConfig? session;

  /// Explicit observability binding.
  final DartitectObservabilityConfig observability;

  /// Explicit scheduler binding.
  final DartitectSchedulerConfig scheduler;

  /// Confined Dart sources containing typed project-local extensions.
  final List<String> extensionSources;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'configVersion': configVersion,
    'profile': profile,
    'layers': layers,
    'compositionRoots': compositionRoots,
    'generatedInfrastructure': generatedInfrastructure,
    'generatedSuffixes': generatedSuffixes,
    'suppressions': suppressions.map((value) => value.toJson()).toList(),
    if (modeling != null) 'modeling': modeling!.toJson(),
    'targets': targets.toJson(),
    'storageContexts': <String, Object?>{
      for (final entry in storageContexts.entries)
        entry.key: entry.value.toJson(),
    },
    'transports': <String, Object?>{
      for (final entry in transports.entries) entry.key: entry.value.toJson(),
    },
    'contracts': <String, Object?>{
      for (final entry in contracts.entries) entry.key: entry.value.toJson(),
    },
    if (session != null) 'session': session!.toJson(),
    'observability': observability.toJson(),
    'scheduler': scheduler.toJson(),
    'features': features.toJson(),
    'extensionSources': extensionSources,
  };

  /// Canonical two-space JSON with a trailing newline.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Reads and validates [file] without modifying it.
  static Future<DartitectConfig> load(File file) async =>
      DartitectConfig.parse(await file.readAsString());

  void _validateImplementations() {
    final applicationTargets = targets.platforms.toSet();
    final registeredDatasets = <String, String>{};
    void validateRestrictedTargets(
      Iterable<DartitectPlatform> restricted,
      String pointer,
    ) {
      final outside = restricted.where(
        (target) => !applicationTargets.contains(target),
      );
      if (outside.isNotEmpty) {
        throw DartitectConfigException(
          pointer,
          '${outside.first.wireName} is not an application target',
        );
      }
    }

    validateRestrictedTargets(observability.targets, '/observability/targets');
    validateRestrictedTargets(scheduler.targets, '/scheduler/targets');
    for (final entry in storageContexts.entries) {
      validateRestrictedTargets(
        entry.value.targets,
        '/storageContexts/${_pointerToken(entry.key)}/targets',
      );
      if (entry.value.scope == FeatureScope.session && session == null) {
        throw DartitectConfigException(
          '/storageContexts/${_pointerToken(entry.key)}/scope',
          'session-scoped contexts require session.factorySource',
        );
      }
    }
    for (final entry in transports.entries) {
      validateRestrictedTargets(
        entry.value.targets,
        '/transports/${_pointerToken(entry.key)}/targets',
      );
      if (entry.value.scope == FeatureScope.session && session == null) {
        throw DartitectConfigException(
          '/transports/${_pointerToken(entry.key)}/scope',
          'session-scoped contexts require session.factorySource',
        );
      }
    }
    final contractOutputs = <String>{};
    for (final entry in contracts.entries) {
      final contract = entry.value;
      if (!transports.containsKey(contract.transport)) {
        throw DartitectConfigException(
          '/contracts/${_pointerToken(entry.key)}/transport',
          'unknown transport context "${contract.transport}"',
        );
      }
      if (!contractOutputs.add(contract.output)) {
        throw DartitectConfigException(
          '/contracts/${_pointerToken(entry.key)}/output',
          'generated contract outputs must be unique',
        );
      }
    }
    for (final entry in features.declarations.entries) {
      final pointer = '/features/declarations/${_pointerToken(entry.key)}';
      final declaration = entry.value;
      if (declaration.scope == FeatureScope.session && session == null) {
        throw DartitectConfigException(
          '$pointer/scope',
          'session-scoped features require session.factorySource',
        );
      }
      final featureTargets = declaration.targets.isEmpty
          ? applicationTargets
          : declaration.targets.toSet();
      validateRestrictedTargets(declaration.targets, '$pointer/targets');
      validateRestrictedTargets(
        declaration.headlessTargets,
        '$pointer/headlessTargets',
      );
      final invalidHeadless = declaration.headlessTargets.where(
        (target) => !featureTargets.contains(target),
      );
      if (invalidHeadless.isNotEmpty) {
        throw DartitectConfigException(
          '$pointer/headlessTargets',
          '${invalidHeadless.first.wireName} is not a feature target',
        );
      }
      final storageName = declaration.storageContext;
      if (storageName != null) {
        final storage = storageContexts[storageName];
        if (storage == null) {
          throw DartitectConfigException(
            '$pointer/storageContext',
            'unknown storage context "$storageName"',
          );
        }
        final unsupported = featureTargets.where(
          (target) => !storage.targets.contains(target),
        );
        if (unsupported.isNotEmpty) {
          throw DartitectConfigException(
            '$pointer/storageContext',
            '$storageName does not support ${unsupported.first.wireName}',
          );
        }
        if (declaration.profile != FeatureProfile.local &&
            storage.mode != DartitectStorageMode.durable) {
          throw DartitectConfigException(
            '$pointer/storageContext',
            '${declaration.profile.wireName} requires durable operational storage',
          );
        }
        if (declaration.scope == FeatureScope.application &&
            storage.scope == FeatureScope.session) {
          throw DartitectConfigException(
            '$pointer/storageContext',
            'application features cannot borrow session-scoped storage',
          );
        }
        final dataset = declaration.dataset!;
        final registrationKey = '$storageName/${dataset.dataset}';
        final priorFeature = registeredDatasets[registrationKey];
        if (priorFeature != null) {
          throw DartitectConfigException(
            '$pointer/dataset/dataset',
            'dataset ${dataset.dataset} is already registered by $priorFeature in $storageName',
          );
        }
        registeredDatasets[registrationKey] = entry.key;
      }
      final transportName = declaration.transport;
      if (transportName != null) {
        final transport = transports[transportName];
        if (transport == null) {
          throw DartitectConfigException(
            '$pointer/transport',
            'unknown transport "$transportName"',
          );
        }
        final unsupported = featureTargets.where(
          (target) => !transport.targets.contains(target),
        );
        if (unsupported.isNotEmpty) {
          throw DartitectConfigException(
            '$pointer/transport',
            '$transportName does not support ${unsupported.first.wireName}',
          );
        }
        if (declaration.scope == FeatureScope.application &&
            transport.scope == FeatureScope.session) {
          throw DartitectConfigException(
            '$pointer/transport',
            'application features cannot borrow session-scoped transports',
          );
        }
      }
      final selectedOperations = <String>{};
      for (var index = 0; index < declaration.operations.length; index += 1) {
        final operation = declaration.operations[index];
        final contract = contracts[operation.contract];
        if (contract == null) {
          throw DartitectConfigException(
            '$pointer/operations/$index/contract',
            'unknown contract "${operation.contract}"',
          );
        }
        if (declaration.transport != contract.transport) {
          throw DartitectConfigException(
            '$pointer/operations/$index/contract',
            'contract transport ${contract.transport} does not match the feature transport',
          );
        }
        final key = '${operation.contract}/${operation.operationId}';
        if (!selectedOperations.add(key)) {
          throw DartitectConfigException(
            '$pointer/operations/$index',
            'duplicate OpenAPI operation selection',
          );
        }
      }
      if (scheduler.provider == 'none' &&
          declaration.headlessTargets.isNotEmpty) {
        throw DartitectConfigException(
          '$pointer/headlessTargets',
          'headless execution requires an implemented scheduler',
        );
      }
      if (declaration.headlessTargets.isNotEmpty) {
        final schedulerTargets = scheduler.targets.isEmpty
            ? applicationTargets
            : scheduler.targets.toSet();
        final unsupported = declaration.headlessTargets.where(
          (target) => !schedulerTargets.contains(target),
        );
        if (unsupported.isNotEmpty) {
          throw DartitectConfigException(
            '$pointer/headlessTargets',
            'scheduler does not support ${unsupported.first.wireName}',
          );
        }
      }
    }
  }

  static Map<String, List<String>> _parseLayers(Object? value) {
    if (value is! Map<String, Object?> || value.isEmpty) {
      throw const DartitectConfigException(
        '/layers',
        'expected a non-empty object',
      );
    }
    const required = <String>{
      'presentation',
      'application',
      'domain',
      'data',
      'infrastructure',
    };
    final missing = required.difference(value.keys.toSet());
    if (missing.isNotEmpty) {
      final names = missing.toList()..sort();
      throw DartitectConfigException(
        '/layers',
        'missing required layers: $names',
      );
    }
    final output = <String, List<String>>{};
    for (final entry in value.entries) {
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(entry.key)) {
        throw DartitectConfigException(
          '/layers/${_pointerToken(entry.key)}',
          'invalid layer name',
        );
      }
      output[entry.key] = _globList(
        entry.value,
        '/layers/${_pointerToken(entry.key)}',
      );
    }
    return output;
  }

  static List<DartitectSuppression> _parseSuppressions(Object? value) {
    if (value is! List<Object?>) {
      throw const DartitectConfigException(
        '/suppressions',
        'expected an array',
      );
    }
    final output = <DartitectSuppression>[];
    for (var index = 0; index < value.length; index += 1) {
      final raw = value[index];
      final pointer = '/suppressions/$index';
      if (raw is! Map<String, Object?>) {
        throw DartitectConfigException(pointer, 'expected an object');
      }
      const known = <String>{'code', 'path', 'reason', 'owner', 'expiresAt'};
      _rejectUnknown(raw, known, pointer);
      final code = _requiredString(raw, 'code', pointer);
      if (!RegExp(r'^DT\d{4}$').hasMatch(code)) {
        throw DartitectConfigException(
          '$pointer/code',
          'expected DT followed by four digits',
        );
      }
      final expires = raw['expiresAt'];
      if (expires is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expires)) {
        throw DartitectConfigException(
          '$pointer/expiresAt',
          'required in YYYY-MM-DD format',
        );
      }
      final expiresAt = DateTime.tryParse('${expires}T00:00:00Z');
      if (expiresAt == null) {
        throw DartitectConfigException('$pointer/expiresAt', 'invalid date');
      }
      output.add(
        DartitectSuppression(
          code: code,
          path: _normalizeGlob(
            _requiredString(raw, 'path', pointer),
            '$pointer/path',
          ),
          reason: _requiredString(raw, 'reason', pointer),
          owner: _requiredString(raw, 'owner', pointer),
          expiresAt: expiresAt,
        ),
      );
    }
    return output;
  }

  static DartitectModelingConfig? _parseModeling(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/modeling', 'expected an object');
    }
    _rejectUnknown(value, const <String>{'preset', 'jsonLimits'}, '/modeling');
    final presetValue = _requiredString(value, 'preset', '/modeling');
    final preset = DartitectModelingPreset.values
        .where((candidate) => candidate.wireName == presetValue)
        .firstOrNull;
    if (preset == null) {
      throw const DartitectConfigException(
        '/modeling/preset',
        'expected minimal or recommended_complete',
      );
    }
    final limits = value['jsonLimits'];
    if (limits is! Map<String, Object?>) {
      throw const DartitectConfigException(
        '/modeling/jsonLimits',
        'expected an object',
      );
    }
    const keys = <String>{'maxDepth', 'maxCollectionItems', 'maxNodes'};
    _rejectUnknown(limits, keys, '/modeling/jsonLimits');
    int positive(String key) {
      final raw = limits[key];
      if (raw is! int || raw <= 0) {
        throw DartitectConfigException(
          '/modeling/jsonLimits/$key',
          'expected a positive integer',
        );
      }
      return raw;
    }

    return DartitectModelingConfig(
      preset: preset,
      maxDepth: positive('maxDepth'),
      maxCollectionItems: positive('maxCollectionItems'),
      maxNodes: positive('maxNodes'),
    );
  }

  static DartitectFeaturesConfig _parseFeatures(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/features', 'expected an object');
    }
    _rejectUnknown(value, const <String>{'declarations'}, '/features');
    final rawDeclarations = value['declarations'];
    if (rawDeclarations is! Map<String, Object?>) {
      throw const DartitectConfigException(
        '/features/declarations',
        'expected an object',
      );
    }
    final declarations = <String, DartitectFeatureDeclaration>{};
    for (final entry in rawDeclarations.entries) {
      final pointer = '/features/declarations/${_pointerToken(entry.key)}';
      final raw = entry.value;
      if (raw is! Map<String, Object?>) {
        throw DartitectConfigException(pointer, 'expected an object');
      }
      const known = <String>{
        'profile',
        'scope',
        'factorySource',
        'localAuthority',
        'storageContext',
        'dataset',
        'transport',
        'targets',
        'pagination',
        'diagnostics',
        'headlessTargets',
        'capabilities',
        'operations',
      };
      _rejectUnknown(raw, known, pointer);
      final capabilitiesRaw = raw['capabilities'];
      if (capabilitiesRaw is! List<Object?>) {
        throw DartitectConfigException(
          '$pointer/capabilities',
          'expected an array',
        );
      }
      final capabilities = <DartitectCapability>[];
      for (var index = 0; index < capabilitiesRaw.length; index += 1) {
        final capability = capabilitiesRaw[index];
        if (capability is! String) {
          throw DartitectConfigException(
            '$pointer/capabilities/$index',
            'expected a string',
          );
        }
        try {
          final parsed = DartitectCapability.parse(capability);
          if (!capabilities.contains(parsed)) capabilities.add(parsed);
        } on FormatException catch (error) {
          throw DartitectConfigException(
            '$pointer/capabilities/$index',
            error.message,
          );
        }
      }
      try {
        declarations[entry.key] = DartitectFeatureDeclaration(
          profile: FeatureProfile.parse(
            _requiredString(raw, 'profile', pointer),
          ),
          scope: FeatureScope.parse(_requiredString(raw, 'scope', pointer)),
          factorySource: _parseFactorySource(
            raw['factorySource'],
            '$pointer/factorySource',
          ),
          localAuthority: FeatureLocalAuthorityStrategy.parse(
            _requiredString(raw, 'localAuthority', pointer),
          ),
          storageContext: _optionalString(raw, 'storageContext', pointer),
          dataset: _parseStorageDataset(raw['dataset'], '$pointer/dataset'),
          transport: _optionalString(raw, 'transport', pointer),
          targets: raw.containsKey('targets')
              ? _parsePlatformList(raw['targets'], '$pointer/targets')
              : const <DartitectPlatform>[],
          pagination: FeaturePagination.parse(
            _requiredString(raw, 'pagination', pointer),
          ),
          diagnostics: FeatureDiagnosticsLevel.parse(
            _requiredString(raw, 'diagnostics', pointer),
          ),
          headlessTargets: _parsePlatformList(
            raw['headlessTargets'],
            '$pointer/headlessTargets',
            allowEmpty: true,
          ),
          capabilities: capabilities,
          operations: _parseOperations(
            raw['operations'],
            '$pointer/operations',
          ),
        );
      } on DartitectConfigException catch (error) {
        final suffix = error.pointer.startsWith('/features/declarations')
            ? error.pointer.substring('/features/declarations'.length)
            : error.pointer;
        throw DartitectConfigException('$pointer$suffix', error.message);
      } on FormatException catch (error) {
        throw DartitectConfigException(pointer, error.message);
      }
    }
    return DartitectFeaturesConfig(declarations: declarations);
  }

  static DartitectStorageDatasetConfig? _parseStorageDataset(
    Object? value,
    String pointer,
  ) {
    if (value == null) return null;
    final object = _requiredObject(value, pointer);
    _rejectUnknown(object, const <String>{
      'dataset',
      'partition',
      'codec',
      'retention',
      'transactionBoundary',
    }, pointer);
    try {
      return DartitectStorageDatasetConfig(
        dataset: _requiredString(object, 'dataset', pointer),
        partition: _requiredString(object, 'partition', pointer),
        codec: _requiredString(object, 'codec', pointer),
        retention: _requiredString(object, 'retention', pointer),
        transactionBoundary: _requiredString(
          object,
          'transactionBoundary',
          pointer,
        ),
      );
    } on DartitectConfigException catch (error) {
      throw DartitectConfigException(
        error.pointer.replaceFirst('/features/declarations/dataset', pointer),
        error.message,
      );
    }
  }

  static DartitectFactorySourceConfig _parseFactorySource(
    Object? value,
    String pointer,
  ) {
    final object = _requiredObject(value, pointer);
    _rejectUnknown(object, const <String>{'source', 'declaration'}, pointer);
    try {
      return DartitectFactorySourceConfig(
        source: _requiredString(object, 'source', pointer),
        declaration: _requiredString(object, 'declaration', pointer),
      );
    } on DartitectConfigException catch (error) {
      throw DartitectConfigException(
        error.pointer.replaceFirst('/factorySource', pointer),
        error.message,
      );
    }
  }

  static List<DartitectOpenApiOperationConfig> _parseOperations(
    Object? value,
    String pointer,
  ) {
    if (value is! List<Object?>) {
      throw DartitectConfigException(pointer, 'expected an array');
    }
    return <DartitectOpenApiOperationConfig>[
      for (var index = 0; index < value.length; index += 1)
        _parseOperation(value[index], '$pointer/$index'),
    ];
  }

  static DartitectOpenApiOperationConfig _parseOperation(
    Object? value,
    String pointer,
  ) {
    final object = _requiredObject(value, pointer);
    _rejectUnknown(object, const <String>{'contract', 'operationId'}, pointer);
    try {
      return DartitectOpenApiOperationConfig(
        contract: _requiredString(object, 'contract', pointer),
        operationId: _requiredString(object, 'operationId', pointer),
      );
    } on DartitectConfigException catch (error) {
      throw DartitectConfigException(
        error.pointer.replaceFirst(
          '/features/declarations/operations',
          pointer,
        ),
        error.message,
      );
    }
  }

  static DartitectTargetsConfig _parseTargets(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/targets', 'expected an object');
    }
    _rejectUnknown(value, const <String>{'platforms'}, '/targets');
    return DartitectTargetsConfig(
      _parsePlatformList(value['platforms'], '/targets/platforms'),
    );
  }

  static Map<String, DartitectStorageContextConfig> _parseStorageContexts(
    Object? value,
  ) {
    final entries = _requiredObject(value, '/storageContexts');
    return <String, DartitectStorageContextConfig>{
      for (final entry in entries.entries)
        entry.key: _parseStorageContext(
          entry.value,
          '/storageContexts/${_pointerToken(entry.key)}',
        ),
    };
  }

  static DartitectStorageContextConfig _parseStorageContext(
    Object? value,
    String pointer,
  ) {
    final object = _requiredObject(value, pointer);
    _rejectUnknown(object, const <String>{
      'provider',
      'mode',
      'scope',
      'factorySource',
      'targets',
    }, pointer);
    final modeName = _requiredString(object, 'mode', pointer);
    final mode = DartitectStorageMode.values
        .where((candidate) => candidate.wireName == modeName)
        .firstOrNull;
    if (mode == null) {
      throw DartitectConfigException(
        '$pointer/mode',
        'expected durable or memory',
      );
    }
    try {
      return DartitectStorageContextConfig(
        provider: _requiredString(object, 'provider', pointer),
        mode: mode,
        scope: FeatureScope.parse(_requiredString(object, 'scope', pointer)),
        factorySource: _parseFactorySource(
          object['factorySource'],
          '$pointer/factorySource',
        ),
        targets: _parsePlatformList(object['targets'], '$pointer/targets'),
      );
    } on DartitectConfigException catch (error) {
      throw DartitectConfigException(
        error.pointer.replaceFirst('/storageContexts', pointer),
        error.message,
      );
    }
  }

  static Map<String, DartitectTransportConfig> _parseTransports(Object? value) {
    final entries = _requiredObject(value, '/transports');
    return <String, DartitectTransportConfig>{
      for (final entry in entries.entries)
        entry.key: _parseTransport(
          entry.value,
          '/transports/${_pointerToken(entry.key)}',
        ),
    };
  }

  static DartitectTransportConfig _parseTransport(
    Object? value,
    String pointer,
  ) {
    final object = _requiredObject(value, pointer);
    _rejectUnknown(object, const <String>{
      'provider',
      'scope',
      'factorySource',
      'targets',
    }, pointer);
    try {
      return DartitectTransportConfig(
        provider: _requiredString(object, 'provider', pointer),
        scope: FeatureScope.parse(_requiredString(object, 'scope', pointer)),
        factorySource: _parseFactorySource(
          object['factorySource'],
          '$pointer/factorySource',
        ),
        targets: _parsePlatformList(object['targets'], '$pointer/targets'),
      );
    } on DartitectConfigException catch (error) {
      throw DartitectConfigException(
        error.pointer.replaceFirst('/transports', pointer),
        error.message,
      );
    }
  }

  static Map<String, DartitectContractConfig> _parseContracts(Object? value) {
    final entries = _requiredObject(value, '/contracts');
    return <String, DartitectContractConfig>{
      for (final entry in entries.entries)
        entry.key: _parseContract(
          entry.value,
          '/contracts/${_pointerToken(entry.key)}',
        ),
    };
  }

  static DartitectContractConfig _parseContract(Object? value, String pointer) {
    final object = _requiredObject(value, pointer);
    _rejectUnknown(object, const <String>{
      'spec',
      'output',
      'transport',
    }, pointer);
    try {
      return DartitectContractConfig(
        spec: _requiredString(object, 'spec', pointer),
        output: _requiredString(object, 'output', pointer),
        transport: _requiredString(object, 'transport', pointer),
      );
    } on DartitectConfigException catch (error) {
      throw DartitectConfigException(
        error.pointer.replaceFirst('/contracts', pointer),
        error.message,
      );
    }
  }

  static DartitectSessionConfig? _parseSession(Object? value) {
    if (value == null) return null;
    final object = _requiredObject(value, '/session');
    _rejectUnknown(object, const <String>{'factorySource'}, '/session');
    return DartitectSessionConfig(
      factorySource: _parseFactorySource(
        object['factorySource'],
        '/session/factorySource',
      ),
    );
  }

  static DartitectObservabilityConfig _parseObservability(Object? value) {
    final object = _requiredObject(value, '/observability');
    _rejectUnknown(object, const <String>{
      'provider',
      'targets',
    }, '/observability');
    return DartitectObservabilityConfig(
      provider: _requiredString(object, 'provider', '/observability'),
      targets: object.containsKey('targets')
          ? _parsePlatformList(object['targets'], '/observability/targets')
          : const <DartitectPlatform>[],
    );
  }

  static DartitectSchedulerConfig _parseScheduler(Object? value) {
    final object = _requiredObject(value, '/scheduler');
    _rejectUnknown(object, const <String>{'provider', 'targets'}, '/scheduler');
    return DartitectSchedulerConfig(
      provider: _requiredString(object, 'provider', '/scheduler'),
      targets: object.containsKey('targets')
          ? _parsePlatformList(object['targets'], '/scheduler/targets')
          : const <DartitectPlatform>[],
    );
  }

  static List<String> _parseExtensionSources(Object? value) {
    if (value is! List<Object?>) {
      throw const DartitectConfigException(
        '/extensionSources',
        'expected an array',
      );
    }
    return <String>[
      for (var index = 0; index < value.length; index += 1)
        if (value[index] case final String source)
          _normalizeDartSource(source, '/extensionSources/$index')
        else
          throw DartitectConfigException(
            '/extensionSources/$index',
            'expected a string',
          ),
    ];
  }

  static List<DartitectPlatform> _parsePlatformList(
    Object? value,
    String pointer, {
    bool allowEmpty = false,
  }) {
    if (value is! List<Object?> || (!allowEmpty && value.isEmpty)) {
      throw DartitectConfigException(pointer, 'expected a non-empty array');
    }
    final output = <DartitectPlatform>[];
    for (var index = 0; index < value.length; index += 1) {
      final item = value[index];
      if (item is! String) {
        throw DartitectConfigException('$pointer/$index', 'expected a string');
      }
      try {
        final platform = DartitectPlatform.parse(item);
        if (!output.contains(platform)) output.add(platform);
      } on FormatException catch (error) {
        throw DartitectConfigException('$pointer/$index', error.message);
      }
    }
    return output;
  }

  static Map<String, Object?> _requiredObject(Object? value, String pointer) {
    if (value is! Map<String, Object?>) {
      throw DartitectConfigException(pointer, 'expected an object');
    }
    return value;
  }

  static List<String> _globList(Object? value, String pointer) {
    if (value is! List<Object?> || value.isEmpty) {
      throw DartitectConfigException(pointer, 'expected a non-empty array');
    }
    return <String>[
      for (var index = 0; index < value.length; index += 1)
        if (value[index] is String)
          _normalizeGlob(value[index]! as String, '$pointer/$index')
        else
          throw DartitectConfigException(
            '$pointer/$index',
            'expected a string',
          ),
    ];
  }

  static List<String> _suffixList(Object? value) {
    if (value is! List<Object?> || value.isEmpty) {
      throw const DartitectConfigException(
        '/generatedSuffixes',
        'expected a non-empty array',
      );
    }
    final output = <String>[];
    for (var index = 0; index < value.length; index += 1) {
      final raw = value[index];
      if (raw is! String ||
          !RegExp(
            r'^\.[a-z0-9_.-]+\.dart$',
            caseSensitive: false,
          ).hasMatch(raw) ||
          raw.contains('/') ||
          raw.contains('\\')) {
        throw DartitectConfigException(
          '/generatedSuffixes/$index',
          'expected a safe suffix such as .dartitect.g.dart',
        );
      }
      if (!output.contains(raw)) output.add(raw);
    }
    return output;
  }

  static int _requiredInt(
    Map<String, Object?> json,
    String key,
    String parent,
  ) {
    if (!json.containsKey(key)) {
      throw DartitectConfigException(
        '$parent/$key',
        'required field is missing',
      );
    }
    final value = json[key];
    if (value is! int) {
      throw DartitectConfigException('$parent/$key', 'expected an integer');
    }
    return value;
  }

  static String _requiredString(
    Map<String, Object?> json,
    String key,
    String parent,
  ) {
    if (!json.containsKey(key)) {
      throw DartitectConfigException(
        '$parent/$key',
        'required field is missing',
      );
    }
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw DartitectConfigException(
        '$parent/$key',
        'expected a non-empty string',
      );
    }
    return value.trim();
  }

  static String? _optionalString(
    Map<String, Object?> json,
    String key,
    String parent,
  ) {
    if (!json.containsKey(key)) return null;
    return _requiredString(json, key, parent);
  }

  static void _rejectUnknown(
    Map<String, Object?> json,
    Set<String> known,
    String parent,
  ) {
    for (final key in json.keys) {
      if (!known.contains(key)) {
        throw DartitectConfigException(
          '$parent/${_pointerToken(key)}',
          'unknown field in closed config v3 schema',
        );
      }
    }
  }

  static String _normalizeGlob(String value, String pointer) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized.split('/').contains('..')) {
      throw DartitectConfigException(
        pointer,
        'expected a safe project-relative glob',
      );
    }
    return normalized;
  }

  static Map<String, List<String>> _copyLayers(
    Map<String, List<String>> value,
  ) => Map<String, List<String>>.unmodifiable(<String, List<String>>{
    for (final entry in value.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  });
}

List<DartitectPlatform> _platformSet(
  Iterable<DartitectPlatform> targets,
  String pointer,
) {
  final output = _optionalPlatformSet(targets);
  if (output.isEmpty) {
    throw DartitectConfigException(pointer, 'expected at least one target');
  }
  return output;
}

List<DartitectPlatform> _optionalPlatformSet(
  Iterable<DartitectPlatform> targets,
) => List<DartitectPlatform>.unmodifiable(
  targets.toSet().toList()
    ..sort((left, right) => left.index.compareTo(right.index)),
);

Map<String, T> _sortedConfigMap<T>(Map<String, T> values) {
  final entries = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return Map<String, T>.unmodifiable(<String, T>{
    for (final entry in entries) entry.key: entry.value,
  });
}

String _normalizeDartSource(String value, String pointer) {
  final normalized = value.trim().replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.split('/').contains('..') ||
      !normalized.endsWith('.dart')) {
    throw DartitectConfigException(
      pointer,
      'expected a confined project-relative Dart source',
    );
  }
  return normalized;
}

String _normalizeProjectFile(String value, String pointer) {
  final normalized = value.trim().replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized
          .split('/')
          .any((segment) => segment.isEmpty || segment == '..')) {
    throw DartitectConfigException(
      pointer,
      'expected a confined project-relative file',
    );
  }
  return normalized;
}

String _normalizeGeneratedOutput(String value, String pointer) {
  final normalized = _normalizeProjectFile(value, pointer);
  if (!normalized.startsWith('lib/') ||
      !normalized.endsWith('.dartitect.g.dart')) {
    throw DartitectConfigException(
      pointer,
      'expected a manifest-owned lib/**/*.dartitect.g.dart output',
    );
  }
  return normalized;
}

T _enumByWireName<T extends Enum>(
  Iterable<T> values,
  String value,
  String description,
) {
  for (final candidate in values) {
    final wireName = switch (candidate) {
      final FeatureDiagnosticsLevel item => item.wireName,
      final FeatureScope item => item.wireName,
      final FeatureLocalAuthorityStrategy item => item.wireName,
      final DartitectPlatform item => item.wireName,
      final FeaturePagination item => item.wireName,
      final DartitectCapability item => item.wireName,
      _ => candidate.name,
    };
    if (wireName == value) return candidate;
  }
  throw FormatException('Unknown $description "$value".');
}

void _validateProviderIdentifier(
  String value, {
  required String pointer,
  required Set<String> builtIns,
}) {
  if (builtIns.contains(value)) return;
  if (!RegExp(r'^custom:[a-z][a-z0-9]*(?:-[a-z0-9]+)*$').hasMatch(value)) {
    final expected = <String>[...builtIns]..sort();
    throw DartitectConfigException(
      pointer,
      'expected ${expected.join('|')} or custom:<slug>',
    );
  }
}

String _pointerToken(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');

final RegExp _featureName = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');
final RegExp _configName = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
