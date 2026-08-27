import 'dart:io';

/// Verifies the reviewed stable-v1 internal package DAG and core purity.
void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final observed = <String, Set<String>>{};
  final errors = <String>[];
  for (final entity in Directory(
    '${root.path}/packages',
  ).listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final pubspec = File('${entity.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final source = pubspec.readAsStringSync();
    final name = RegExp(
      r'^name:\s*([^\s]+)',
      multiLine: true,
    ).firstMatch(source)!.group(1)!;
    observed[name] = _internalDependencies(source);
  }
  if (observed.keys.toSet().difference(_allowed.keys.toSet()).isNotEmpty ||
      _allowed.keys.toSet().difference(observed.keys.toSet()).isNotEmpty) {
    errors.add('Package set differs from the reviewed stable-v1 topology.');
  }
  for (final entry in observed.entries) {
    final allowed = _allowed[entry.key];
    if (allowed == null || !_sameSet(entry.value, allowed)) {
      errors.add(
        '${entry.key} internal dependencies are ${entry.value}; '
        'expected $allowed.',
      );
    }
  }
  final visiting = <String>{};
  final visited = <String>{};
  bool visit(String package) {
    if (!visiting.add(package)) return false;
    if (!visited.add(package)) {
      visiting.remove(package);
      return true;
    }
    for (final dependency in observed[package] ?? const <String>{}) {
      if (!visit(dependency)) return false;
    }
    visiting.remove(package);
    return true;
  }

  for (final package in observed.keys) {
    if (!visit(package))
      errors.add('Internal package cycle includes $package.');
  }
  for (final package in const <String>['dartitect', 'dartitect_sync']) {
    final lib = Directory('${root.path}/packages/$package/lib');
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final imports = RegExp(r'''(?:import|export)\s+['"]package:([^/]+)/''')
          .allMatches(entity.readAsStringSync());
      for (final match in imports) {
        final dependency = match.group(1)!;
        if (package == 'dartitect' || dependency != 'dartitect') {
          errors.add('$package purity violation: $dependency.');
        }
      }
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Stable-v1 package DAG is acyclic and core/sync purity is intact.',
  );
}

Set<String> _internalDependencies(String pubspec) {
  final output = <String>{};
  var dependencies = false;
  for (final line in pubspec.split(RegExp(r'\r?\n'))) {
    if (line == 'dependencies:') {
      dependencies = true;
      continue;
    }
    if (dependencies && line.isNotEmpty && !line.startsWith(' ')) break;
    final match = dependencies
        ? RegExp(r'^  (dartitect(?:_[A-Za-z0-9_]+)?):').firstMatch(line)
        : null;
    if (match != null) output.add(match.group(1)!);
  }
  return output;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

const Map<String, Set<String>> _allowed = <String, Set<String>>{
  'dartitect': <String>{},
  'dartitect_cli': <String>{},
  'dartitect_dio': <String>{'dartitect', 'dartitect_observability'},
  'dartitect_drift': <String>{
    'dartitect',
    'dartitect_observability',
    'dartitect_sync',
  },
  'dartitect_flutter': <String>{'dartitect'},
  'dartitect_isolates': <String>{'dartitect'},
  'dartitect_lints': <String>{},
  'dartitect_locale_br': <String>{},
  'dartitect_mcp': <String>{'dartitect_cli'},
  'dartitect_media': <String>{'dartitect'},
  'dartitect_objectbox': <String>{
    'dartitect',
    'dartitect_flutter',
    'dartitect_observability',
    'dartitect_sync',
  },
  'dartitect_observability': <String>{'dartitect'},
  'dartitect_privacy': <String>{},
  'dartitect_geometry': <String>{},
  'dartitect_sentry': <String>{'dartitect_observability'},
  'dartitect_sync': <String>{'dartitect'},
  'dartitect_testing': <String>{
    'dartitect',
    'dartitect_isolates',
    'dartitect_observability',
    'dartitect_sync',
  },
};
