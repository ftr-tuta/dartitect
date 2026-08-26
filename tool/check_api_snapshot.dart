import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final release = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (release is! Map<String, Object?> || release['cohortVersion'] is! String) {
    throw const FormatException('Invalid package release cohort.');
  }
  final cohort = release['cohortVersion']! as String;
  final entrypoints = <File>[];
  await for (final package in Directory.fromUri(
    root.uri.resolve('packages/'),
  ).list(followLinks: false)) {
    if (package is! Directory) continue;
    final lib = Directory.fromUri(package.uri.resolve('lib/'));
    if (!await lib.exists()) continue;
    await for (final entity in lib.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        entrypoints.add(entity.absolute);
      }
    }
  }
  entrypoints.sort((left, right) => left.path.compareTo(right.path));
  final surface = <String, Object?>{};
  for (final entrypoint in entrypoints) {
    final collection = AnalysisContextCollection(
      includedPaths: <String>[entrypoint.path],
    );
    try {
      final context = collection.contextFor(entrypoint.path);
      final result = await context.currentSession.getResolvedLibrary(
        entrypoint.path,
      );
      if (result is! ResolvedLibraryResult) {
        throw StateError('Could not resolve ${entrypoint.path}: $result');
      }
      final names =
          result.element.exportNamespace.definedNames2.entries
              .where((entry) => !entry.key.startsWith('_'))
              .map(
                (entry) => <String, String>{
                  'name': entry.key,
                  'declaration': entry.value.displayString(),
                },
              )
              .toList()
            ..sort((left, right) => left['name']!.compareTo(right['name']!));
      final path = entrypoint.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      surface[path] = names;
    } finally {
      await collection.dispose();
    }
  }
  final encoded =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'sdkVersion': cohort, 'entrypoints': surface})}\n';
  final snapshot = File.fromUri(
    root.uri.resolve('tool/api_surface.snapshot.json'),
  );
  if (arguments.contains('--update')) {
    await snapshot.writeAsString(encoded, flush: true);
    stdout.writeln(
      'Updated API snapshot for ${entrypoints.length} entrypoints.',
    );
    return;
  }
  if (!await snapshot.exists() || await snapshot.readAsString() != encoded) {
    stderr.writeln(
      'Public API snapshot is stale; review and run with --update.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Public API snapshot matches ${entrypoints.length} entrypoints.',
  );
}
