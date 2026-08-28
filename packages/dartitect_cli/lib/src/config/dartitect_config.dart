import 'dart:convert';
import 'dart:io';

import '../rules/generated_boundary_policy.dart';

/// First stable on-disk Dartitect configuration version.
const int currentConfigVersion = 1;

/// Stable Native Strict profile identifier.
const String nativeStrictProfile = 'native_strict';

/// A validation failure with a JSON Pointer location.
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

/// Reviewed modeling adoption preset encoded inside stable config v1.
enum DartitectModelingPreset {
  /// Value semantics only; every other capability remains disabled.
  minimal('minimal'),

  /// Complete opt-in defaults for new Dartitect-owned models.
  recommended('recommended_complete'),

  /// Incremental adoption that tolerates existing project tooling.
  interop('interop_existing_project');

  const DartitectModelingPreset(this.wireName);

  /// Stable JSON name.
  final String wireName;

  /// Whether existing consumer-owned generators may coexist during adoption.
  bool get allowsExistingModelGenerators => this == interop;

  /// Capabilities suggested by this preset; annotations remain authoritative.
  List<String> get suggestedCapabilities => switch (this) {
    minimal => const <String>['value'],
    recommended => const <String>['value', 'json', 'projection', 'mapper'],
    interop => const <String>['value'],
  };
}

/// Public paved-road feature profiles.
enum FeatureProfile {
  /// Remote authority without durable local persistence.
  online('online'),

  /// Remote authority with a durable local cache.
  cache('cache'),

  /// Locally queryable synchronized replica.
  replica('replica'),

  /// Replica plus durable offline mutation delivery.
  offlineFull('offline-full');

  const FeatureProfile(this.wireName);

  /// Stable CLI and config spelling.
  final String wireName;

  /// Parses a public profile name.
  static FeatureProfile parse(String value) {
    for (final profile in values) {
      if (profile.wireName == value) return profile;
    }
    throw FormatException('Unknown feature profile "$value".');
  }
}

/// Closed generated diagnostics levels for feature wiring.
enum FeatureDiagnosticsLevel {
  /// No feature-level diagnostics wiring.
  off('off'),

  /// Lifecycle counters and closed events.
  basic('basic'),

  /// Full payload-free protocol instrumentation.
  full('full');

  const FeatureDiagnosticsLevel(this.wireName);

  /// Stable CLI and config spelling.
  final String wireName;

  /// Parses one supported diagnostics level.
  static FeatureDiagnosticsLevel parse(String value) {
    for (final level in values) {
      if (level.wireName == value) return level;
    }
    throw FormatException('Unknown feature diagnostics level "$value".');
  }
}

/// One declarative feature/provider compatibility record.
final class DartitectFeatureDeclaration {
  /// Creates and validates a declaration.
  DartitectFeatureDeclaration({
    required this.profile,
    required this.persistence,
    required this.transport,
    this.cursorPagination = false,
    this.headlessSync = false,
    this.diagnostics = FeatureDiagnosticsLevel.basic,
    Map<String, Object?> unknown = const <String, Object?>{},
  }) : unknown = Map<String, Object?>.unmodifiable(unknown) {
    _validateProvider(persistence, 'persistence');
    _validateProvider(transport, 'transport');
    if (profile == FeatureProfile.online && persistence != 'none') {
      throw const DartitectConfigException(
        '/features/declarations',
        'online profiles require persistence "none"',
      );
    }
    if (profile != FeatureProfile.online && persistence == 'none') {
      throw const DartitectConfigException(
        '/features/declarations',
        'cache, replica, and offline-full require persistence',
      );
    }
    if (transport == 'none') {
      throw const DartitectConfigException(
        '/features/declarations',
        'public paved-road profiles require a transport',
      );
    }
    if (headlessSync &&
        profile != FeatureProfile.replica &&
        profile != FeatureProfile.offlineFull) {
      throw const DartitectConfigException(
        '/features/declarations',
        'headless sync requires replica or offline-full',
      );
    }
  }

