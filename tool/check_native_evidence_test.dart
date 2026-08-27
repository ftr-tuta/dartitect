import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts exactly five schema-v3 current-run manifests', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('all five hosted cells'));
  });

  test('rejects a missing and a duplicate cell', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final paths = fixture.manifestPaths();

    final missing = await fixture.check(manifests: paths.sublist(1));
    final duplicate = await fixture.check(
      manifests: <String>[...paths, paths.first],
    );

    expect(missing.exitCode, 1);
    expect(missing.stderr, contains('Missing native evidence manifest'));
    expect(duplicate.exitCode, 1);
    expect(duplicate.stderr, contains('Duplicate native manifest'));
  });

  test('rejects cancelled or ignored conclusions', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    for (final resultValue in const <String>['cancelled', 'skipped']) {
      final manifest = fixture.manifest('android-media-floor-build');
      manifest['result'] = resultValue;
      await fixture.writeManifest('android-media-floor-build', manifest);
      final result = await fixture.check();
      expect(result.exitCode, 1);
      expect(result.stderr, contains('conclusion'));
    }
  });

  test('rejects SHA, tree, run id, and attempt mismatches', () async {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (manifest) => manifest['sourceSha'] = _repeat('0', 40),
      (manifest) => manifest['sourceTree'] = _repeat('0', 40),
      (manifest) =>
          (manifest['workflow']! as Map<String, Object?>)['runId'] = 999,
      (manifest) =>
          (manifest['workflow']! as Map<String, Object?>)['runAttempt'] = 2,
    ]) {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final manifest = fixture.manifest('ios-current-simulator');
      mutation(manifest);
      await fixture.writeManifest('ios-current-simulator', manifest);

      final result = await fixture.check();

      expect(result.exitCode, 1);
    }
  });

  test('rejects a physical cell or self-hosted runner policy', () async {
    for (final mutate in <void Function(Map<String, Object?>)>[
      (contract) =>
          (contract['requiredCells']! as List<Object?>).add(<String, Object?>{
            'id': 'android-physical',
            'platform': 'android',
            'capabilities': <String>['media'],
            'evidenceKind': 'physical',
            'floor': false,
            'requiredVersionKeys': <String>['os'],
            'requiredScenarios': <String>['tree-clean'],
          }),
      (contract) => contract['runner'] = 'self-hosted',
    ]) {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final contract = fixture.contract;
      mutate(contract);
      await File('${fixture.root.path}/tool/native_evidence_contract.json')
          .writeAsString(jsonEncode(contract));

      final result = await fixture.check(contractOnly: true);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('forbidden policy'));
    }
  });

  test('formal mode rejects local and other-run artifacts', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final local = await fixture.check(githubActions: false);
    final otherRun = await fixture.check(runId: 124);

    expect(local.exitCode, 1);
    expect(local.stderr, contains('restricted to GitHub-hosted Actions'));
    expect(otherRun.exitCode, 1);
    expect(otherRun.stderr, contains('current GitHub Actions run'));
  });
}

final class _Fixture {
  const _Fixture(this.root, this.sha, this.tree, this.contract);

  final Directory root;
  final String sha;
  final String tree;
  final Map<String, Object?> contract;

  static Future<_Fixture> create() async {
    final sourceRoot = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp(
      'dartitect-native-evidence-v3-',
    );
    await _copy(
      File('${sourceRoot.path}/tool/native_evidence_contract.json'),
      File('${root.path}/tool/native_evidence_contract.json'),
    );
    final contract = jsonDecode(
      File('${root.path}/tool/native_evidence_contract.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    for (final path in const <String>[
      'tool/canaries/native_capabilities/lib/main.dart',
      'tool/canaries/native_capabilities/integration_test/android_media_test.dart',
      'tool/canaries/native_capabilities/lib/ios_ci_harness.dart',
      'tool/run_native_ci_evidence.dart',
    ]) {
      await _text(root, path, '// fixture\n');
    }
    final android = contract['android']! as Map<String, Object?>;
    final ios = contract['ios']! as Map<String, Object?>;
    final androidSource = (android['requiredSourceMarkers']! as List<Object?>)
        .join('\n');
    await _text(root, android['manifest']! as String, androidSource);
    await _text(root, android['plugin']! as String, androidSource);
    final iosSource = <String>[
      ...(ios['requiredSourceMarkers']! as List<Object?>).cast<String>(),
      "s.platform = :ios, '14.0'",
      "s.platform = :ios, '12.0'",
    ].join('\n');
    for (final key in const <String>[
      'mediaPodspec',
      'privacyPodspec',
      'mediaPlugin',
      'privacyPlugin',
    ]) {
      await _text(root, ios[key]! as String, iosSource);
    }
    await _text(root, '.gitignore', 'build/\n');
    await _text(root, 'tracked.txt', 'clean\n');
    await _run(root, 'git', const <String>['init', '-q']);
    await _run(root, 'git', const <String>['config', 'user.name', 'fixture']);
    await _run(root, 'git', const <String>[
      'config',
      'user.email',
      'fixture@example.invalid',
    ]);
    await _run(root, 'git', const <String>['add', '.']);
    await _run(root, 'git', const <String>['commit', '-qm', 'fixture']);
    final sha = (await _run(root, 'git', const <String>[
      'rev-parse',
      'HEAD',
    ])).stdout.toString().trim();
    final tree = (await _run(root, 'git', const <String>[
      'show',
      '-s',
      '--format=%T',
      'HEAD',
    ])).stdout.toString().trim();
    final fixture = _Fixture(root, sha, tree, contract);
    for (final cell
        in (contract['requiredCells']! as List<Object?>)
            .cast<Map<String, Object?>>()) {
      await fixture.writeManifest(
        cell['id']! as String,
        fixture._newManifest(cell),
      );
    }
    return fixture;
  }

