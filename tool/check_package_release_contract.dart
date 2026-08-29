import 'dart:convert';
import 'dart:io';

/// Verifies package metadata, compatibility ranges, cohorts, and publication DAG.
void main(List<String> arguments) {
  try {
    final root = _root(arguments);
    final contract = _object(
      jsonDecode(
        File('${root.path}/tool/package_release_contract.json')
            .readAsStringSync(),
      ),
    );
    final errors = <String>[];
    if (contract['schemaVersion'] != 2 || contract['series'] != '1.0.x') {
      errors.add('Package release contract has an unsupported schema/series.');
    }
    final baseline = contract['baselineVersion'];
    final candidateTag = contract['candidateTag'];
    final declaredCount = contract['packageCount'];
    if (baseline is! String ||
        candidateTag != 'v$baseline' ||
        declaredCount is! int) {
      errors.add('Baseline, package count, or candidate tag is invalid.');
    }

    final compatibility = _objectOrNull(contract['compatibility']);
    final defaultRange = compatibility?['defaultRange'];
    final packageRanges = _objectOrNull(compatibility?['packageRanges']);
    if (defaultRange is! String ||
        packageRanges == null ||
        compatibility?['prereleaseBaselineRequired'] != true ||
        compatibility?['stableIndependentPatches'] != true ||
        compatibility?['stableDefaultRange'] != '>=1.0.0 <1.1.0') {
      errors.add('Compatibility policy is incomplete.');
    }
    final manifestPackages =
        _objectOrNull(contract['packages']) ?? const <String, Object?>{};
    final inventoryDecisions = _objectOrNull(contract['inventoryDecisions']);
    if (declaredCount is int && manifestPackages.length != declaredCount) {
      errors.add(
        'Package count is ${manifestPackages.length}; expected $declaredCount.',
      );
    }
    if (inventoryDecisions == null ||
        inventoryDecisions.keys
            .toSet()
            .difference(manifestPackages.keys.toSet())
            .isNotEmpty ||
        manifestPackages.keys
            .toSet()
            .difference(inventoryDecisions.keys.toSet())
            .isNotEmpty ||
        inventoryDecisions.values.any(
          (value) => value is! String || value.trim().isEmpty,
        )) {
      errors.add('Every package must have one inventory decision.');
    }

    final cohorts = _objectOrNull(contract['publicationCohorts']);
    const cohortNames = <String>{
      'foundation',
      'platformServices',
      'providerAdapters',
      'tooling',
      'leafUtilities',
    };
    if (cohorts == null ||
        cohorts.keys.toSet().difference(cohortNames).isNotEmpty ||
        cohortNames
            .difference(cohorts?.keys.toSet() ?? const <String>{})
            .isNotEmpty) {
      errors.add('Publication cohorts must define the five reviewed cohorts.');
    }
    final cohortPackages = <String>[
      if (cohorts != null)
        for (final name in cohortNames) ..._strings(cohorts[name], errors),
    ];
    if (cohortPackages.length != cohortPackages.toSet().length ||
        cohortPackages
            .toSet()
            .difference(manifestPackages.keys.toSet())
            .isNotEmpty ||
        manifestPackages.keys
            .toSet()
            .difference(cohortPackages.toSet())
            .isNotEmpty) {
      errors.add(
        'Every package must belong to exactly one publication cohort.',
      );
    }

    final layers = _layers(contract['publicationLayers'], errors);
    final order = _strings(contract['publicationOrder'], errors);
    final flattened = <String>[for (final layer in layers) ...layer];
    if (!_sameList(flattened, order)) {
      errors.add('Publication order must exactly flatten publication layers.');
    }
    if (order.toSet().length != order.length ||
        order.toSet().difference(manifestPackages.keys.toSet()).isNotEmpty ||
        manifestPackages.keys.toSet().difference(order.toSet()).isNotEmpty) {
      errors.add('Publication order must contain every package exactly once.');
    }
    _validatePolicy(contract, errors);

    final packages = <String, _Package>{};
    final packagesDirectory = Directory('${root.path}/packages');
    if (!packagesDirectory.existsSync()) {
      errors.add('Packages directory is missing.');
    } else {
      for (final entity in packagesDirectory.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final pubspec = File('${entity.path}/pubspec.yaml');
        if (!pubspec.existsSync()) continue;
        final source = pubspec.readAsStringSync();
        final name = _field(source, 'name');
        final version = _field(source, 'version');
        if (name == null || version == null) {
          errors.add('${entity.path} has no package name/version.');
          continue;
        }
        packages[name] = _Package(
          version: version,
          dependencies: _internalDependencies(source),
        );
        if (!source.contains('resolution: workspace')) {
          errors.add('$name must use workspace resolution.');
        }
        if (RegExp(
              r'^dependency_overrides:',
              multiLine: true,
            ).hasMatch(source) ||
            RegExp(r'^    path:', multiLine: true).hasMatch(source)) {
          errors.add('$name contains a forbidden override/path dependency.');
        }
        final changelog = File('${entity.path}/CHANGELOG.md');
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
    }

    if (packages.keys
            .toSet()
            .difference(manifestPackages.keys.toSet())
            .isNotEmpty ||
        manifestPackages.keys
            .toSet()
            .difference(packages.keys.toSet())
            .isNotEmpty) {
      errors.add('Workspace packages and release manifest packages differ.');
    }
    final positions = <String, int>{
      for (var index = 0; index < order.length; index += 1) order[index]: index,
    };
    final layerPositions = <String, int>{
      for (var index = 0; index < layers.length; index += 1)
        for (final package in layers[index]) package: index,
    };
    for (final entry in packages.entries) {
      final metadata = _objectOrNull(manifestPackages[entry.key]);
      if (metadata == null ||
          metadata['version'] != entry.value.version ||
          metadata['platforms'] is! List<Object?> ||
          metadata['stability'] is! String) {
        errors.add('${entry.key} does not match its release metadata.');
      }
      if (baseline is String &&
          baseline.contains('-') &&
          compatibility?['prereleaseBaselineRequired'] == true &&
          entry.value.version != baseline) {
        errors.add('${entry.key} must start from RC8 baseline $baseline.');
      }
      for (final dependency in entry.value.dependencies.entries) {
        final expected = packageRanges?[dependency.key] ?? defaultRange;
        if (dependency.value != expected) {
          errors.add(
            '${entry.key} -> ${dependency.key} uses ${dependency.value}; '
            'expected compatible range $expected.',
          );
        }
        final dependencyPosition = positions[dependency.key];
        final packagePosition = positions[entry.key];
        if (dependencyPosition == null ||
            packagePosition == null ||
            dependencyPosition >= packagePosition) {
          errors.add(
            'Publication order is not topological: '
            '${dependency.key} -> ${entry.key}.',
          );
        }
        final dependencyLayer = layerPositions[dependency.key];
        final packageLayer = layerPositions[entry.key];
        if (dependencyLayer == null ||
            packageLayer == null ||
            dependencyLayer >= packageLayer) {
          errors.add(
            'Publication layers are not topological: '
            '${dependency.key} -> ${entry.key}.',
          );
        }
      }
    }

    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Package release contract passed for ${packages.length} packages from '
      'baseline $baseline with compatible independent patch ranges.',
    );
  } on Object catch (error) {
    stderr.writeln('Package release contract could not be read: $error');
    exitCode = 1;
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

void _validatePolicy(Map<String, Object?> contract, List<String> errors) {
  final artifact = _objectOrNull(contract['artifactContract']);
  if (artifact == null ||
      artifact['cleanClone'] != true ||
      artifact['exactSourceSha'] != true ||
      artifact['trackedTreeClean'] != true ||
      artifact['pathDependencies'] != false ||
      artifact['dependencyOverrides'] != false ||
      artifact['digestAlgorithm'] != 'sha256') {
    errors.add('Artifact reproducibility policy is incomplete.');
  }
  final candidate = _objectOrNull(contract['gitCandidate']);
  if (candidate == null ||
      candidate['tag'] != contract['candidateTag'] ||
      candidate['materialized'] != false ||
      candidate['pubDevPublication'] != false) {
    errors.add('Candidate tag policy is incomplete.');
  }
  final partial = _objectOrNull(contract['partialFailurePolicy']);
  if (partial == null ||
      partial['automaticRetry'] != false ||
      partial['overwritePublishedVersion'] != false ||
      partial['resumeOnlyWithSameSourceAndDigests'] != true ||
      partial['changedArtifactRequiresNextCohort'] != true) {
    errors.add('Partial-publication recovery policy is incomplete.');
  }
}

List<List<String>> _layers(Object? value, List<String> errors) {
  if (value is! List<Object?>) {
    errors.add('Publication layers must be a list.');
    return const <List<String>>[];
  }
  return <List<String>>[for (final layer in value) _strings(layer, errors)];
}

List<String> _strings(Object? value, List<String> errors) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    errors.add('Expected a list of package names.');
    return const <String>[];
  }
  return value.cast<String>();
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

Map<String, Object?>? _objectOrNull(Object? value) =>
    value is Map<String, Object?> ? value : null;

String? _field(String source, String name) => RegExp(
  '^${RegExp.escape(name)}:\\s*([^\\s]+)',
  multiLine: true,
).firstMatch(source)?.group(1);

Map<String, String> _internalDependencies(String source) {
  final dependencies = <String, String>{};
  var active = false;
  for (final line in source.split(RegExp(r'\r?\n'))) {
    if (line == 'dependencies:') {
      active = true;
      continue;
    }
    if (active && line.isNotEmpty && !line.startsWith(' ')) break;
    if (!active) continue;
    final match = RegExp(
      r'''^  (dartitect(?:_[A-Za-z0-9_]+)?):\s*['"]?([^'"]+?)['"]?\s*$''',
    ).firstMatch(line);
    if (match != null) dependencies[match.group(1)!] = match.group(2)!;
  }
  return dependencies;
}

bool _sameList(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((same) => same);

final class _Package {
  const _Package({required this.version, required this.dependencies});

  final String version;
  final Map<String, String> dependencies;
}