  /// Paved-road behavior profile.
  final FeatureProfile profile;

  /// Consumer-selected persistence provider or `none`.
  final String persistence;

  /// Consumer-selected transport provider.
  final String transport;

  /// Whether generated contracts include cursor pagination.
  final bool cursorPagination;

  /// Whether the feature declares headless sync execution.
  final bool headlessSync;

  /// Payload-free diagnostics wiring level.
  final FeatureDiagnosticsLevel diagnostics;

  /// Unknown declaration keys preserved after known fields validate.
  final Map<String, Object?> unknown;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile.wireName,
    'persistence': persistence,
    'transport': transport,
    'cursorPagination': cursorPagination,
    'headlessSync': headlessSync,
    'diagnostics': diagnostics.wireName,
    ...unknown,
  };

  static void _validateProvider(String value, String field) {
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(value)) {
      throw DartitectConfigException(
        '/features/declarations/$field',
        'expected a safe provider identifier',
      );
    }
  }
}

/// Additive stable-v1 feature declarations.
final class DartitectFeaturesConfig {
  /// Creates an immutable declaration registry.
  DartitectFeaturesConfig({
    Map<String, DartitectFeatureDeclaration> declarations =
        const <String, DartitectFeatureDeclaration>{},
    Map<String, Object?> unknown = const <String, Object?>{},
  }) : declarations = Map<String, DartitectFeatureDeclaration>.unmodifiable(
         declarations,
       ),
       unknown = Map<String, Object?>.unmodifiable(unknown) {
    for (final name in declarations.keys) {
      if (!RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(name)) {
        throw DartitectConfigException(
          '/features/declarations/$name',
          'expected an ASCII snake_case feature name',
        );
      }
    }
  }

  /// Feature declarations keyed by snake_case feature name.
  final Map<String, DartitectFeatureDeclaration> declarations;

  /// Unknown feature-section keys preserved after validation.
  final Map<String, Object?> unknown;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'declarations': <String, Object?>{
      for (final entry in declarations.entries) entry.key: entry.value.toJson(),
    },
    ...unknown,
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

  /// Adoption preset; annotations still control individual capabilities.
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

/// Additive ecosystem policy for incremental adoption.
final class DartitectEcosystemConfig {
  /// Creates an explicit ecosystem block.
  const DartitectEcosystemConfig({
    this.adoption = 'incremental',
    this.installedOverlap = 'warning',
  });

  /// Stable adoption mode.
  final String adoption;

  /// Disposition for an installed but non-leaking overlapping runtime.
  final String installedOverlap;

  /// Stable machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'adoption': adoption,
    'installedOverlap': installedOverlap,
  };
}

