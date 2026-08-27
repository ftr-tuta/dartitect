import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts an explicit fail-closed pre-decision contract', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(contractOnly: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('NOT_READY_FOR_1_0_RC'));
  });

  test('formal gate rejects the pre-decision state', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Formal RC readiness is not granted'));
  });

  test('rejects coupled readiness and authorization records', () async {
    final fixture = await _Fixture.create(ready: true);
    addTearDown(fixture.dispose);
    final authorization = fixture.read('rc_distribution_authorization.json');
    authorization['authorizationId'] = authorization['readinessDecisionId'];
    await fixture.write('rc_distribution_authorization.json', authorization);

    final result = await fixture.check(contractOnly: true);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('incomplete or coupled'));
  });

  test(
    'accepts exact-SHA ready decision with later channel authorization',
    () async {
      final fixture = await _Fixture.create(ready: true);
      addTearDown(fixture.dispose);

      final result = await fixture.check();

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('separately authorized signed-bundle'));
    },
  );
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  static Future<_Fixture> create({bool ready = false}) async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-rc-readiness-',
    );
    await Directory('${root.path}/tool').create(recursive: true);
    await File('${root.path}/README.md').writeAsString('candidate\n');
    await _run(root, 'git', const <String>['init', '-q']);
    await _run(root, 'git', const <String>['config', 'user.name', 'ftr']);
    await _run(root, 'git', const <String>[
      'config',
      'user.email',
      'ftr@tuta.com',
    ]);
    await _run(root, 'git', const <String>['add', 'README.md']);
    await _run(root, 'git', const <String>['commit', '-qm', 'candidate']);
    final sha = (await _run(root, 'git', const <String>[
      'rev-parse',
      'HEAD',
    ])).stdout.toString().trim();
    final tree = (await _run(root, 'git', <String>[
      'show',
      '-s',
      '--format=%T',
      sha,
    ])).stdout.toString().trim();
    const cohort = '1.0.0-rc.2';
    const authority = 'Codex';
    const required = <String>[
      'V1S-00',
      'V1S-01',
      'V1S-02',
      'V1S-03',
      'V1S-04',
      'V1S-05',
      'V1S-06',
      'V1S-07',
      'V1S-08',
      'V1S-09',
      'V1S-10',
      'V1S-11',
      'V1S-12',
      'V1S-13',
      'V1S-14',
    ];
    final fixture = _Fixture(root);
    await fixture.write('package_release_contract.json', <String, Object?>{
      'cohortVersion': cohort,
    });
    await fixture.write('rc_candidate_contract.json', <String, Object?>{
      'cohortVersion': cohort,
      'candidateState': ready ? 'ASSEMBLED' : 'ASSEMBLY_IN_PROGRESS',
      'sourceSha': ready ? sha : null,
      'sourceTree': ready ? tree : null,
      'targetChannel': ready ? 'signed-bundle' : 'UNSELECTED',
    });
    await fixture.write('rc_readiness_decision.json', <String, Object?>{
      'schemaVersion': 1,
      'goal': 'V1S-15',
      'cohortVersion': cohort,
      'state': ready ? 'READY_FOR_1_0_RC' : 'NOT_READY_FOR_1_0_RC',
      'decisionId': ready ? 'rc1-readiness' : null,
      'sourceSha': ready ? sha : null,
      'sourceTree': ready ? tree : null,
      'recordedAt': ready ? '2026-08-25T12:00:00Z' : null,
      'reviewedBy': ready ? <String>[authority] : <String>[],
      'requiredWorkflowNames': <String>['CI', 'Security'],
      'requiredGoalIds': required,
      'blockers': ready ? <String>[] : <String>['Evidence is incomplete.'],
    });
    await fixture.write('rc_distribution_authorization.json', <String, Object?>{
      'schemaVersion': 1,
      'goal': 'V1S-15',
      'cohortVersion': cohort,
      'state': ready ? 'AUTHORIZED' : 'NOT_AUTHORIZED',
      'authorizationId': ready ? 'rc1-signed-bundle-authorization' : null,
      'readinessDecisionId': ready ? 'rc1-readiness' : null,
      'sourceSha': ready ? sha : null,
      'channel': ready ? 'signed-bundle' : 'UNSELECTED',
      'recordedAt': ready ? '2026-08-25T12:01:00Z' : null,
      'reviewedBy': ready ? <String>[authority] : <String>[],
      'allowedChannels': <String>['pub-dev-prerelease', 'signed-bundle'],
      'separateFromReadinessDecision': true,
    });
    await fixture.write('goal_gates.json', <String, Object?>{
      'releaseStatus': ready ? 'READY_FOR_1_0_RC' : 'NOT_READY_FOR_1_0_RC',
      'roadmap': <String, Object?>{
        'requiredGoalIds': <String>[
          ...required,
          'V1S-15',
          'V1S-16',
          'V1S-17',
          'V1-18',
        ],
      },
      'statusPolicy': <String, Object?>{
        'reviewAuthority': <String, Object?>{
          'kind': 'MAINTAINER_DELEGATED_AUTOMATION',
          'name': authority,
        },
      },
      'baselines': <String, Object?>{
        'rcCandidates': ready
            ? <Map<String, Object?>>[
                <String, Object?>{
                  'sha': sha,
                  'tree': tree,
                  'workflowRuns': <Map<String, Object?>>[
                    _workflow('CI', 1, sha),
                    _workflow('Security', 2, sha),
                  ],
                },
              ]
            : <Object?>[],
      },
      'goals': <Map<String, Object?>>[
        for (final id in required)
          <String, Object?>{
            'id': id,
            'status': ready ? 'COMPLETE' : 'IN_PROGRESS',
            'sourceSha': ready ? sha : null,
            'reviewedBy': ready ? <String>[authority] : <String>[],
            'completedAt': ready ? '2026-08-25T11:59:00Z' : null,
          },
      ],
    });
    return fixture;
  }

  Map<String, Object?> read(String name) =>
      jsonDecode(File('${root.path}/tool/$name').readAsStringSync())
          as Map<String, Object?>;

  Future<void> write(String name, Map<String, Object?> value) =>
      File('${root.path}/tool/$name').writeAsString(jsonEncode(value));

  Future<ProcessResult> check({bool contractOnly = false}) {
    final checker = File(
      '${Directory.current.path}/tool/check_rc_readiness.dart',
    );
    return Process.run(Platform.resolvedExecutable, <String>[
      checker.path,
      '--root',
      root.path,
      if (contractOnly) '--contract-only',
    ]);
  }

  Future<void> dispose() => root.delete(recursive: true);
}

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
