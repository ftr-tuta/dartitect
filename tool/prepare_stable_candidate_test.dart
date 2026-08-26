import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('refuses before any file write when V1S-17 is incomplete', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-prepare-stable-',
    );
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/tool').create(recursive: true);
    await File('${root.path}/tool/check_rc_validation.dart').writeAsString('''
import 'dart:io';
void main() {
  stderr.writeln('READY_FOR_1_0 is absent.');
  exitCode = 1;
}
''');
    final sentinel = File('${root.path}/sentinel.txt');
    await sentinel.writeAsString('unchanged\n');
    await _git(root, const <String>['init', '-q']);
    await _git(root, const <String>['config', 'user.name', 'ftr']);
    await _git(root, const <String>['config', 'user.email', 'ftr@tuta.com']);
    await _git(root, const <String>['add', '.']);
    await _git(root, const <String>['commit', '-qm', 'fixture']);

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '${Directory.current.path}/tool/prepare_stable_candidate.dart',
      '--root',
      root.path,
    ]);
    final status = await _git(root, const <String>['status', '--porcelain']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('before any file write'));
    expect(await sentinel.readAsString(), 'unchanged\n');
    expect(status.stdout.toString().trim(), isEmpty);
  });

  test('rejects malformed arguments before accessing the workspace', () async {
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '${Directory.current.path}/tool/prepare_stable_candidate.dart',
      '--unknown',
    ]);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Usage:'));
  });
}

Future<ProcessResult> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result;
}
