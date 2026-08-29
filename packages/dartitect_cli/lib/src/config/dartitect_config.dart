import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';

import '../rules/generated_boundary_policy.dart';

/// First stable on-disk Dartitect configuration version.
const int currentConfigVersion = 1;

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
    this.expiresAt,
    this.permanentJustification,
  });

  /// Stable `DTnnnn` code.
  final String code;

  /// Normalized project-relative glob.
  final String path;

  /// Reviewed reason.
  final String reason;

  /// Accountable owner.
  final String owner;

  /// Optional UTC expiry date.
  final DateTime? expiresAt;

  /// Required justification when the suppression is permanent.
  final String? permanentJustification;

  /// Whether this suppression is expired at [now].
  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !now.toUtc().isBefore(expiresAt!);

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'path': path,
    'reason': reason,
    'owner': owner,
    if (expiresAt != null)
      'expiresAt': expiresAt!.toIso8601String().substring(0, 10),
    if (permanentJustification != null)
      'permanentJustification': permanentJustification,
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

/// Native/web persistence selection for one feature.
final class FeaturePersistenceMatrix {
  /// Creates and validates a provider matrix.
  FeaturePersistenceMatrix({required this.native, required this.web}) {
    _validateProviderIdentifier(
      native,
      pointer: '/features/declarations/persistence/native',
      builtIns: _persistenceProviders,
    );
    _validateProviderIdentifier(
      web,
      pointer: '/features/declarations/persistence/web',
      builtIns: _persistenceProviders,
    );
    if (web == 'objectbox') {
      throw const DartitectConfigException(
        '/features/declarations/persistence/web',
        'ObjectBox is not implemented on web',
      );
    }
  }

  /// Provider for Android, iOS, macOS, Windows, and Linux.
  final String native;

  /// Provider for web.
  final String web;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'native': native,
    'web': web,
  };
}

/// One strict, executable feature declaration.
final class DartitectFeatureDeclaration {
  /// Creates and validates a declaration.
  DartitectFeatureDeclaration({
    required this.profile,
    required this.scope,
    required this.persistence,
    required this.transport,
    required this.pagination,
    required this.diagnostics,
    required Map<DartitectPlatform, bool> headless,
    Iterable<DartitectCapability> capabilities = const <DartitectCapability>[],
  }) : headless = Map<DartitectPlatform, bool>.unmodifiable(headless),
       capabilities = List<DartitectCapability>.unmodifiable(
         capabilities.toSet().toList()
           ..sort((left, right) => left.wireName.compareTo(right.wireName)),
       ) {
    _validateProviderIdentifier(
      transport,
      pointer: '/features/declarations/transport',
      builtIns: const <String>{'dio'},
    );
    final missing = DartitectPlatform.values.where(
      (platform) => !this.headless.containsKey(platform),
    );
    if (missing.isNotEmpty) {
      throw DartitectConfigException(
        '/features/declarations/headless',
        'missing platform ${missing.first.wireName}',
      );
    }
    if (profile == FeatureProfile.online) {
      if (persistence.native != 'none' || persistence.web != 'none') {
        throw const DartitectConfigException(
          '/features/declarations/persistence',
          'online profiles require persistence "none" on native and web',
        );
      }
    } else if (persistence.native == 'none' || persistence.web == 'none') {
      throw const DartitectConfigException(
        '/features/declarations/persistence',
        'cache, replica, and offline-full require persistence on native and web',
      );
    }
    if (this.headless.values.any((enabled) => enabled) &&
        profile != FeatureProfile.replica &&
        profile != FeatureProfile.offlineFull) {
      throw const DartitectConfigException(
        '/features/declarations/headless',
        'headless execution requires replica or offline-full',
      );
    }
  }

  /// Paved-road behavior profile.
  final FeatureProfile profile;

  /// Application or authenticated-session owner.
  final FeatureScope scope;

  /// Native/web persistence providers.
  final FeaturePersistenceMatrix persistence;

  /// `dio` or a `custom:<slug>` transport.
  final String transport;

  /// Pagination policy.
  final FeaturePagination pagination;

  /// Payload-free diagnostics wiring level.
  final FeatureDiagnosticsLevel diagnostics;

  /// Headless execution opt-in for every supported platform.
  final Map<DartitectPlatform, bool> headless;

