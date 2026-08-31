import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'accepts one RC baseline with a generated compatibility range',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.check();

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('2 packages from baseline 1.0.0-rc.8'));
    },
  );

  test('accepts independent stable patches declared by the manifest', () async {
    final fixture = await _Fixture.create(
      baseline: '1.0.0',
      syncVersion: '1.0.3',
      constraint: '>=1.0.0 <1.1.0',
    );
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test(
    'rejects workspace version that differs from package metadata',
    () async {
      final fixture = await _Fixture.create(
        syncVersion: '1.0.0-rc.10',
        manifestSyncVersion: '1.0.0-rc.8',
      );
      addTearDown(fixture.dispose);

      final result = await fixture.check();

      expect(result.exitCode, 1);
      expect(result.stderr, contains('does not match its release metadata'));
    },
  );

  test('rejects a broad internal constraint', () async {
    final fixture = await _Fixture.create(constraint: '^1.0.0-rc.8');
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('uses ^1.0.0-rc.8'));
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
    String baseline = '1.0.0-rc.8',
    String? syncVersion,
    String? manifestSyncVersion,
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
    final expectedConstraint = baseline.contains('-')
        ? '>=$baseline <1.0.0'
        : '>=1.0.0 <1.1.0';
    final actualSyncVersion = syncVersion ?? baseline;
    await _package(root, 'dartitect', baseline);
    await _package(
      root,
      'dartitect_sync',
      actualSyncVersion,
      dependency: constraint ?? expectedConstraint,
    );
    final order = <String>[for (final layer in layers) ...layer];
    await File('${root.path}/tool/package_release_contract.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'series': '1.0.x',
        'cohortVersion': baseline,
        'baselineVersion': baseline,
        'candidateTag': 'v$baseline',
        'packageCount': 2,
        'publicEntrypointCount': 1,
        'compatibility': <String, Object?>{
          'defaultRange': expectedConstraint,
          'packageRanges': <String, Object?>{},
          'prereleaseBaselineRequired': true,
          'stableIndependentPatches': true,
          'stableDefaultRange': '>=1.0.0 <1.1.0',
        },
        'inventoryDecisions': <String, Object?>{
          'dartitect': 'fixture-foundation',
          'dartitect_sync': 'fixture-platform-service',
        },
        'publicationCohorts': <String, Object?>{
          'foundation': <String>['dartitect'],
          'platformServices': <String>['dartitect_sync'],
          'providerAdapters': <String>[],
          'tooling': <String>[],
          'leafUtilities': <String>[],
        },
        'packages': <String, Object?>{
          'dartitect': _metadata(baseline),
          'dartitect_sync': _metadata(manifestSyncVersion ?? actualSyncVersion),
        },
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
        'gitCandidate': <String, Object?>{
          'tag': 'v$baseline',
          'materialized': false,
          'pubDevPublication': false,
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

  static Map<String, Object?> _metadata(String version) => <String, Object?>{
    'version': version,
    'platforms': <String>['Dart'],
    'stability': 'fixture',
  };

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
