import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('accepts the exact successful main CI artifact', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('authorized by CI run 123'));
    expect(result.stdout, contains('actor release-operator'));
  });

  test('rejects a divergent CI run id', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(runId: 999);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('does not match source_sha and ci_run_id'));
  });

  test('rejects a divergent CI run attempt', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(runAttempt: 2);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('does not match source_sha and ci_run_id'));
  });

  test('rejects an expired, missing, or altered artifact', () async {
    for (final mutation in <Future<void> Function(_Fixture)>[
      (fixture) =>
          File('${fixture.artifactRoot.path}/native/ios-current-simulator.json')
              .delete(),
      (fixture) =>
          File('${fixture.artifactRoot.path}/native/ios-current-simulator.json')
              .writeAsString('altered\n'),
    ]) {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await mutation(fixture);

      final result = await fixture.check();

      expect(result.exitCode, 1);
      expect(result.stderr, contains('expired, missing, or altered'));
    }
  });

  test('rejects a source SHA outside the referenced artifact', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final manifest = fixture.readManifest();
    manifest['sourceSha'] = '0000000000000000000000000000000000000000';
    await fixture.writeManifest(manifest);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('does not match source_sha and ci_run_id'));
  });

  test('rejects Release when stable candidate evidence fails', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await File('${fixture.root.path}/tool/check_stable_candidate.dart')
        .writeAsString('void main() => throw StateError("stale evidence");\n');

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('Stable release rejected candidate evidence'),
    );
  });
}

final class _Fixture {
  const _Fixture(this.root, this.artifactRoot, this.sha, this.tree);

  final Directory root;
  final Directory artifactRoot;
  final String sha;
  final String tree;

  static Future<_Fixture> create() async {
    final sourceRoot = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp('release-readiness-');
    final policyFile = File('${root.path}/tool/actions_readiness_policy.json');
    await policyFile.parent.create(recursive: true);
    await File('${sourceRoot.path}/tool/actions_readiness_policy.json')
        .copy(policyFile.path);
    await File('${root.path}/tool/check_stable_candidate.dart')
        .writeAsString("void main() => print('stable fixture passed');\n");
    await File('${root.path}/README.md').writeAsString('fixture\n');
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
    final policy =
        jsonDecode(policyFile.readAsStringSync()) as Map<String, Object?>;
    final artifactRoot = Directory('${root.path}/build/actions-readiness-v1');
    await artifactRoot.create(recursive: true);
    final digests = <Map<String, Object?>>[];
    for (final cell
        in (policy['nativeCells']! as List<Object?>).cast<String>()) {
      final file = File('${artifactRoot.path}/native/$cell.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('{"cell":"$cell"}\n');
      digests.add(_digestEntry(file, artifactRoot, 'native-manifest'));
    }
    for (final path
        in (policy['repositoryArtifacts']! as List<Object?>).cast<String>()) {
      final file = File('${artifactRoot.path}/repository/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString('$path\n');
      digests.add(_digestEntry(file, artifactRoot, 'repository-artifact'));
    }
    digests.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    final fixture = _Fixture(root, artifactRoot, sha, tree);
    await fixture.writeManifest(<String, Object?>{
      'schemaVersion': 1,
      'artifact': 'actions-readiness-v1',
      'authority': 'github-actions',
      'workflow': 'CI',
      'requiredCheck': 'CI / Required',
      'sourceSha': sha,
      'sourceTree': tree,
      'ref': 'refs/heads/main',
      'event': 'push',
      'runId': 123,
      'runAttempt': 1,
      'repository': 'ftr-tuta/dartitect',
      'url': 'https://github.com/ftr-tuta/dartitect/actions/runs/123',
      'jobs': <Map<String, Object?>>[
        for (final id
            in (policy['requiredJobs']! as List<Object?>).cast<String>())
          <String, Object?>{'id': id, 'conclusion': 'success'},
      ],
      'artifactDigests': digests,
      'createdAt': '2026-08-27T12:00:00Z',
    });
    return fixture;
  }

  Map<String, Object?> readManifest() => jsonDecode(
    File('${artifactRoot.path}/actions-readiness-v1.json').readAsStringSync(),
  ) as Map<String, Object?>;

  Future<void> writeManifest(Map<String, Object?> value) =>
      File('${artifactRoot.path}/actions-readiness-v1.json')
          .writeAsString(jsonEncode(value));

  Future<ProcessResult> check({int runId = 123, int runAttempt = 1}) {
    final checker = File(
      '${Directory.current.path}/tool/check_release_readiness.dart',
    );
    return Process.run(
      Platform.resolvedExecutable,
      <String>[
        checker.path,
        '--root=${root.path}',
        '--source-sha=$sha',
        '--ci-run-id=$runId',
        '--manifest=${artifactRoot.path}/actions-readiness-v1.json',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'GITHUB_ACTIONS': 'true',
        'RUNNER_ENVIRONMENT': 'github-hosted',
        'GITHUB_WORKFLOW': 'Release',
        'GITHUB_EVENT_NAME': 'workflow_dispatch',
        'GITHUB_ACTOR': 'release-operator',
        'CI_RUN_ATTEMPT': '$runAttempt',
      },
    );
  }

  Future<void> dispose() => root.delete(recursive: true);
}

Map<String, Object?> _digestEntry(File file, Directory root, String kind) =>
    <String, Object?>{
      'path': file.path.substring(root.path.length + 1),
      'kind': kind,
      'sha256': sha256.convert(file.readAsBytesSync()).toString(),
    };

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
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return result;
}
