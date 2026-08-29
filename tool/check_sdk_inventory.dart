import 'dart:convert';
import 'dart:io';

/// Generates or verifies the machine-readable package/API inventory.
Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final release = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (release is! Map<String, Object?> || release['cohortVersion'] is! String) {
    throw const FormatException('Invalid package release cohort.');
  }
  final cohort = release['cohortVersion']! as String;
  final releasePackages = release['packages'];
  final decisions = release['inventoryDecisions'];
  if (releasePackages is! Map<String, Object?> ||
      decisions is! Map<String, Object?>) {
    throw const FormatException('Release inventory metadata is missing.');
  }
  final api = jsonDecode(
    File('${root.path}/tool/api_surface.snapshot.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final surfaces = api['entrypoints']! as Map<String, Object?>;
  if (api['schemaVersion'] != 2) {
    throw const FormatException('Unsupported semantic API snapshot schema.');
  }
  final packages = <Map<String, Object?>>[];
  for (final entity in Directory(
    '${root.path}/packages',
  ).listSync(followLinks: false)) {
    if (entity is! Directory) continue;
    final pubspec = File('${entity.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final source = pubspec.readAsStringSync();
    String field(String name) => RegExp(
      '^$name:\\s*([^\\s]+)',
      multiLine: true,
    ).firstMatch(source)!.group(1)!;
    final name = field('name');
    final releasePackage = releasePackages[name];
    if (releasePackage is! Map<String, Object?> ||
        releasePackage['version'] != field('version')) {
      throw FormatException('$name differs from release package metadata.');
    }
    final entrypoints =
        surfaces.entries
            .where((entry) => entry.key.startsWith('packages/$name/lib/'))
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    final symbolCount = entrypoints.fold<int>(0, (total, entry) {
      final surface = entry.value;
      if (surface is! Map<String, Object?> ||
          surface['symbols'] is! List<Object?>) {
        throw FormatException('Invalid API entrypoint ${entry.key}.');
      }
      return total + (surface['symbols']! as List<Object?>).length;
    });
    packages.add(<String, Object?>{
      'name': name,
      'version': releasePackage['version'],
      'decision': decisions[name],
      'runtimeDependencies': _dependencies(source),
      'entrypoints': <String>[
        for (final entry in entrypoints) entry.key.split('/').last,
      ],
      'publicSymbolCount': symbolCount,
    });
  }
  packages.sort(
    (left, right) =>
        (left['name']! as String).compareTo(right['name']! as String),
  );
  final unknown = packages
      .where((package) => package['decision'] == null)
      .map((package) => package['name'])
      .toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unclassified SDK packages: $unknown');
    exitCode = 1;
    return;
  }
  final encoded =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'status': cohort == '1.0.0' ? 'STABLE_CANDIDATE' : 'NOT_READY_FOR_1_0_RC', 'packages': packages})}\n';
  final inventory = File('${root.path}/tool/sdk_inventory.json');
  if (arguments.contains('--update')) {
    inventory.writeAsStringSync(encoded, flush: true);
    stdout.writeln(
      'Updated SDK inventory for ${packages.length} packages and '
      '${surfaces.length} entrypoints.',
    );
    return;
  }
  if (!inventory.existsSync() || inventory.readAsStringSync() != encoded) {
    stderr.writeln('SDK inventory is stale; review and run with --update.');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'SDK inventory matches ${packages.length} packages and '
    '${surfaces.length} entrypoints.',
  );
}

List<String> _dependencies(String pubspec) {
  final output = <String>[];
  var inDependencies = false;
  for (final line in pubspec.split(RegExp(r'\r?\n'))) {
    if (line == 'dependencies:') {
      inDependencies = true;
      continue;
    }
    if (inDependencies && line.isNotEmpty && !line.startsWith(' ')) break;
    final match = inDependencies
        ? RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line)
        : null;
    if (match != null) output.add(match.group(1)!);
  }
  output.sort();
  return output;
}
