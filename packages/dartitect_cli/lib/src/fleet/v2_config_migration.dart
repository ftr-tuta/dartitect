import 'dart:convert';

import '../config/dartitect_config.dart';

/// Stable migration identity recorded by fleet preview/apply receipts.
const String dartitectV2ToV3MigrationId = 'config-v2-to-v3';

/// Deterministic config-v2 to config-v3 migration result.
final class DartitectV2ConfigMigration {
  /// Creates migration evidence.
  const DartitectV2ConfigMigration({
    required this.config,
    required this.changed,
    required this.manualActions,
  });

  /// Strict config-v3 result.
  final DartitectConfig config;

  /// Whether the source used config v2.
  final bool changed;

  /// Consumer-owned factory implementations that must exist before apply.
  final List<String> manualActions;

  /// Versioned migration identity, including when [changed] is false.
  String get migrationId => dartitectV2ToV3MigrationId;
}

/// Migrates the exact released config-v2 closure to config v3.
///
/// The transformation never invents domain behavior. It selects deterministic
/// factory source locations and reports them as manual actions; the semantic
/// factory compiler must validate those consumer-owned declarations before a
/// generation transaction may commit.
DartitectV2ConfigMigration migrateDartitectV2Config(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const DartitectConfigException('/', 'expected a JSON object');
  }
  if (decoded['configVersion'] == currentConfigVersion) {
    return DartitectV2ConfigMigration(
      config: DartitectConfig.fromJson(decoded),
      changed: false,
      manualActions: const <String>[],
    );
  }
  if (decoded['configVersion'] != 2 ||
      decoded['profile'] != nativeStrictProfile) {
    throw const DartitectConfigException(
      '/configVersion',
      'only exact stable config v2 or current config v3 can be migrated',
    );
  }
  const keys = <String>{
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
    'observability',
    'scheduler',
    'extensionSources',
  };
  final unknown = decoded.keys.toSet().difference(keys);
  if (unknown.isNotEmpty) {
    throw DartitectConfigException(
      '/${_pointer(unknown.first)}',
      'unknown config-v2 data cannot be represented in closed config v3',
    );
  }
  final manual = <String>{};
  final storage = _object(decoded['storageContexts'], '/storageContexts');
  for (final entry in storage.entries) {
    final value = _object(
      entry.value,
      '/storageContexts/${_pointer(entry.key)}',
    );
    const expected = <String>{'provider', 'mode', 'targets'};
    _requireExact(value, expected, '/storageContexts/${_pointer(entry.key)}');
    final path = 'lib/composition/contexts/${entry.key}_storage_factory.dart';
    value
      ..['scope'] = 'application'
      ..['factorySource'] = <String, Object?>{
        'source': path,
        'declaration': '${_pascal(entry.key)}StorageFactory',
      };
    manual.add(path);
  }
  final transports = _object(decoded['transports'], '/transports');
  for (final entry in transports.entries) {
    final value = _object(entry.value, '/transports/${_pointer(entry.key)}');
    const expected = <String>{'provider', 'targets'};
    _requireExact(value, expected, '/transports/${_pointer(entry.key)}');
    final path = 'lib/composition/contexts/${entry.key}_transport_factory.dart';
    value
      ..['scope'] = 'application'
      ..['factorySource'] = <String, Object?>{
        'source': path,
        'declaration': '${_pascal(entry.key)}TransportFactory',
      };
    manual.add(path);
  }
  final features = _object(decoded['features'], '/features');
  _requireExact(features, const <String>{'declarations'}, '/features');
  final declarations = _object(
    features['declarations'],
    '/features/declarations',
  );
  var needsSession = false;
  for (final entry in declarations.entries) {
    final pointer = '/features/declarations/${_pointer(entry.key)}';
    final value = _object(entry.value, pointer);
    const expected = <String>{
      'profile',
      'scope',
      'storageContext',
      'dataset',
      'transport',
      'targets',
      'pagination',
      'diagnostics',
      'headlessTargets',
      'capabilities',
    };
    final unknownFeature = value.keys.toSet().difference(expected);
    if (unknownFeature.isNotEmpty) {
      throw DartitectConfigException(
        '$pointer/${_pointer(unknownFeature.first)}',
        'unknown config-v2 feature data cannot be migrated',
      );
    }
    final featurePath =
        'lib/features/${entry.key}/composition/${entry.key}_factory.dart';
    value
      ..['factorySource'] = <String, Object?>{
        'source': featurePath,
        'declaration': '${_pascal(entry.key)}Factory',
      }
      ..['localAuthority'] = value['storageContext'] == null
          ? 'custom'
          : 'generated_pull'
      ..['operations'] = <Object?>[];
    manual.add(featurePath);
    needsSession = needsSession || value['scope'] == 'session';
  }
  decoded
    ..['configVersion'] = currentConfigVersion
    ..['contracts'] = <String, Object?>{};
  if (needsSession) {
    const path = 'lib/composition/session_factory.dart';
    decoded['session'] = <String, Object?>{
      'factorySource': <String, Object?>{
        'source': path,
        'declaration': 'SessionFactory',
      },
    };
    manual.add(path);
  }
  return DartitectV2ConfigMigration(
    config: DartitectConfig.fromJson(decoded),
    changed: true,
    manualActions: List<String>.unmodifiable(manual.toList()..sort()),
  );
}

Map<String, Object?> _object(Object? value, String pointer) {
  if (value is! Map<String, Object?>) {
    throw DartitectConfigException(pointer, 'expected an object');
  }
  return value;
}

void _requireExact(
  Map<String, Object?> value,
  Set<String> expected,
  String pointer,
) {
  final unknown = value.keys.toSet().difference(expected);
  final missing = expected.difference(value.keys.toSet());
  if (unknown.isNotEmpty) {
    throw DartitectConfigException(
      '$pointer/${_pointer(unknown.first)}',
      'unknown config-v2 field cannot be migrated',
    );
  }
  if (missing.isNotEmpty) {
    throw DartitectConfigException(
      '$pointer/${_pointer(missing.first)}',
      'required config-v2 field is missing',
    );
  }
}

String _pascal(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

String _pointer(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');
