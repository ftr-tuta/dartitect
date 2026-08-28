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
