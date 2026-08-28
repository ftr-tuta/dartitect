import 'dart:convert';
import 'dart:io';

/// Runs the complete release audit from a disposable clone of exact `HEAD`.
Future<void> main() async {
  final source = File.fromUri(Platform.script).parent.parent.absolute;
  final status = await _git(source, const <String>['status', '--porcelain']);
  if (status.trim().isNotEmpty) {
    throw StateError(
      'The source tree must be clean before a clean-clone audit.',
    );
  }
  final revision = (await _git(source, const <String>[
    'rev-parse',
    'HEAD',
  ])).trim();
  final tree = (await _git(source, const <String>[
    'show',
    '-s',
    '--format=%T',
    'HEAD',
  ])).trim();
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-rc-clean-clone-',
  );
  final clone = Directory('${temporary.path}/repository');
  try {
    await _run(temporary, 'git', <String>[
      'clone',
      '--quiet',
      '--no-hardlinks',
      source.path,
      clone.path,
    ]);
    await _run(clone, 'git', <String>[
      'checkout',
      '--quiet',
      '--detach',
      revision,
    ]);
    await _run(clone, 'flutter', const <String>['pub', 'get']);
    await _run(clone, 'dart', <String>[
      'run',
      'tool/release_audit.dart',
      '--docs',
      '--publish-dry-run',
      '--author-revision=$revision',
    ]);
    final cloneStatus = await _git(clone, const <String>[
      'status',
      '--porcelain',
    ]);
    if (cloneStatus.trim().isNotEmpty) {
      throw StateError(
        'The clean-clone audit changed tracked files:\n$cloneStatus',
      );
    }
    final receiptDirectory = Directory('${source.path}/build/release-audit');
    await receiptDirectory.create(recursive: true);
    final receipt = File('${receiptDirectory.path}/clean-clone-$revision.json');
    await receipt.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'sourceSha': revision,
        'tree': tree,
        'cohortVersion': '1.0.0-rc.4',
        'commands': <String>['flutter pub get', 'dart run tool/release_audit.dart --docs --publish-dry-run --author-revision=$revision'],
        'trackedTreeClean': true,
        'result': 'PASS',
        'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
      })}\n',
      flush: true,
    );
    stdout.writeln('Clean-clone release audit passed for $revision.');
    stdout.writeln('Receipt: ${receipt.path}');
  } finally {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  }
}

Future<String> _git(Directory directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<void> _run(
  Directory directory,
  String executable,
  List<String> arguments,
) async {
  stdout.writeln('> $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows && executable == 'flutter',
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw StateError('$executable ${arguments.join(' ')} failed with $code.');
  }
}
