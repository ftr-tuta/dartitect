import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'release_contract.dart';

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
    final cohorts = ReleaseCohortContract.read(root);
    final errors = <String>[];
    const forbiddenLegacyFields = <String>{
      'compatibility',
      'internalDependency',
      'publicationCohorts',
      'publicationLayers',
      'publicationOrder',
      'partialFailurePolicy',
      'releaseTag',
      'releaseVersion',
    };
    if (contract['schemaVersion'] != 4 || contract['series'] != '1.x') {
      errors.add('Package release contract has an unsupported schema/series.');
    }
    if (contract.keys.toSet().intersection(forbiddenLegacyFields).isNotEmpty) {
      errors.add('Independent-patch or registry-publication fields remain.');
    }

    final version = cohorts.workspace.version;
    final tag = cohorts.workspace.tag;
    final distributedVersion = cohorts.distributed.version;
    final distributedTag = cohorts.distributed.tag;
    final declaredCount = contract['packageCount'];
    if (cohorts.workspace.semanticVersion.major != 1 ||
        tag != 'v$version' ||
        declaredCount is! int) {
      errors.add(
        'Workspace version, derived tag, or package count is invalid.',
      );
    }
    final expectedChannel = cohorts.workspace.isPrerelease
        ? 'candidate'
        : 'stable';
    if (cohorts.workspace.channel != expectedChannel ||
        (cohorts.workspace.isPrerelease && cohorts.workspace.tagMaterialized)) {
      errors.add('Workspace channel or tag materialization is invalid.');
    }
    if (cohorts.distributed.semanticVersion.major != 1 ||
        cohorts.distributed.isPrerelease ||
        cohorts.distributed.channel != 'stable' ||
        distributedTag != 'v$distributedVersion' ||
        !cohorts.distributed.available ||
        cohorts.workspace.semanticVersion.compareTo(
              cohorts.distributed.semanticVersion,
            ) <
            0) {
      errors.add('Distributed stable cohort is invalid.');
    }
    final lockstep = _objectOrNull(contract['lockstep']);
    if (lockstep == null ||
        lockstep['enabled'] != true ||
        lockstep['version'] != version ||
        lockstep['derivedTag'] != tag ||
        lockstep['futurePatchRule'] is! String) {
      errors.add('Permanent lockstep policy is incomplete.');
    }
    _validateDependency(
      contract['workspaceInternalDependency'],
      version,
      errors,
      'Workspace',
    );
    _validateDependency(
      contract['distributedInternalDependency'],
      distributedVersion,
      errors,
      'Distributed',
    );
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
    final changelogsWithUnreleased = <String>{};
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
      final changelogSource = changelog.existsSync()
          ? changelog.readAsStringSync()
          : '';
      final changelogLines = changelogSource.split(RegExp(r'\r?\n'));
      if (changelogLines.isEmpty || changelogLines.first != '# Changelog') {
        errors.add('$name changelog must begin with "# Changelog".');
      }
      final headings = RegExp(
        r'^##\s+([^\s]+)',
        multiLine: true,
      ).allMatches(changelogSource).map((match) => match.group(1)!).toList();
      if (headings.isNotEmpty && headings.first == 'Unreleased') {
        changelogsWithUnreleased.add(name);
        final body = _changelogSection(changelogLines, '## Unreleased');
        if (body.isEmpty) {
          errors.add('$name changelog has an empty Unreleased section.');
        }
      }
      final firstRelease = headings.where(_isNumberedVersion).firstOrNull;
      if (firstRelease != distributedVersion) {
        errors.add(
          '$name changelog first numbered version must be '
          '$distributedVersion.',
        );
      }
    }

    if (changelogsWithUnreleased.length != manifestNames.length) {
      errors.add(
        'Unreleased changelog cohort is partial: '
        '${changelogsWithUnreleased.length}/${manifestNames.length}.',
      );
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
    _validateArtifactPolicy(contract, cohorts, errors);
    _validateVersionSources(root, contract, errors);

    if (errors.isNotEmpty) {
      stderr.writeln(errors.toSet().join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Package release contract passed for ${packages.length} packages in '
      'the permanent $version workspace lockstep cohort; stable distribution '
      'remains $distributedTag.',
    );
  } on Object catch (error) {
    stderr.writeln('Package release contract could not be read: $error');
    exitCode = 1;
  }
}

void _validateVersionSources(
  Directory root,
  Map<String, Object?> contract,
  List<String> errors,
) {
  final sources = _objectOrNull(contract['workspaceVersionSources']);
  if (sources == null ||
      sources.keys.toSet().difference(const <String>{
        'manifests',
        'nativeManifests',
        'structuredDerivatives',
      }).isNotEmpty) {
    errors.add('Workspace version source inventory is invalid.');
    return;
  }
  final paths = <String>[];
  for (final key in const <String>[
    'manifests',
    'nativeManifests',
    'structuredDerivatives',
  ]) {
    final value = sources[key];
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      errors.add('Workspace version source list $key is invalid.');
      continue;
    }
    paths.addAll(value.cast<String>());
  }
  if (paths.length != paths.toSet().length ||
      paths.any(
        (path) =>
            path.startsWith('/') ||
            path.split('/').contains('..') ||
            path.startsWith('docs/'),
      )) {
    errors.add('Workspace version sources must be unique and current-only.');
  }
  for (final path in paths) {
    if (!File('${root.path}/$path').existsSync()) {
      errors.add('Workspace version source is missing: $path.');
    }
  }
}

void _validateArtifactPolicy(
  Map<String, Object?> contract,
  ReleaseCohortContract cohorts,
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
      release['tag'] != cohorts.distributed.tag ||
      release['materialized'] != cohorts.distributed.available ||
      release['annotated'] != true ||
      release['signed'] != false ||
      release['transitiveOverrides'] != false ||
      release['registryPublication'] != false ||
      release['immutable'] != true) {
    errors.add('Git release policy is incomplete.');
  }
}

void _validateDependency(
  Object? value,
  String version,
  List<String> errors,
  String label,
) {
  final dependency = _objectOrNull(value);
  if (dependency == null ||
      dependency['url'] != 'https://github.com/ftr-tuta/dartitect.git' ||
      dependency['pathPrefix'] != 'packages/' ||
      dependency['tagPattern'] != 'v{{version}}' ||
      dependency['version'] != version) {
    errors.add('$label internal dependency contract is invalid.');
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

bool _isNumberedVersion(String value) =>
    RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(value);

String _changelogSection(List<String> lines, String heading) {
  final start = lines.indexOf(heading);
  if (start < 0) return '';
  final body = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ')) break;
    if (line.trim().isNotEmpty) body.add(line.trim());
  }
  return body.join('\n');
}

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;

final class _Package {
  const _Package(this.dependencies);

  final Set<String> dependencies;
}
