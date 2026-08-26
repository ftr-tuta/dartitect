import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts the explicit fail-closed stable contract', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(const <String>['--contract-only']);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('NOT_ASSEMBLED/NOT_AUTHORIZED'));
  });

  test('formal gate rejects an unassembled stable candidate', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(const <String>[]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('validation is not complete'));
  });

  test(
    'rejects any broadening of the closed release-record allowlist',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final contract = fixture.read('stable_candidate_contract.json');
      final diff = contract['diffPolicy']! as Map<String, Object?>;
      (diff['releaseRecordPaths']! as List<Object?>).add('packages/**');
      await fixture.write('stable_candidate_contract.json', contract);

      final result = await fixture.check(const <String>['--contract-only']);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('allowlist is invalid or broadened'));
    },
  );

  test(
    'accepts only literal metadata, constraints, and changelog prefix',
    () async {
      final fixture = await _Fixture.create(withPromotionHistory: true);
      addTearDown(fixture.dispose);

      final result = await fixture.check(<String>[
        '--compare',
        fixture.rcSha!,
        fixture.stableSha!,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('no readiness or publication was asserted'),
      );
    },
  );

  test('rejects a functional source edit hidden in stable promotion', () async {
    final fixture = await _Fixture.create(
      withPromotionHistory: true,
      functionalChange: true,
    );
    addTearDown(fixture.dispose);

    final result = await fixture.check(<String>[
      '--compare',
      fixture.rcSha!,
      fixture.stableSha!,
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('non-release change outside the allowlist'));
  });

  test('rejects files added during stable promotion', () async {
    final fixture = await _Fixture.create(
      withPromotionHistory: true,
      addedFile: true,
    );
    addTearDown(fixture.dispose);

    final result = await fixture.check(<String>[
      '--compare',
      fixture.rcSha!,
      fixture.stableSha!,
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('forbids add/delete/rename'));
  });

  test(
    'accepts complete same-SHA candidate evidence without publication',
    () async {
      final fixture = await _FormalFixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.check();

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('publication remains a separate decision'),
      );
    },
  );

  test(
    'requires the later authorization for tag and pub.dev actions',
    () async {
      final fixture = await _FormalFixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.check(requireAuthorization: true);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('not authorized'));
    },
  );

  test('rejects duplicate repeated-gate receipts', () async {
    final fixture = await _FormalFixture.create();
    addTearDown(fixture.dispose);
    final record = fixture.readCandidate();
    final gates = record['gateReceipts']! as List<Object?>;
    gates.add(Map<String, Object?>.from(gates.first! as Map<String, Object?>));
    await fixture.writeCandidate(record);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('receipt set is not exact'));
  });
}

final class _Fixture {
  const _Fixture(this.root, {this.rcSha, this.stableSha});

  final Directory root;
  final String? rcSha;
  final String? stableSha;

