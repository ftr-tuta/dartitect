import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('structural mode cannot declare readiness', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(contractOnly: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('cannot declare release readiness'));
  });

  test(
    'accepts a current main Actions manifest with all successful jobs',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.check();

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('current main CI execution'));
    },
  );

  test('rejects a divergent run id or attempt', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final manifest = fixture.readManifest();
    manifest['runAttempt'] = 2;
    await fixture.writeManifest(manifest);

    final result = await fixture.check(runId: 999);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('current CI execution'));
  });

  test('rejects failed, cancelled, and skipped jobs', () async {
    for (final conclusion in const <String>[
      'failure',
      'cancelled',
      'skipped',
    ]) {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final manifest = fixture.readManifest();
      ((manifest['jobs']! as List<Object?>).first
              as Map<String, Object?>)['conclusion'] =
          conclusion;
      await fixture.writeManifest(manifest);

      final result = await fixture.check();

      expect(result.exitCode, 1);
      expect(result.stderr, contains('missing, skipped, or failed'));
    }
  });

  test('rejects an altered artifact', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await File('${fixture.artifactRoot.path}/native/ios-current-simulator.json')
        .writeAsString('altered\n');

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('altered or is missing'));
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
    final root = await Directory.systemTemp.createTemp('actions-readiness-');
    for (final path in const <String>[
      'tool/actions_readiness_policy.json',
      'tool/native_evidence_contract.json',
    ]) {
      final destination = File('${root.path}/$path');
      await destination.parent.create(recursive: true);
      await File('${sourceRoot.path}/$path').copy(destination.path);
    }
    for (final path in const <String>[
      '.github/workflows/ci.yaml',
      '.github/workflows/publish.yaml',
    ]) {
      final file = File('${root.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString('name: fixture\n');
    }
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
    final artifactRoot = Directory('${root.path}/build/actions-readiness-v1');
    await artifactRoot.create(recursive: true);
    final policy = jsonDecode(
      File('${root.path}/tool/actions_readiness_policy.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
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

  Future<ProcessResult> check({bool contractOnly = false, int runId = 123}) {
    final checker = File(
      '${Directory.current.path}/tool/check_rc_readiness.dart',
    );
    return Process.run(
      Platform.resolvedExecutable,
      <String>[
        checker.path,
        '--root=${root.path}',
        if (contractOnly)
          '--contract-only'
        else
          '--manifest=${artifactRoot.path}/actions-readiness-v1.json',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'GITHUB_ACTIONS': 'true',
        'RUNNER_ENVIRONMENT': 'github-hosted',
        'GITHUB_WORKFLOW': 'CI',
        'GITHUB_EVENT_NAME': 'push',
        'GITHUB_REF': 'refs/heads/main',
        'GITHUB_SHA': sha,
        'GITHUB_RUN_ID': '$runId',
        'GITHUB_RUN_ATTEMPT': '1',
        'GITHUB_REPOSITORY': 'ftr-tuta/dartitect',
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
