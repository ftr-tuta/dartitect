import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory root;
  late Map<String, Object?> authority;
  late String emptyBaselineSha;

  setUpAll(() async {
    root = Directory.current.absolute;
    authority = jsonDecode(
      File('${root.path}/tool/goal_gates.json').readAsStringSync(),
    ) as Map<String, Object?>;
    emptyBaselineSha = await _createEmptyBaseline(root);
  });

  test('accepts the checked fail-closed authority', () async {
    final result = await _check(root);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test(
    'derives goal identifiers and dependencies entirely from JSON',
    () async {
      final fixture = _copyAuthority(authority);
      final roadmap = fixture['roadmap']! as Map<String, Object?>;
      final goals = (fixture['goals']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final renames = <String, String>{
        for (var index = 0; index < goals.length; index += 1)
          goals[index]['id']! as String:
              'G-${index.toString().padLeft(2, '0')}',
      };
      roadmap['requiredGoalIds'] = <String>[
        for (final id
            in (roadmap['requiredGoalIds']! as List<Object?>).cast<String>())
          renames[id]!,
      ];
      for (final goal in goals) {
        goal['id'] = renames[goal['id']]!;
        goal['dependsOn'] = <String>[
          for (final id in (goal['dependsOn']! as List<Object?>).cast<String>())
            renames[id]!,
        ];
      }

      final result = await _check(root, fixture);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test('rejects a required goal omitted from the authority', () async {
    final fixture = _copyAuthority(authority);
    (fixture['goals']! as List<Object?>).removeWhere(
      (goal) => (goal! as Map<String, Object?>)['id'] == 'V1S-06',
    );
    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Required goals are missing'));
  });

  test('rejects dependencies that are not topologically ordered', () async {
    final fixture = _copyAuthority(authority);
    final goals = (fixture['goals']! as List<Object?>)
        .cast<Map<String, Object?>>();
    goals.first['dependsOn'] = <String>[goals.last['id']! as String];
    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('not topological'));
  });

  test('rejects required cancellation even with review metadata', () async {
    final fixture = _copyAuthority(authority);
    final goal = _goal(fixture, 'V1S-10');
    goal['status'] = 'CANCELLED';
    goal['cancellation'] = <String, Object?>{
      'justification': 'replaced by an explicitly reviewed successor',
      'owner': 'maintainer',
      'reviewedBy': <String>['Codex'],
    };
    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Required goal V1S-10 cannot be CANCELLED'));
  });

  test('rejects completion before required predecessors', () async {
    final fixture = _copyAuthority(authority);
    _complete(_goal(fixture, 'V1S-01'));
    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('cannot be COMPLETE before'));
  });

  test('rejects remote evidence from a different source SHA', () async {
    final fixture = _copyAuthority(authority);
    final goal = _goal(fixture, 'V1S-00');
    _complete(goal, sourceSha: emptyBaselineSha);
    (goal['workflowRuns']! as List<Object?>).single as Map<String, Object?>
      ..['sourceSha'] = '0000000000000000000000000000000000000000';
    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('cross-SHA workflow run'));
  });

  test('rejects a reviewer outside the delegated authority', () async {
    final fixture = _copyAuthority(authority);
    final goal = _goal(fixture, 'V1S-00');
    _complete(goal, sourceSha: emptyBaselineSha);
    goal['reviewedBy'] = <String>['unlisted reviewer'];

    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('unauthorized reviewer'));
  });

  test('reopens a complete goal when a covered path changed', () async {
    final fixture = _copyAuthority(authority);
    final goal = _goal(fixture, 'V1S-00');
    _complete(goal, sourceSha: emptyBaselineSha);
    goal['coveredPaths'] = <String>['tool/check_goal_gates.dart'];
    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('must reopen'));
  });

  test('does not reopen a goal for receipt-only metadata', () async {
    final fixture = _copyAuthority(authority);
    final goal = _goal(fixture, 'V1S-00');
    _complete(goal, sourceSha: emptyBaselineSha);
    goal['coveredPaths'] = <String>['tool/goal_gates.json'];

    final result = await _check(root, fixture);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('rejects wildcard receipt-only paths', () async {
    final fixture = _copyAuthority(authority);
    (fixture['statusPolicy']! as Map<String, Object?>)['receiptOnlyPaths'] =
        <String>['docs/release/**'];

    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('unique exact safe paths'));
  });

  test('rejects target topology that differs from checked inventory', () async {
    final fixture = _copyAuthority(authority);
    (fixture['target']! as Map<String, Object?>)['packageCount'] = 15;
    final result = await _check(root, fixture);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Target topology does not match'));
  });

  test('accepts an empty pre-receipt baseline registry', () async {
    final fixture = _copyAuthority(authority);
    final baselines = fixture['baselines']! as Map<String, Object?>;
    expect(baselines['implementation'], isNull);
    expect(baselines['rcCandidates'], isEmpty);
    final result = await _check(root, fixture);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}

Map<String, Object?> _copyAuthority(Map<String, Object?> authority) =>
    jsonDecode(jsonEncode(authority)) as Map<String, Object?>;

Map<String, Object?> _goal(Map<String, Object?> authority, String id) =>
    (authority['goals']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((goal) => goal['id'] == id);

void _complete(
  Map<String, Object?> goal, {
  String sourceSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) {
  goal
    ..['status'] = 'COMPLETE'
    ..['sourceSha'] = sourceSha
    ..['workflowRuns'] = <Object?>[
      <String, Object?>{
        'workflow': 'CI',
        'runId': 1,
        'url': 'https://example.invalid/actions/runs/1',
        'sourceSha': sourceSha,
        'conclusion': 'success',
      },
    ]
    ..['reviewedBy'] = <String>['Codex']
    ..['completedAt'] = '2026-08-25T12:30:19Z';
}

Future<String> _createEmptyBaseline(Directory root) async {
  final treeProcess = await Process.start('git', const <String>[
    'mktree',
  ], workingDirectory: root.path);
  await treeProcess.stdin.close();
  final tree = (await utf8.decoder.bind(treeProcess.stdout).join()).trim();
  final treeError = await utf8.decoder.bind(treeProcess.stderr).join();
  expect(await treeProcess.exitCode, 0, reason: treeError);
  final commit = await Process.run(
    'git',
    <String>['commit-tree', tree, '-m', 'synthetic empty test baseline'],
    workingDirectory: root.path,
    environment: <String, String>{
      ...Platform.environment,
      'GIT_AUTHOR_NAME': 'fixture',
      'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
      'GIT_COMMITTER_NAME': 'fixture',
      'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
    },
  );
  expect(commit.exitCode, 0, reason: '${commit.stderr}');
  return (commit.stdout as String).trim();
}

Future<ProcessResult> _check(
  Directory root, [
  Map<String, Object?>? fixture,
]) async {
  File? file;
  if (fixture != null) {
    final directory = Directory.systemTemp.createTempSync(
      'dartitect-goal-gates-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    file = File('${directory.path}/goal_gates.json')
      ..writeAsStringSync(jsonEncode(fixture));
  }
  return Process.run('dart', <String>[
    'run',
    'tool/check_goal_gates.dart',
    if (file != null) '--file=${file.path}',
  ], workingDirectory: root.path);
}