  static Future<_Fixture> create({
    bool withPromotionHistory = false,
    bool functionalChange = false,
    bool addedFile = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('dartitect-stable-');
    await Directory('${root.path}/tool').create(recursive: true);
    for (final name in const <String>[
      'stable_candidate_contract.json',
      'stable_candidate_record.json',
      'stable_publication_authorization.json',
    ]) {
      await File('${root.path}/tool/$name').writeAsString(
        File('${Directory.current.path}/tool/$name').readAsStringSync(),
      );
    }
    await File('${root.path}/tool/goal_gates.json').writeAsString(
      jsonEncode(<String, Object?>{
        'statusPolicy': <String, Object?>{
          'reviewAuthority': <String, Object?>{
            'kind': 'MAINTAINER_DELEGATED_AUTOMATION',
            'name': 'Codex',
          },
        },
        'goals': <Object?>[],
        'baselines': <String, Object?>{'stableCandidate': null},
      }),
    );
    if (!withPromotionHistory) return _Fixture(root);

    await Directory('${root.path}/packages/dartitect').create(recursive: true);
    await Directory('${root.path}/lib').create(recursive: true);
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: fixture
version: 1.0.0-rc.7
''');
    await File('${root.path}/packages/dartitect/pubspec.yaml').writeAsString('''
name: dartitect
version: 1.0.0-rc.7
dependencies:
  dartitect_sync: '>=1.0.0-rc.7 <1.0.0'
''');
    await File('${root.path}/packages/dartitect/CHANGELOG.md').writeAsString('''
## 1.0.0-rc.7

- Final release candidate.
''');
    await File('${root.path}/lib/version.dart')
        .writeAsString("const version = '1.0.0-rc.7';\n");
    await File('${root.path}/tool/package_release_contract.json').writeAsString(
      jsonEncode(<String, Object?>{
        'cohortVersion': '1.0.0-rc.7',
        'internalConstraint': '>=1.0.0-rc.7 <1.0.0',
        'publicationOrder': <String>['dartitect'],
      }),
    );
    await _run(root, 'git', const <String>['init', '-q']);
    await _run(root, 'git', const <String>['config', 'user.name', 'ftr']);
    await _run(root, 'git', const <String>[
      'config',
      'user.email',
      'ftr@tuta.com',
    ]);
    await _run(root, 'git', const <String>['add', '.']);
    await _run(root, 'git', const <String>['commit', '-qm', 'final rc']);
    final rcSha = (await _run(root, 'git', const <String>[
      'rev-parse',
      'HEAD',
    ])).stdout.toString().trim();

    await File('${root.path}/pubspec.yaml').writeAsString('''
name: fixture
version: 1.0.0
''');
    await File('${root.path}/packages/dartitect/pubspec.yaml').writeAsString('''
name: dartitect
version: 1.0.0
dependencies:
  dartitect_sync: '>=1.0.0 <1.1.0'
''');
    final oldChangelog = File('${root.path}/packages/dartitect/CHANGELOG.md')
        .readAsStringSync();
    await File('${root.path}/packages/dartitect/CHANGELOG.md').writeAsString('''
## 1.0.0

- Stable promotion; no functional changes.

$oldChangelog''');
    await File('${root.path}/lib/version.dart').writeAsString(
      functionalChange
          ? "const version = '1.0.0';\nconst behavior = 'changed';\n"
          : "const version = '1.0.0';\n",
    );
    await File('${root.path}/tool/package_release_contract.json').writeAsString(
      jsonEncode(<String, Object?>{
        'cohortVersion': '1.0.0',
        'internalConstraint': '>=1.0.0 <1.1.0',
        'publicationOrder': <String>['dartitect'],
      }),
    );
    if (addedFile) {
      await File('${root.path}/STABLE.txt').writeAsString('new file\n');
    }
    await _run(root, 'git', const <String>['add', '.']);
    await _run(root, 'git', const <String>['commit', '-qm', 'stable']);
    final stableSha = (await _run(root, 'git', const <String>[
      'rev-parse',
      'HEAD',
    ])).stdout.toString().trim();
    return _Fixture(root, rcSha: rcSha, stableSha: stableSha);
  }

  Map<String, Object?> read(String name) =>
      jsonDecode(File('${root.path}/tool/$name').readAsStringSync())
          as Map<String, Object?>;

  Future<void> write(String name, Map<String, Object?> value) =>
      File('${root.path}/tool/$name').writeAsString(jsonEncode(value));

  Future<ProcessResult> check(List<String> arguments) =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/check_stable_candidate.dart',
        '--root',
        root.path,
        ...arguments,
      ]);

  Future<void> dispose() => root.delete(recursive: true);
}

final class _FormalFixture {
  const _FormalFixture(this.root);

  final Directory root;

  static Future<_FormalFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-stable-formal-',
    );
    await Directory('${root.path}/tool').create(recursive: true);
    for (final name in const <String>[
      'stable_candidate_contract.json',
      'stable_candidate_record.json',
      'stable_publication_authorization.json',
    ]) {
      await File('${root.path}/tool/$name').writeAsString(
        File('${Directory.current.path}/tool/$name').readAsStringSync(),
      );
    }
    const names = <String>[
      'dartitect',
      'dartitect_cli',
      'dartitect_geometry',
      'dartitect_lints',
      'dartitect_locale_br',
      'dartitect_privacy',
      'dartitect_flutter',
      'dartitect_isolates',
      'dartitect_mcp',
      'dartitect_media',
      'dartitect_observability',
      'dartitect_sync',
      'dartitect_dio',
      'dartitect_objectbox',
      'dartitect_sentry',
      'dartitect_testing',
    ];
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: fixture
version: 1.0.0-rc.9
''');
    for (final name in names) {
      final package = Directory('${root.path}/packages/$name');
      await package.create(recursive: true);
      await File('${package.path}/pubspec.yaml').writeAsString('''
name: $name
version: 1.0.0-rc.9
''');
      await File('${package.path}/CHANGELOG.md').writeAsString('''
## 1.0.0-rc.9

- Final RC.
''');
    }
    await _writeRelease(root, names, '1.0.0-rc.9', '>=1.0.0-rc.9 <1.0.0');
    await _writeLedger(root, const <String, Object?>{
      'statusPolicy': <String, Object?>{
        'reviewAuthority': <String, Object?>{
          'kind': 'MAINTAINER_DELEGATED_AUTOMATION',
          'name': 'Codex',
        },
      },
      'goals': <Object?>[],
      'baselines': <String, Object?>{'stableCandidate': null},
    });
    await File('${root.path}/tool/stable_readiness_decision.json')
        .writeAsString('{}');
    await _run(root, 'git', const <String>['init', '-q', '-b', 'main']);
    await _run(root, 'git', const <String>['config', 'user.name', 'ftr']);
    await _run(root, 'git', const <String>[
      'config',
      'user.email',
      'ftr@tuta.com',
    ]);
    await _run(root, 'git', const <String>['add', '.']);
    await _run(root, 'git', const <String>['commit', '-qm', 'final rc']);
    final rcSha = await _head(root);

    await File('${root.path}/pubspec.yaml').writeAsString('''
name: fixture
version: 1.0.0
''');
    for (final name in names) {
      final package = Directory('${root.path}/packages/$name');
      await File('${package.path}/pubspec.yaml').writeAsString('''
name: $name
version: 1.0.0
''');
      final previous = File('${package.path}/CHANGELOG.md').readAsStringSync();
      await File('${package.path}/CHANGELOG.md').writeAsString('''
## 1.0.0

- Stable promotion only.

$previous''');
    }
    await _writeRelease(root, names, '1.0.0', '>=1.0.0 <1.1.0');
    await _run(root, 'git', const <String>['add', '.']);
    await _run(root, 'git', const <String>[
      'commit',
      '-qm',
      'stable candidate',
    ]);
    final stableSha = await _head(root);
    final stableTree = (await _run(root, 'git', <String>[
      'show',
      '-s',
      '--format=%T',
      stableSha,
    ])).stdout.toString().trim();
    await _run(root, 'git', <String>[
      'update-ref',
      'refs/remotes/origin/main',
      stableSha,
    ]);

    const manifestDigest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await File('${root.path}/tool/stable_readiness_decision.json')
        .writeAsString(
          jsonEncode(<String, Object?>{
            'state': 'READY_FOR_1_0',
            'rcSourceSha': rcSha,
            'rcManifestSha256': manifestDigest,
          }),
        );
    await File('${root.path}/tool/stable_candidate_record.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'goal': 'V1-18',
        'state': 'VALIDATED',
        'candidateId': 'stable-1.0.0-candidate',
        'stableVersion': '1.0.0',
        'sourceSha': stableSha,
        'sourceTree': stableTree,
        'finalRcSourceSha': rcSha,
        'finalRcManifestSha256': manifestDigest,
        'validatedAt': '2026-08-25T23:00:00Z',
        'reviewedBy': <String>['Codex'],
        'workflowRuns': <Map<String, Object?>>[
          _workflow('CI', 1, stableSha),
          _workflow('Security', 2, stableSha),
        ],
        'gateReceipts': <Map<String, Object?>>[
          for (final gate in const <String>[
            'clean-clone',
            'release-audit',
            'sbom',
            'licenses',
            'publish-dry-runs',
          ])
            <String, Object?>{
              'gate': gate,
              'sourceSha': stableSha,
              'result': 'passed',
              'completedAt': '2026-08-25T22:59:00Z',
            },
        ],
        'artifactDigests': <Map<String, Object?>>[
          for (final artifact in const <String>[
            'sbom',
            'licenses',
            'package-manifest',
          ])
            <String, Object?>{
              'artifact': artifact,
              'sourceSha': stableSha,
              'sha256': manifestDigest,
            },
        ],
        'blockers': <String>[],
      }),
    );
    await _writeLedger(root, <String, Object?>{
      'statusPolicy': <String, Object?>{
        'reviewAuthority': <String, Object?>{
          'kind': 'MAINTAINER_DELEGATED_AUTOMATION',
          'name': 'Codex',
        },
      },
      'goals': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'V1S-17',
          'status': 'COMPLETE',
          'sourceSha': rcSha,
        },
      ],
      'baselines': <String, Object?>{
        'stableCandidate': <String, Object?>{
          'sha': stableSha,
          'tree': stableTree,
          'finalRcSha': rcSha,
        },
      },
    });
    await _run(root, 'git', const <String>['add', '.']);
    await _run(root, 'git', const <String>[
      'commit',
      '-qm',
      'record stable evidence',
    ]);
    return _FormalFixture(root);
  }

  Future<ProcessResult> check({bool requireAuthorization = false}) =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/check_stable_candidate.dart',
        '--root',
        root.path,
        if (requireAuthorization) '--require-publication-authorization',
      ]);

  Map<String, Object?> readCandidate() => jsonDecode(
    File('${root.path}/tool/stable_candidate_record.json').readAsStringSync(),
  ) as Map<String, Object?>;

  Future<void> writeCandidate(Map<String, Object?> value) =>
      File('${root.path}/tool/stable_candidate_record.json')
          .writeAsString(jsonEncode(value));

  Future<void> dispose() => root.delete(recursive: true);
}

Future<void> _writeRelease(
  Directory root,
  List<String> names,
  String cohort,
  String constraint,
) => File('${root.path}/tool/package_release_contract.json').writeAsString(
  jsonEncode(<String, Object?>{
    'cohortVersion': cohort,
    'internalConstraint': constraint,
    'publicationOrder': names,
  }),
);

Future<void> _writeLedger(Directory root, Map<String, Object?> value) =>
    File('${root.path}/tool/goal_gates.json').writeAsString(jsonEncode(value));

Future<String> _head(Directory root) async => (await _run(
  root,
  'git',
  const <String>['rev-parse', 'HEAD'],
)).stdout.toString().trim();

Map<String, Object?> _workflow(String name, int id, String sourceSha) =>
    <String, Object?>{
      'workflow': name,
      'runId': id,
      'url': 'https://example.invalid/actions/$id',
      'sourceSha': sourceSha,
      'conclusion': 'success',
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
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed: ${result.stderr}',
    );
  }
  return result;
}
