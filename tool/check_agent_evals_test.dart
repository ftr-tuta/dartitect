import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts the checked-in corpus and both fixed matrices', () async {
    final checker = await Process.run(Platform.resolvedExecutable, <String>[
      'tool/check_agent_evals.dart',
    ]);
    expect(checker.exitCode, 0, reason: '${checker.stdout}\n${checker.stderr}');

    for (final arguments in <List<String>>[
      <String>['--dry-run', '--suite=required', '--repetitions=1'],
      <String>['--dry-run', '--suite=trend', '--repetitions=3'],
    ]) {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'tool/agent_evals/run.dart',
        ...arguments,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }
  });

  test('rejects a changed upstream pin', () async {
    final root = Directory.current.absolute;
    final temporary = await Directory.systemTemp.createTemp('agent-evals-v1-');
    addTearDown(() => temporary.delete(recursive: true));
    final corpus = jsonDecode(
      File('${root.path}/tool/agent_evals/corpus.json').readAsStringSync(),
    ) as Map<String, Object?>;
    corpus['pins'] = <String, String>{
      'flutterEvals': '0000000000000000000000000000000000000000',
      'flutterAgentPlugins': 'df9bebe7ec3c96f80f499e5d62ba1ebe81892500',
    };
    final changed = File('${temporary.path}/corpus.json');
    await changed.writeAsString(jsonEncode(corpus));

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'tool/check_agent_evals.dart',
      '--corpus=${changed.path}',
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('flutter/evals pin changed'));
  });

  test('runner rejects matrix drift as usage error', () async {
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'tool/agent_evals/run.dart',
      '--dry-run',
      '--suite=required',
      '--repetitions=3',
    ]);
    expect(result.exitCode, 64);
    expect(result.stderr, contains('requires exactly 1 repetition'));
  });
}
