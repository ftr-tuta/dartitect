import 'dart:convert';
import 'dart:io';

/// Verifies lockstep versions, internal constraints, and publication order.
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
    if (contract['schemaVersion'] != 1 || contract['series'] != '1.0.x') {
      errors.add('Package release contract has an unsupported schema/series.');
    }
    final cohort = contract['cohortVersion'];
    final constraint = contract['internalConstraint'];
    if (cohort is! String || constraint is! String) {
      errors.add('Package release cohort and constraint must be strings.');
    }
    final expectedConstraint = cohort is String
        ? _constraintFor(cohort, errors)
        : null;
    if (expectedConstraint != null && constraint != expectedConstraint) {
      errors.add(
        'Internal constraint is $constraint; expected $expectedConstraint.',
      );
    }

    final layers = _layers(contract['publicationLayers'], errors);
    final order = _strings(contract['publicationOrder'], errors);
    final flattened = <String>[for (final layer in layers) ...layer];
    if (!_sameList(flattened, order)) {
      errors.add('Publication order must exactly flatten publication layers.');
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
          errors.add('$name changelog does not begin with cohort $version.');
        }
      }
    }

    final names = packages.keys.toSet();
    if (names.length != order.length || !names.containsAll(order)) {
      errors.add('Publication order does not contain every package exactly.');
    }
    if (order.toSet().length != order.length) {
      errors.add('Publication order contains duplicate packages.');
    }
    final positions = <String, int>{
      for (var index = 0; index < order.length; index += 1) order[index]: index,
    };
    final layerPositions = <String, int>{
      for (var index = 0; index < layers.length; index += 1)
        for (final package in layers[index]) package: index,
    };
    for (final entry in packages.entries) {
      if (entry.value.version != cohort) {
        errors.add(
          '${entry.key} is ${entry.value.version}; expected cohort $cohort.',
        );
      }
      for (final dependency in entry.value.dependencies.entries) {
        if (dependency.value != constraint) {
          errors.add(
            '${entry.key} -> ${dependency.key} uses ${dependency.value}; '
            'expected $constraint.',
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
      'Package release contract passed for ${packages.length} packages at '
      '$cohort in topological order.',
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

String? _constraintFor(String version, List<String> errors) {
  if (RegExp(r'^1\.0\.0-(?:dev|rc)\.[1-9][0-9]*$').hasMatch(version)) {
    return '>=$version <1.0.0';
  }
  if (RegExp(r'^1\.0\.(?:0|[1-9][0-9]*)$').hasMatch(version)) {
    return '>=$version <1.1.0';
  }
  errors.add('Unsupported lockstep cohort version: $version.');
  return null;
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
