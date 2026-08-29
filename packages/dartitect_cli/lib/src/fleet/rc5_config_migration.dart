import 'dart:convert';

import '../config/dartitect_config.dart';
import '../rules/generated_boundary_policy.dart';

/// Exact, one-way config-v1 migration result from RC5 to RC6.
final class DartitectRc5ConfigMigration {
  /// Creates a migration result.
  const DartitectRc5ConfigMigration({
    required this.config,
    required this.changed,
  });

  /// Strict RC6 configuration.
  final DartitectConfig config;

  /// Whether the input used the exact RC5 representation.
  final bool changed;
}

/// Migrates only the released RC5 config-v1 representation.
///
/// Already-strict RC6 input is validated and returned unchanged. No other
/// legacy or experimental representation is accepted.
DartitectRc5ConfigMigration migrateExactRc5Config(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const DartitectConfigException('/', 'expected a JSON object');
  }
  final appearsRc5 =
      decoded.containsKey('scaffolds') ||
      decoded.containsKey('ecosystem') ||
      _containsRc5Feature(decoded['features']);
  if (!appearsRc5) {
    return DartitectRc5ConfigMigration(
      config: DartitectConfig.fromJson(decoded),
      changed: false,
    );
  }
  if (decoded['configVersion'] != 1 ||
      decoded['profile'] != nativeStrictProfile) {
    throw const DartitectConfigException(
      '/profile',
      'only exact RC5 native_strict config-v1 can be migrated',
    );
  }
  const rc5Keys = <String>{
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
  final unknownRoot = <String, Object?>{
    for (final entry in decoded.entries)
      if (!rc5Keys.contains(entry.key)) entry.key: entry.value,
  };
  _validateRc5Scaffolds(decoded['scaffolds']);
  _validateRc5Ecosystem(decoded['ecosystem']);
  final migratedFeatures = _migrateFeatures(decoded['features']);
  final hasHeadless = migratedFeatures.values.any((feature) {
    final declaration = feature! as Map<String, Object?>;
    final headless = declaration['headless']! as Map<String, Object?>;
    return headless.values.any((enabled) => enabled == true);
  });
  final extensions = <String, Object?>{};
  if (unknownRoot.isNotEmpty) {
    extensions['dartitect.rc5'] = <String, Object?>{'unknownRoot': unknownRoot};
  }
  final strict = <String, Object?>{
    'configVersion': 1,
    'profile': nativeStrictProfile,
    'layers': decoded['layers'],
    'compositionRoots': decoded['compositionRoots'],
    'generatedInfrastructure': decoded['generatedInfrastructure'],
    'generatedSuffixes':
        decoded['generatedSuffixes'] ??
        DartitectArchitectureRules.defaultGeneratedSuffixes,
    'suppressions': decoded['suppressions'] ?? const <Object?>[],
    if (decoded['modeling'] != null) 'modeling': decoded['modeling'],
    'features': <String, Object?>{'declarations': migratedFeatures},
    'platforms': DartitectPlatform.values
        .map((platform) => platform.wireName)
        .toList(),
    'scheduler': hasHeadless ? 'workmanager' : 'none',
    'extensions': extensions,
  };
  return DartitectRc5ConfigMigration(
    config: DartitectConfig.fromJson(strict),
    changed: true,
  );
}

bool _containsRc5Feature(Object? features) {
  if (features is! Map<String, Object?>) return false;
  final declarations = features['declarations'];
  if (declarations is! Map<String, Object?>) return false;
  return declarations.values.any(
    (value) =>
        value is Map<String, Object?> &&
        (value.containsKey('cursorPagination') ||
            value.containsKey('headlessSync') ||
            value['persistence'] is String),
  );
}

void _validateRc5Scaffolds(Object? value) {
  if (value == null) return;
  if (value is! Map<String, Object?> ||
      value.keys.toSet().difference(const <String>{
        'layout',
        'blueprints',
      }).isNotEmpty ||
      value['layout'] != 'feature_first' ||
      value['blueprints'] is! List<Object?>) {
    throw const DartitectConfigException(
      '/scaffolds',
      'expected the exact released RC5 scaffold declaration',
    );
  }
  const aliases = <String>{
    'simple',
    'remote-read',
    'local-first',
    'offline-mutation',
    'sync-dataset',
  };
  final values = value['blueprints']! as List<Object?>;
  if (values.any((item) => item is! String || !aliases.contains(item))) {
    throw const DartitectConfigException(
      '/scaffolds/blueprints',
      'expected only released RC5 blueprint aliases',
    );
  }
}

void _validateRc5Ecosystem(Object? value) {
  if (value == null) return;
  if (value is! Map<String, Object?> ||
      value.keys.toSet().difference(const <String>{
        'adoption',
        'installedOverlap',
      }).isNotEmpty ||
      value['adoption'] != 'incremental' ||
      value['installedOverlap'] != 'warning') {
    throw const DartitectConfigException(
      '/ecosystem',
      'expected the exact released RC5 ecosystem declaration',
    );
  }
}

Map<String, Object?> _migrateFeatures(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is! Map<String, Object?> ||
      value['declarations'] is! Map<String, Object?>) {
    throw const DartitectConfigException(
      '/features/declarations',
      'expected the exact released RC5 feature registry',
    );
  }
  final unknownFeatureRegistry = value.keys.toSet().difference(const <String>{
    'declarations',
  });
  if (unknownFeatureRegistry.isNotEmpty) {
    throw DartitectConfigException(
      '/features/${_pointer(unknownFeatureRegistry.first)}',
      'RC5 feature-registry extensions cannot be migrated safely',
    );
  }
  final output = <String, Object?>{};
  final declarations = value['declarations']! as Map<String, Object?>;
  for (final entry in declarations.entries) {
    final pointer = '/features/declarations/${_pointer(entry.key)}';
    final raw = entry.value;
    if (raw is! Map<String, Object?>) {
      throw DartitectConfigException(pointer, 'expected an object');
    }
    const keys = <String>{
      'profile',
      'persistence',
      'transport',
      'cursorPagination',
      'headlessSync',
      'diagnostics',
    };
    final unknown = raw.keys.toSet().difference(keys);
    if (unknown.isNotEmpty) {
      throw DartitectConfigException(
        '$pointer/${_pointer(unknown.first)}',
        'RC5 feature extensions cannot be migrated safely',
      );
    }
    final profile = raw['profile'];
    final persistence = raw['persistence'];
    final transport = raw['transport'];
    final pagination = raw['cursorPagination'] ?? false;
    final headless = raw['headlessSync'] ?? false;
    final diagnostics = raw['diagnostics'] ?? 'basic';
    if (profile is! String ||
        persistence is! String ||
        transport is! String ||
        pagination is! bool ||
        headless is! bool ||
        diagnostics is! String) {
      throw DartitectConfigException(pointer, 'invalid exact RC5 declaration');
    }
    output[entry.key] = <String, Object?>{
      'profile': profile,
      'scope': 'application',
      'persistence': <String, Object?>{
        'native': persistence,
        'web': persistence == 'objectbox' ? 'memory' : persistence,
      },
      'transport': transport,
      'pagination': pagination ? 'cursor' : 'none',
      'diagnostics': diagnostics,
      'headless': <String, Object?>{
        for (final platform in DartitectPlatform.values)
          platform.wireName: headless && platform != DartitectPlatform.windows,
      },
      'capabilities': <Object?>[],
    };
  }
  return output;
}

String _pointer(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');
