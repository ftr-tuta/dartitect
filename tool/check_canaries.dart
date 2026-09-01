import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Validates the source contract used by the annotated-tag Git canaries.
void main(List<String> arguments) {
  try {
    if (arguments.isNotEmpty &&
        !(arguments.length == 1 && arguments.single == '--validate-only')) {
      throw const FormatException(
        'Usage: dart run tool/check_canaries.dart [--validate-only]',
      );
    }
    final root = File.fromUri(Platform.script).parent.parent.absolute;
    final contract = _object(
      jsonDecode(
        File('${root.path}/tool/canaries/canary_contract.json')
            .readAsStringSync(),
      ),
    );
    final release = _object(
      jsonDecode(
        File('${root.path}/tool/package_release_contract.json')
            .readAsStringSync(),
      ),
    );
    final installation = _object(contract['gitInstallation']);
    final workspace = _object(release['workspaceCohort']);
    final errors = <String>[];
    if (contract['schemaVersion'] != 4 ||
        contract['workspaceVersion'] != workspace['version'] ||
        installation['repository'] !=
            'https://github.com/ftr-tuta/dartitect.git' ||
        installation['ref'] != workspace['derivedTag'] ||
        installation['tagPattern'] != 'v{{version}}' ||
        installation['annotatedTagRequired'] != true ||
        installation['localDisposableTag'] != true ||
        installation['remoteTagRequired'] != false ||
        installation['dependencyOverrides'] != false ||
        installation['transitiveClosureRequired'] != true ||
        installation['localPathResolution'] != false ||
        installation['hostedDartitectResolution'] != false) {
      errors.add('Git canary installation policy is incomplete.');
    }
    final canaries = _objects(contract['canaries']);
    if (canaries.map((item) => item['id']).toSet().length != canaries.length) {
      errors.add('Git canary IDs must be unique.');
    }
    for (final canary in canaries) {
      final id = canary['id'];
      final source = canary['source'];
      final pubspecPath = canary['pubspec'];
      if (id is! String ||
          source is! String ||
          pubspecPath is! String ||
          !Directory('${root.path}/$source').existsSync() ||
          !File('${root.path}/$pubspecPath').existsSync() ||
          _strings(canary['commands']).isEmpty ||
          _strings(canary['requiredPackages']).isEmpty ||
          canary['residualResourceCensus'] != 0) {
        errors.add('Canary $id is incomplete.');
        continue;
      }
      _checkTemplate(
        File('${root.path}/$pubspecPath'),
        workspace['version']! as String,
        errors,
      );
    }
    final catalog = _object(contract['catalog']);
    final packages = _object(catalog['packages']).keys.toSet();
    final releasePackages = _object(release['packages']).keys.toSet();
    if (packages.length != 25 ||
        packages.difference(releasePackages).isNotEmpty ||
        releasePackages.difference(packages).isNotEmpty) {
      errors.add('Canary catalog must cover all 25 release packages.');
    }
    final runner = File('${root.path}/tool/run_git_canaries.dart')
        .readAsStringSync();
    for (final required in const <String>[
      "locked['source'] != 'git'",
      "locked['tag-pattern'] != 'v{{version}}'",
      "locked['resolved-ref'] != resolvedCommit",
      "locked['path'] != 'packages/\$package'",
      'resolved from the local workspace',
    ]) {
      if (!runner.contains(required)) {
        errors.add('Git canary runner is missing lock audit: $required.');
      }
    }
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Git canary contract passed for ${canaries.length} consumers and all '
      '25 packages; execution requires the disposable annotated-tag remote.',
    );
  } on Object catch (error) {
    stderr.writeln('Git canary contract could not be checked: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

void _checkTemplate(File file, String version, List<String> errors) {
  final yaml = _yamlObject(loadYaml(file.readAsStringSync()));
  if (yaml.containsKey('dependency_overrides')) {
    errors.add('${file.path} must not contain dependency_overrides.');
  }
  var direct = 0;
  for (final sectionName in const <String>[
    'dependencies',
    'dev_dependencies',
  ]) {
    final section = _yamlObjectOrNull(yaml[sectionName]);
    if (section == null) continue;
    for (final entry in section.entries.where(
      (entry) => RegExp(r'^dartitect(?:_[a-z0-9_]+)?$').hasMatch(entry.key),
    )) {
      direct += 1;
      if (entry.value != version) {
        errors.add(
          '${file.path} template must declare ${entry.key}: $version for '
          'Git rendering.',
        );
      }
    }
  }
  if (direct == 0) errors.add('${file.path} has no direct Dartitect package.');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON object list.');
  }
  return <Map<String, Object?>>[for (final item in value) _object(item)];
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

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