  /// Independently opted-in stable workflows.
  final List<DartitectCapability> capabilities;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile.wireName,
    'scope': scope.wireName,
    'persistence': persistence.toJson(),
    'transport': transport,
    'pagination': pagination.wireName,
    'diagnostics': diagnostics.wireName,
    'headless': <String, Object?>{
      for (final platform in DartitectPlatform.values)
        platform.wireName: headless[platform]!,
    },
    'capabilities': capabilities
        .map((capability) => capability.wireName)
        .toList(),
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

/// Additive modeling configuration for stable config v1.
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

/// Stable v1 Native Strict configuration.
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
    Iterable<DartitectPlatform> platforms = DartitectPlatform.values,
    this.scheduler = 'none',
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : layers = _copyLayers(layers),
       compositionRoots = List<String>.unmodifiable(compositionRoots),
       generatedInfrastructure = List<String>.unmodifiable(
         generatedInfrastructure,
       ),
       generatedSuffixes = List<String>.unmodifiable(generatedSuffixes),
       suppressions = List<DartitectSuppression>.unmodifiable(suppressions),
       features = features ?? DartitectFeaturesConfig(),
       platforms = List<DartitectPlatform>.unmodifiable(
         platforms.toSet().toList()
           ..sort((left, right) => left.index.compareTo(right.index)),
       ),
       extensions = Map<String, Object?>.unmodifiable(extensions) {
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
    if (this.platforms.isEmpty) {
      throw const DartitectConfigException(
        '/platforms',
        'expected at least one supported platform',
      );
    }
    _validateProviderIdentifier(
      scheduler,
      pointer: '/scheduler',
      builtIns: const <String>{'none', 'workmanager'},
    );
    for (final namespace in this.extensions.keys) {
      if (!_extensionNamespace.hasMatch(namespace)) {
        throw DartitectConfigException(
          '/extensions/${_pointerToken(namespace)}',
          'expected a reverse-domain or slug namespace',
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

  /// Validates a decoded stable-v1 JSON object.
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
      'platforms',
      'scheduler',
      'extensions',
    };
    _rejectUnknown(json, known, '');
    final version = _requiredInt(json, 'configVersion', '');
    if (version != currentConfigVersion) {
      throw DartitectConfigException(
        '/configVersion',
        'expected stable version $currentConfigVersion; only fleet upgrade '
            'migrates an exact RC5 configuration',
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
      platforms: _parsePlatforms(json['platforms']),
      scheduler: _requiredString(json, 'scheduler', ''),
      extensions: _parseExtensions(json['extensions']),
    );
  }

  /// Stable schema version. The only accepted value is `1`.
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

  /// Closed application target platforms.
  final List<DartitectPlatform> platforms;

  /// `none`, `workmanager`, or `custom:<slug>`.
  final String scheduler;

  /// The only location where namespaced unknown data is preserved.
  final Map<String, Object?> extensions;

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
    'features': features.toJson(),
    'platforms': platforms.map((platform) => platform.wireName).toList(),
    'scheduler': scheduler,
    'extensions': extensions,
  };

  /// Canonical two-space JSON with a trailing newline.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Reads and validates [file] without modifying it.
  static Future<DartitectConfig> load(File file) async =>
      DartitectConfig.parse(await file.readAsString());

  void _validateImplementations() {
    for (final entry in features.declarations.entries) {
      final hasHeadless = entry.value.headless.values.any((value) => value);
      if (scheduler == 'none' && hasHeadless) {
        throw DartitectConfigException(
          '/features/declarations/${_pointerToken(entry.key)}/headless',
          'headless execution requires an implemented scheduler',
        );
      }
      if (scheduler != 'workmanager') continue;
      if (platforms.contains(DartitectPlatform.windows) &&
          entry.value.headless[DartitectPlatform.windows]!) {
        throw DartitectConfigException(
          '/features/declarations/${_pointerToken(entry.key)}/headless/windows',
          'workmanager is unsupported on Windows',
        );
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
      const known = <String>{
        'code',
        'path',
        'reason',
        'owner',
        'expiresAt',
        'permanentJustification',
      };
      _rejectUnknown(raw, known, pointer);
      final code = _requiredString(raw, 'code', pointer);
      if (!RegExp(r'^DT\d{4}$').hasMatch(code)) {
        throw DartitectConfigException(
          '$pointer/code',
          'expected DT followed by four digits',
        );
      }
      final expires = raw['expiresAt'];
      DateTime? expiresAt;
      if (expires != null) {
        if (expires is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expires)) {
          throw DartitectConfigException(
            '$pointer/expiresAt',
            'expected YYYY-MM-DD',
          );
        }
        expiresAt = DateTime.tryParse('${expires}T00:00:00Z');
        if (expiresAt == null) {
          throw DartitectConfigException('$pointer/expiresAt', 'invalid date');
        }
      }
      final permanent = raw['permanentJustification'];
      if (expiresAt == null &&
          (permanent is! String || permanent.trim().isEmpty)) {
        throw DartitectConfigException(
          '$pointer/permanentJustification',
          'required when expiresAt is absent',
        );
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
          permanentJustification: permanent is String ? permanent.trim() : null,
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
        'persistence',
        'transport',
        'pagination',
        'diagnostics',
        'headless',
        'capabilities',
      };
      _rejectUnknown(raw, known, pointer);
      final persistenceRaw = raw['persistence'];
      if (persistenceRaw is! Map<String, Object?>) {
        throw DartitectConfigException(
          '$pointer/persistence',
          'expected an object',
        );
      }
      _rejectUnknown(persistenceRaw, const <String>{
        'native',
        'web',
      }, '$pointer/persistence');
      final headlessRaw = raw['headless'];
      if (headlessRaw is! Map<String, Object?>) {
        throw DartitectConfigException(
          '$pointer/headless',
          'expected an object',
        );
      }
      final platformNames = DartitectPlatform.values
          .map((platform) => platform.wireName)
          .toSet();
      _rejectUnknown(headlessRaw, platformNames, '$pointer/headless');
      final headless = <DartitectPlatform, bool>{};
      for (final platform in DartitectPlatform.values) {
        final rawValue = headlessRaw[platform.wireName];
        if (rawValue is! bool) {
          throw DartitectConfigException(
            '$pointer/headless/${platform.wireName}',
            'expected a boolean',
          );
        }
        headless[platform] = rawValue;
      }
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
          persistence: FeaturePersistenceMatrix(
            native: _requiredString(
              persistenceRaw,
              'native',
              '$pointer/persistence',
            ),
            web: _requiredString(persistenceRaw, 'web', '$pointer/persistence'),
          ),
          transport: _requiredString(raw, 'transport', pointer),
          pagination: FeaturePagination.parse(
            _requiredString(raw, 'pagination', pointer),
          ),
          diagnostics: FeatureDiagnosticsLevel.parse(
            _requiredString(raw, 'diagnostics', pointer),
          ),
          headless: headless,
          capabilities: capabilities,
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

  static List<DartitectPlatform> _parsePlatforms(Object? value) {
    if (value is! List<Object?> || value.isEmpty) {
      throw const DartitectConfigException(
        '/platforms',
        'expected a non-empty array',
      );
    }
    final output = <DartitectPlatform>[];
    for (var index = 0; index < value.length; index += 1) {
      final item = value[index];
      if (item is! String) {
        throw DartitectConfigException(
          '/platforms/$index',
          'expected a string',
        );
      }
      try {
        final platform = DartitectPlatform.parse(item);
        if (!output.contains(platform)) output.add(platform);
      } on FormatException catch (error) {
        throw DartitectConfigException('/platforms/$index', error.message);
      }
    }
    return output;
  }

  static Map<String, Object?> _parseExtensions(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/extensions', 'expected an object');
    }
    return <String, Object?>{
      for (final entry in value.entries) entry.key: entry.value,
    };
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

  static void _rejectUnknown(
    Map<String, Object?> json,
    Set<String> known,
    String parent,
  ) {
    for (final key in json.keys) {
      if (!known.contains(key)) {
        throw DartitectConfigException(
          '$parent/${_pointerToken(key)}',
          'unknown field; extensions are allowed only under '
              '/extensions/<namespace>',
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

T _enumByWireName<T extends Enum>(
  Iterable<T> values,
  String value,
  String description,
) {
  for (final candidate in values) {
    final wireName = switch (candidate) {
      final FeatureDiagnosticsLevel item => item.wireName,
      final FeatureScope item => item.wireName,
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
final RegExp _extensionNamespace = RegExp(
  r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$',
);
const Set<String> _persistenceProviders = <String>{
  'none',
  'memory',
  'drift',
  'objectbox',
};

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
