import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Verifies the permanent lockstep cohort, package paths, and dependency order.
void main(List<String> arguments) {
  try {
    final root = _root(arguments);
    final contract = _jsonObject(
      jsonDecode(
        File('${root.path}/tool/package_release_contract.json')
            .readAsStringSync(),
      ),
    );
    final errors = <String>[];
    const forbiddenLegacyFields = <String>{
      'compatibility',
      'publicationCohorts',
      'publicationLayers',
      'publicationOrder',
      'partialFailurePolicy',
    };
    if (contract['schemaVersion'] != 3 || contract['series'] != '1.x') {
      errors.add('Package release contract has an unsupported schema/series.');
    }
    if (contract.keys.toSet().intersection(forbiddenLegacyFields).isNotEmpty) {
      errors.add('Independent-patch or registry-publication fields remain.');
    }

    final version = contract['releaseVersion'];
    final tag = contract['releaseTag'];
    final declaredCount = contract['packageCount'];
    if (version != '1.0.0' || tag != 'v$version' || declaredCount is! int) {
      errors.add('Release version, tag, or package count is invalid.');
    }
    final lockstep = _objectOrNull(contract['lockstep']);
    if (lockstep == null ||
        lockstep['enabled'] != true ||
        lockstep['version'] != version ||
        lockstep['tag'] != tag ||
        lockstep['futurePatchRule'] is! String) {
      errors.add('Permanent lockstep policy is incomplete.');
    }
    final distribution = _objectOrNull(contract['distribution']);
    if (distribution == null ||
        distribution['kind'] != 'github-release' ||
        distribution['packageSource'] != 'git' ||
        distribution['registryPublication'] != false ||
        distribution['annotatedTag'] != true ||
        distribution['immutableRelease'] != true) {
      errors.add('GitHub-only distribution policy is incomplete.');
    }

    final manifestPackages =
        _objectOrNull(contract['packages']) ?? const <String, Object?>{};
    final packagePaths =
        _objectOrNull(contract['packagePaths']) ?? const <String, Object?>{};
    final inventoryDecisions =
        _objectOrNull(contract['inventoryDecisions']) ??
        const <String, Object?>{};
    final order = _strings(contract['dependencyOrder'], errors);
    final manifestNames = manifestPackages.keys.toSet();
    if (declaredCount is int && manifestNames.length != declaredCount) {
      errors.add(
        'Package count is ${manifestNames.length}; expected $declaredCount.',
      );
    }
    for (final inventory in <Map<String, Object?>>[
      packagePaths,
      inventoryDecisions,
    ]) {
      if (inventory.keys.toSet().difference(manifestNames).isNotEmpty ||
          manifestNames.difference(inventory.keys.toSet()).isNotEmpty) {
        errors.add('Release inventories must contain the same package set.');
      }
    }
    if (order.length != order.toSet().length ||
        order.toSet().difference(manifestNames).isNotEmpty ||
        manifestNames.difference(order.toSet()).isNotEmpty) {
      errors.add('Dependency order must contain every package exactly once.');
    }

    final packages = <String, _Package>{};
    for (final entry in packagePaths.entries) {
      final name = entry.key;
      final path = entry.value;
      if (path != 'packages/$name') {
        errors.add('$name has non-canonical package path $path.');
        continue;
      }
      final pubspec = File('${root.path}/$path/pubspec.yaml');
      if (!pubspec.existsSync()) {
        errors.add('$name pubspec is missing at $path.');
        continue;
      }
      final yaml = _yamlObject(loadYaml(pubspec.readAsStringSync()));
      final actualName = yaml['name'];
      final actualVersion = yaml['version'];
      if (actualName != name || actualVersion != version) {
        errors.add('$name must declare the lockstep version $version.');
      }
      final dependencies = <String>{};
      for (final sectionName in const <String>[
        'dependencies',
        'dev_dependencies',
      ]) {
        final section = _yamlObjectOrNull(yaml[sectionName]);
        if (section == null) continue;
        dependencies.addAll(section.keys.where(_isDartitectPackage));
      }
      packages[name] = _Package(dependencies);

      final metadata = _objectOrNull(manifestPackages[name]);
      if (metadata == null ||
          metadata['version'] != version ||
          metadata['platforms'] is! List<Object?> ||
          !'${metadata['stability']}'.startsWith('stable')) {
        errors.add('$name does not match its stable release metadata.');
      }
      final changelog = File('${root.path}/$path/CHANGELOG.md');
      final firstRelease = changelog.existsSync()
          ? RegExp(
              r'^##\s+([^\s]+)',
              multiLine: true,
            ).firstMatch(changelog.readAsStringSync())?.group(1)
          : null;
      if (firstRelease != version) {
        errors.add('$name changelog does not begin with version $version.');
      }
    }

    final actualPackageNames = Directory('${root.path}/packages')
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where(
          (directory) => File('${directory.path}/pubspec.yaml').existsSync(),
        )
        .map((directory) => _basename(directory.path))
        .toSet();
    if (actualPackageNames.difference(manifestNames).isNotEmpty ||
        manifestNames.difference(actualPackageNames).isNotEmpty) {
      errors.add('Workspace packages and release manifest packages differ.');
    }

    final positions = <String, int>{
      for (var index = 0; index < order.length; index += 1) order[index]: index,
    };
    for (final entry in packages.entries) {
      for (final dependency in entry.value.dependencies) {
        if (!manifestNames.contains(dependency)) {
          errors.add('${entry.key} references unknown package $dependency.');
          continue;
        }
        if ((positions[dependency] ?? order.length) >=
            (positions[entry.key] ?? -1)) {
          errors.add(
            'Dependency order is not topological: $dependency -> ${entry.key}.',
          );
        }
      }
    }
    _validateArtifactPolicy(contract, errors);

    if (errors.isNotEmpty) {
      stderr.writeln(errors.toSet().join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Package release contract passed for ${packages.length} packages in '
      'the permanent $version GitHub-only lockstep cohort.',
    );
  } on Object catch (error) {
    stderr.writeln('Package release contract could not be read: $error');
    exitCode = 1;
  }
}

void _validateArtifactPolicy(
  Map<String, Object?> contract,
  List<String> errors,
) {
  final artifact = _objectOrNull(contract['artifactContract']);
  if (artifact == null ||
      artifact['cleanClone'] != true ||
      artifact['exactSourceSha'] != true ||
      artifact['trackedTreeClean'] != true ||
      artifact['internalPathDependencies'] != false ||
      artifact['dependencyOverrides'] != false ||
      artifact['digestAlgorithm'] != 'sha256') {
    errors.add('Artifact reproducibility policy is incomplete.');
  }
  final release = _objectOrNull(contract['gitRelease']);
  if (release == null ||
      release['tag'] != contract['releaseTag'] ||
      release['annotated'] != true ||
      release['signed'] != false ||
      release['transitiveOverrides'] != false ||
      release['registryPublication'] != false ||
      release['immutable'] != true) {
    errors.add('Git release policy is incomplete.');
  }
}

Directory _root(List<String> arguments) {
  if (arguments.isEmpty) {
    return File.fromUri(Platform.script).parent.parent.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments[1]).absolute;
  }
  throw const FormatException(
    'Usage: dart run tool/check_package_release_contract.dart [--root PATH]',
  );
}

List<String> _strings(Object? value, List<String> errors) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    errors.add('Expected a list of package names.');
    return const <String>[];
  }
  return value.cast<String>();
}

Map<String, Object?> _jsonObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

Map<String, Object?>? _objectOrNull(Object? value) =>
    value is Map<String, Object?> ? value : null;

Map<String, Object?> _yamlObject(Object? value) {
  final result = _yamlObjectOrNull(value);
  if (result == null) throw const FormatException('Expected a YAML map.');
  return result;
}

Map<String, Object?>? _yamlObjectOrNull(Object? value) {
  if (value is! Map<Object?, Object?>) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key! as String] = entry.value;
  }
  return result;
}

bool _isDartitectPackage(String name) =>
    RegExp(r'^dartitect(?:_[a-z0-9_]+)?$').hasMatch(name);

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;

final class _Package {
  const _Package(this.dependencies);

  final Set<String> dependencies;
}
