import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts one exact lockstep cohort in dependency layers', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('2 packages at 1.0.0-rc.9'));
  });

  test('accepts a release-candidate lockstep cohort', () async {
    final fixture = await _Fixture.create(cohort: '1.0.0-rc.2');
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('2 packages at 1.0.0-rc.2'));
  });

  test('rejects a mixed package cohort', () async {
    final fixture = await _Fixture.create(syncVersion: '1.0.0-rc.8');
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('expected cohort'));
  });

  test('rejects a broad internal constraint', () async {
    final fixture = await _Fixture.create(constraint: '^1.0.0-rc.9');
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('uses ^1.0.0-rc.9'));
  });

  test('rejects publication in the dependency layer or later', () async {
    final fixture = await _Fixture.create(
      layers: const <List<String>>[
        <String>['dartitect', 'dartitect_sync'],
      ],
    );
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('layers are not topological'));
  });
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  static Future<_Fixture> create({
    String cohort = '1.0.0-rc.9',
    String? syncVersion,
    String? constraint,
    List<List<String>> layers = const <List<String>>[
      <String>['dartitect'],
      <String>['dartitect_sync'],
    ],
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-release-contract-',
    );
    await Directory('${root.path}/tool').create(recursive: true);
    final internalConstraint = constraint ?? '>=$cohort <1.0.0';
    await _package(root, 'dartitect', cohort);
    await _package(
      root,
      'dartitect_sync',
      syncVersion ?? cohort,
      dependency: internalConstraint,
    );
    final order = <String>[for (final layer in layers) ...layer];
    await File('${root.path}/tool/package_release_contract.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'series': '1.0.x',
        'cohortVersion': cohort,
        'internalConstraint': '>=$cohort <1.0.0',
        'publicationLayers': layers,
        'publicationOrder': order,
        'artifactContract': <String, Object?>{
          'cleanClone': true,
          'exactSourceSha': true,
          'trackedTreeClean': true,
          'pathDependencies': false,
          'dependencyOverrides': false,
          'digestAlgorithm': 'sha256',
        },
        'partialFailurePolicy': <String, Object?>{
          'automaticRetry': false,
          'overwritePublishedVersion': false,
          'resumeOnlyWithSameSourceAndDigests': true,
          'changedArtifactRequiresNextCohort': true,
        },
      }),
    );
    return _Fixture(root);
  }

  Future<ProcessResult> check() async {
    final checker = File(
      '${Directory.current.path}/tool/check_package_release_contract.dart',
    );
    return Process.run(Platform.resolvedExecutable, <String>[
      checker.path,
      '--root',
      root.path,
    ]);
  }

  Future<void> dispose() => root.delete(recursive: true);

  static Future<void> _package(
    Directory root,
    String name,
    String version, {
    String? dependency,
  }) async {
    final directory = Directory('${root.path}/packages/$name');
    await directory.create(recursive: true);
    await File('${directory.path}/pubspec.yaml').writeAsString('''
name: $name
version: $version
resolution: workspace
${dependency == null ? '' : "dependencies:\n  dartitect: '$dependency'\n"}
''');
    await File('${directory.path}/CHANGELOG.md')
        .writeAsString('# Changelog\n\n## $version\n');
  }
}