  Map<String, Object?> _newManifest(Map<String, Object?> cell) {
    final kind = cell['evidenceKind']! as String;
    final environment = <String, Object?>{
      'kind': kind,
      'provider': 'github-hosted',
      'runnerName': 'GitHub Actions 1',
      'runnerOs': kind == 'simulator' ? 'macOS' : 'Linux',
      'runnerImage': kind == 'simulator'
          ? 'macos-15/20260820.1'
          : 'ubuntu24/20260820.1',
      if (kind == 'emulator') ...<String, Object?>{
        'apiLevel': 34,
        'systemImage': 'system-images;android-34;google_apis;x86_64',
        'avdName': 'dartitect-api-34',
        'osVersion': '14',
        'model': 'sdk_gphone_x86_64',
        'bootCompleted': true,
        'cleanShutdown': true,
      },
      if (kind == 'simulator') ...<String, Object?>{
        'runtime': 'iOS 18.5',
        'model': 'iPhone 16 Pro',
        'cleanupCompleted': true,
      },
    };
    return <String, Object?>{
      'schemaVersion': 3,
      'goal': 'V1S-13',
      'cellId': cell['id'],
      'sourceSha': sha,
      'sourceTree': tree,
      'result': 'success',
      'platform': cell['platform'],
      'capabilities': cell['capabilities'],
      'evidenceKind': kind,
      'versions': <String, Object?>{
        for (final key
            in (cell['requiredVersionKeys']! as List<Object?>).cast<String>())
          key: '$key-1.2.3',
      },
      'environment': environment,
      'startedAt': '2026-08-27T12:00:00Z',
      'completedAt': '2026-08-27T12:01:00Z',
      'treeClean': true,
      'scenarios': cell['requiredScenarios'],
      'workflow': <String, Object?>{
        'name': 'CI',
        'runId': 123,
        'runAttempt': 1,
        'repository': 'ftr-tuta/dartitect',
        'event': 'push',
        'url': 'https://github.com/ftr-tuta/dartitect/actions/runs/123',
        'sourceSha': sha,
        'sourceTree': tree,
      },
    };
  }

  Map<String, Object?> manifest(String id) =>
      jsonDecode(File(_manifestPath(id)).readAsStringSync())
          as Map<String, Object?>;

  Future<void> writeManifest(String id, Map<String, Object?> manifest) async {
    final file = File(_manifestPath(id));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(manifest));
  }

  List<String> manifestPaths() => <String>[
    for (final cell
        in (contract['requiredCells']! as List<Object?>)
            .cast<Map<String, Object?>>())
      _manifestPath(cell['id']! as String),
  ];

  Future<ProcessResult> check({
    bool contractOnly = false,
    bool githubActions = true,
    int runId = 123,
    List<String>? manifests,
  }) {
    final checker = File(
      '${Directory.current.path}/tool/check_native_evidence.dart',
    );
    return Process.run(
      Platform.resolvedExecutable,
      <String>[
        checker.path,
        '--root=${root.path}',
        if (contractOnly) '--contract-only',
        if (manifests != null)
          for (final manifest in manifests) '--manifest=$manifest',
      ],
      environment: <String, String>{
        ...Platform.environment,
        if (githubActions)
          'GITHUB_ACTIONS': 'true'
        else
          'GITHUB_ACTIONS': 'false',
        'RUNNER_ENVIRONMENT': githubActions ? 'github-hosted' : 'self-hosted',
        'GITHUB_SHA': sha,
        'GITHUB_RUN_ID': '$runId',
        'GITHUB_RUN_ATTEMPT': '1',
        'GITHUB_REPOSITORY': 'ftr-tuta/dartitect',
      },
    );
  }

  String _manifestPath(String id) =>
      '${root.path}/build/native-evidence/$id-$sha.json';

  Future<void> dispose() => root.delete(recursive: true);
}

Future<void> _copy(File source, File destination) async {
  await destination.parent.create(recursive: true);
  await source.copy(destination.path);
}

Future<void> _text(Directory root, String path, String content) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<ProcessResult> _run(
  Directory root,
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed: ${result.stderr}',
    );
  }
  return result;
}

String _repeat(String value, int count) =>
    List<String>.filled(count, value).join();