/// Stable v1 Native Strict configuration.
///
/// Experimental configuration versions are deliberately not migrated. A
/// consumer recreates this small file so compatibility begins at Dartitect
/// 1.0 rather than inheriting the pre-release schemas.
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
    Map<String, Object?> scaffolds = const <String, Object?>{
      'layout': 'feature_first',
      'blueprints': <String>[
        'simple',
        'remote-read',
        'local-first',
        'offline-mutation',
        'sync-dataset',
      ],
    },
    this.modeling,
    this.ecosystem,
    this.features,
    Map<String, Object?> unknown = const <String, Object?>{},
  }) : layers = _copyLayers(layers),
       compositionRoots = List<String>.unmodifiable(compositionRoots),
       generatedInfrastructure = List<String>.unmodifiable(
         generatedInfrastructure,
       ),
       generatedSuffixes = List<String>.unmodifiable(generatedSuffixes),
       suppressions = List<DartitectSuppression>.unmodifiable(suppressions),
       scaffolds = _copyScaffolds(scaffolds),
       unknown = Map<String, Object?>.unmodifiable(unknown) {
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
      'scaffolds',
      'modeling',
      'ecosystem',
      'features',
    };
    final version = _requiredInt(json, 'configVersion');
    if (version != currentConfigVersion) {
      throw DartitectConfigException(
        '/configVersion',
        'expected stable version $currentConfigVersion; experimental '
            'configurations are not migrated',
      );
    }
    final profile = _requiredString(json, 'profile');
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
      scaffolds: _parseScaffolds(json['scaffolds']),
      modeling: _parseModeling(json['modeling']),
      ecosystem: _parseEcosystem(json['ecosystem']),
      features: _parseFeatures(json['features']),
      unknown: <String, Object?>{
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
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

  /// Generated-once scaffold layout and supported blueprint selection.
  final Map<String, Object?> scaffolds;

  /// Optional modeling adoption. Absence preserves pre-RC4 consumers.
  final DartitectModelingConfig? modeling;

  /// Optional ecosystem coexistence policy.
  final DartitectEcosystemConfig? ecosystem;

  /// Optional paved-road feature declarations.
  final DartitectFeaturesConfig? features;

  /// Unknown keys retained only after the complete stable schema validates.
  final Map<String, Object?> unknown;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'configVersion': configVersion,
    'profile': profile,
    'layers': layers,
    'compositionRoots': compositionRoots,
    'generatedInfrastructure': generatedInfrastructure,
    'generatedSuffixes': generatedSuffixes,
    'suppressions': suppressions.map((value) => value.toJson()).toList(),
    'scaffolds': scaffolds,
    if (modeling != null) 'modeling': modeling!.toJson(),
    if (ecosystem != null) 'ecosystem': ecosystem!.toJson(),
    if (features != null) 'features': features!.toJson(),
    ...unknown,
  };

  /// Canonical two-space JSON with a trailing newline.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Reads and validates [file] without modifying it.
  static Future<DartitectConfig> load(File file) async =>
      DartitectConfig.parse(await file.readAsString());

  static int _requiredInt(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) {
      throw DartitectConfigException('/$key', 'required field is missing');
    }
    final value = json[key];
    if (value is! int) {
      throw DartitectConfigException('/$key', 'expected an integer');
    }
    return value;
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) {
      throw DartitectConfigException('/$key', 'required field is missing');
    }
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw DartitectConfigException('/$key', 'expected a non-empty string');
    }
    return value.trim();
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
          '/layers/${entry.key}',
          'invalid layer name',
        );
      }
      output[entry.key] = _globList(entry.value, '/layers/${entry.key}');
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
      String field(String key) {
        final result = raw[key];
        if (result is! String || result.trim().isEmpty) {
          throw DartitectConfigException(
            '$pointer/$key',
            'required non-empty string',
          );
        }
        return result.trim();
      }

      final code = field('code');
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
          path: _normalizeGlob(field('path'), '$pointer/path'),
          reason: field('reason'),
          owner: field('owner'),
          expiresAt: expiresAt,
          permanentJustification: permanent is String ? permanent.trim() : null,
        ),
      );
    }
    return output;
  }

  static Map<String, Object?> _parseScaffolds(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/scaffolds', 'expected an object');
    }
    if (value['layout'] != 'feature_first') {
      throw const DartitectConfigException(
        '/scaffolds/layout',
        'expected feature_first',
      );
    }
    final rawBlueprints = value['blueprints'];
    if (rawBlueprints is! List<Object?> || rawBlueprints.isEmpty) {
      throw const DartitectConfigException(
        '/scaffolds/blueprints',
        'expected a non-empty array',
      );
    }
    const supported = <String>{
      'simple',
      'remote-read',
      'local-first',
      'offline-mutation',
      'sync-dataset',
    };
    final blueprints = <String>[];
    for (var index = 0; index < rawBlueprints.length; index += 1) {
      final blueprint = rawBlueprints[index];
      if (blueprint is! String || !supported.contains(blueprint)) {
        throw DartitectConfigException(
          '/scaffolds/blueprints/$index',
          'unsupported blueprint',
        );
      }
      if (!blueprints.contains(blueprint)) blueprints.add(blueprint);
    }
    return <String, Object?>{
      'layout': 'feature_first',
      'blueprints': blueprints,
      for (final entry in value.entries)
        if (entry.key != 'layout' && entry.key != 'blueprints')
          entry.key: entry.value,
    };
  }

  static DartitectModelingConfig? _parseModeling(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/modeling', 'expected an object');
    }
    final presetValue = value['preset'];
    final preset = DartitectModelingPreset.values
        .where((candidate) => candidate.wireName == presetValue)
        .firstOrNull;
    if (preset == null) {
      throw const DartitectConfigException(
        '/modeling/preset',
        'expected minimal, recommended_complete, or interop_existing_project',
      );
    }
    final limits = value['jsonLimits'];
    if (limits is! Map<String, Object?>) {
      throw const DartitectConfigException(
        '/modeling/jsonLimits',
        'expected an object',
      );
    }
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

  static DartitectEcosystemConfig? _parseEcosystem(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/ecosystem', 'expected an object');
    }
    final adoption = value['adoption'];
    final overlap = value['installedOverlap'];
    if (adoption != 'incremental') {
      throw const DartitectConfigException(
        '/ecosystem/adoption',
        'expected incremental',
      );
    }
    if (overlap != 'warning') {
      throw const DartitectConfigException(
        '/ecosystem/installedOverlap',
        'expected warning',
      );
    }
    return const DartitectEcosystemConfig();
  }

  static DartitectFeaturesConfig? _parseFeatures(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw const DartitectConfigException('/features', 'expected an object');
    }
    final rawDeclarations = value['declarations'];
    if (rawDeclarations is! Map<String, Object?>) {
      throw const DartitectConfigException(
        '/features/declarations',
        'expected an object',
      );
    }
    final declarations = <String, DartitectFeatureDeclaration>{};
    for (final entry in rawDeclarations.entries) {
      final pointer = '/features/declarations/${entry.key}';
      final raw = entry.value;
      if (raw is! Map<String, Object?>) {
        throw DartitectConfigException(pointer, 'expected an object');
      }
      const known = <String>{
        'profile',
        'persistence',
        'transport',
        'cursorPagination',
        'headlessSync',
        'diagnostics',
      };
      String requiredString(String key) {
        final field = raw[key];
        if (field is! String || field.trim().isEmpty) {
          throw DartitectConfigException(
            '$pointer/$key',
            'expected a non-empty string',
          );
        }
        return field.trim();
      }

      bool boolean(String key, {bool defaultValue = false}) {
        final field = raw[key];
        if (field == null) return defaultValue;
        if (field is! bool) {
          throw DartitectConfigException('$pointer/$key', 'expected a boolean');
        }
        return field;
      }

      declarations[entry.key] = DartitectFeatureDeclaration(
        profile: FeatureProfile.parse(requiredString('profile')),
        persistence: requiredString('persistence'),
        transport: requiredString('transport'),
        cursorPagination: boolean('cursorPagination'),
        headlessSync: boolean('headlessSync'),
        diagnostics: raw['diagnostics'] == null
            ? FeatureDiagnosticsLevel.basic
            : FeatureDiagnosticsLevel.parse(requiredString('diagnostics')),
        unknown: <String, Object?>{
          for (final field in raw.entries)
            if (!known.contains(field.key)) field.key: field.value,
        },
      );
    }
    return DartitectFeaturesConfig(
      declarations: declarations,
      unknown: <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'declarations') entry.key: entry.value,
      },
    );
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
    if (value == null) {
      return DartitectArchitectureRules.defaultGeneratedSuffixes;
    }
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
          'expected a safe suffix such as .freezed.dart',
        );
      }
      if (!output.contains(raw)) output.add(raw);
    }
    return output;
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

  static Map<String, Object?> _copyScaffolds(Map<String, Object?> value) =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in value.entries)
          entry.key: entry.value is List<Object?>
              ? List<Object?>.unmodifiable(entry.value! as List<Object?>)
              : entry.value,
      });
}
