import 'dart:io';

import 'titect_evidence.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1) {
      throw const FormatException('Expected the paired evidence directory.');
    }
    final root = File.fromUri(Platform.script).parent.parent;
    Future<String> git(String revision) async {
      final result = await Process.run('git', [
        'rev-parse',
        revision,
      ], workingDirectory: root.path);
      if (result.exitCode != 0) throw StateError('${result.stderr}');
      return (result.stdout as String).trim();
    }

    validateTitectEvidence(
      root: root,
      evidence: Directory(arguments.single),
      sourceSha: await git('HEAD'),
      sourceTree: await git('HEAD^{tree}'),
      runId: int.parse(Platform.environment['GITHUB_RUN_ID'] ?? '0'),
      runAttempt: int.parse(Platform.environment['GITHUB_RUN_ATTEMPT'] ?? '0'),
    );
    stdout.writeln(
      'Paired Titect evidence passed for this committed CI source.',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
