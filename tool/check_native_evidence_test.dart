import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'accepts exactly five schema-v2 receipts and authorized retention',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.check();

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('all five'));
    },
  );

  test('rejects a source-tree mismatch', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final receipt = fixture.receipt('android-media-floor-build');
    receipt['sourceTree'] = _repeat('0', 40);
    await fixture.writeReceipt('android-media-floor-build', receipt);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('identity/result/cleanliness'));
  });

  test('rejects duplicate receipts', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final paths = fixture.receiptPaths();

    final result = await fixture.check(
      receipts: <String>[...paths, paths.first],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Duplicate native receipt'));
    expect(result.stderr, contains('receipt set is not exact'));
  });

  test('rejects incomplete scenarios', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final receipt = fixture.receipt('ios-current-simulator');
    (receipt['scenarios']! as List<Object?>).removeLast();
    await fixture.writeReceipt('ios-current-simulator', receipt);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('exact required scenario set'));
  });

  test('rejects an invalid CI workflow run', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final receipt = fixture.receipt('ios-media-floor-build');
    (receipt['workflow']! as Map<String, Object?>)['runId'] = 0;
    await fixture.writeReceipt('ios-media-floor-build', receipt);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('CI workflow/run receipt is invalid'));
  });

  test('rejects raw serial fields even when the digest is present', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final receipt = fixture.receipt('android-media-current-physical');
    (receipt['environment']! as Map<String, Object?>)['serial'] = 'private';
    await fixture.writeReceipt('android-media-current-physical', receipt);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('raw device identifier'));
  });

  test('rejects dirty source trees', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await File('${fixture.root.path}/tracked.txt').writeAsString('dirty\n');

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Source tree is dirty'));
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
      'dartitect-native-evidence-check-',
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
      'tool/canaries/native_capabilities/test/native_qa_panel_test.dart',
      'tool/canaries/native_capabilities/ios/RunnerTests/RunnerTests.swift',
      'tool/run_native_evidence.dart',
      'tool/run_native_ci_evidence.dart',
    ]) {
      await _text(root, path, '// fixture\n');
    }
    final android = contract['android']! as Map<String, Object?>;
    final ios = contract['ios']! as Map<String, Object?>;
    await _text(
      root,
      android['manifest']! as String,
      (android['requiredSourceMarkers']! as List<Object?>).join('\n'),
    );
    await _text(
      root,
      android['plugin']! as String,
      (android['requiredSourceMarkers']! as List<Object?>).join('\n'),
    );
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
      await fixture.writeReceipt(
        cell['id']! as String,
        fixture._newReceipt(cell),
      );
    }
    return fixture;
  }

  Map<String, Object?> _newReceipt(Map<String, Object?> cell) {
    final id = cell['id']! as String;
    final kind = cell['evidenceKind']! as String;
    final versions = <String, Object?>{
      for (final key
          in (cell['requiredVersionKeys']! as List<Object?>).cast<String>())
        key: '$key-1.2.3',
    };
    final environment = switch (kind) {
      'build' => <String, Object?>{
        'kind': 'build',
        'runnerOs': 'fixture-os',
        'runnerImage': 'fixture-image',
      },
      'simulator' => <String, Object?>{
        'kind': 'simulator',
        'runnerOs': 'fixture-os',
        'runnerImage': 'fixture-image',
        'deviceModel': 'fixture simulator',
        'deviceIdSha256': _repeat('a', 64),
      },
      _ => <String, Object?>{
        'kind': 'physical',
        'osVersion': '14',
        'apiLevel': 34,
        'deviceModel': 'fixture physical device',
        'deviceIdSha256': _repeat('b', 64),
        'bootCompleted': true,
        'availableDataKb': 1024,
        'batteryLevel': 80,
        'batteryStatus': '2',
      },
    };
    return <String, Object?>{
      'schemaVersion': 2,
      'goal': 'V1S-13',
      'cellId': id,
      'sourceSha': sha,
      'sourceTree': tree,
      'result': 'passed',
      'platform': cell['platform'],
      'capabilities': cell['capabilities'],
      'evidenceKind': kind,
      'versions': versions,
      'environment': environment,
      'startedAt': '2026-08-26T12:00:00Z',
      'completedAt': '2026-08-26T12:01:00Z',
      'sourceDirty': false,
      'treeClean': true,
      'scenarios': cell['requiredScenarios'],
      if (kind == 'physical')
        'retention': <String, Object?>{
          'kind': 'installed-app',
          'applicationId':
              'dev.dartitect.dartitect_native_capabilities_harness',
          'dataClean': true,
          'mediaClean': true,
          'apkSha256': _repeat('c', 64),
        }
      else
        'workflow': <String, Object?>{
          'workflow': 'CI',
          'runId': 123,
          'runAttempt': 1,
          'repository': 'ftr-tuta/dartitect',
          'event': 'push',
          'url': 'https://github.com/ftr-tuta/dartitect/actions/runs/123',
          'sourceSha': sha,
        },
    };
  }

  Map<String, Object?> receipt(String id) =>
      jsonDecode(File(_receiptPath(id)).readAsStringSync())
          as Map<String, Object?>;

  Future<void> writeReceipt(String id, Map<String, Object?> receipt) async {
    final file = File(_receiptPath(id));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(receipt));
  }

  List<String> receiptPaths() => <String>[
    for (final cell
        in (contract['requiredCells']! as List<Object?>)
            .cast<Map<String, Object?>>())
      _receiptPath(cell['id']! as String),
  ];

  String _receiptPath(String id) =>
      '${root.path}/build/native-evidence/$id-$sha.json';

  Future<ProcessResult> check({List<String>? receipts}) {
    final checker = File(
      '${Directory.current.path}/tool/check_native_evidence.dart',
    );
    return Process.run(Platform.resolvedExecutable, <String>[
      checker.path,
      '--root=${root.path}',
      '--source-sha=$sha',
      if (receipts != null)
        for (final receipt in receipts) '--receipt=$receipt',
    ], workingDirectory: Directory.current.path);
  }

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
