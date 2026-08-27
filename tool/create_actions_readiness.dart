import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isNotEmpty) {
      throw const FormatException(
        'create_actions_readiness takes no arguments.',
      );
    }
    final environment = Platform.environment;
    if (environment['GITHUB_ACTIONS'] != 'true' ||
        environment['RUNNER_ENVIRONMENT'] != 'github-hosted' ||
        environment['GITHUB_WORKFLOW'] != 'CI' ||
        environment['GITHUB_EVENT_NAME'] != 'push' ||
        environment['GITHUB_REF'] != 'refs/heads/main') {
      throw StateError(
        'Readiness manifests are produced only by CI pushes to main on a '
        'GitHub-hosted runner.',
      );
    }
    final root = File.fromUri(Platform.script).parent.parent.absolute;
    final policy = _readObject(
      File('${root.path}/tool/actions_readiness_policy.json'),
    );
    final sourceSha = _required(environment, 'GITHUB_SHA');
    final sourceTree = (await _run(root, <String>[
      'show',
      '-s',
      '--format=%T',
      sourceSha,
    ])).trim();
    final needs = _decodeObject(_required(environment, 'DARTITECT_NEEDS_JSON'));
    final requiredJobs = _strings(policy['requiredJobs']);
    if (needs.length != requiredJobs.length ||
        !needs.keys.toSet().containsAll(requiredJobs)) {
      throw StateError('Readiness job conclusion set is not exact.');
    }
    final jobs = <Map<String, Object?>>[];
    for (final id in requiredJobs) {
      final value = needs[id];
      if (value is! Map<String, Object?> || value['result'] != 'success') {
        throw StateError('Required job $id did not conclude success.');
      }
      jobs.add(<String, Object?>{'id': id, 'conclusion': 'success'});
    }

    final output = Directory('${root.path}/build/actions-readiness-v1');
    if (output.existsSync()) await output.delete(recursive: true);
    await output.create(recursive: true);
    final digests = <Map<String, Object?>>[];
    final nativeDirectory = Directory('${root.path}/build/native-evidence');
    for (final cell in _strings(policy['nativeCells'])) {
      final matches = nativeDirectory.existsSync()
          ? nativeDirectory
                .listSync(followLinks: false)
                .whereType<File>()
                .where(
                  (file) =>
                      file.path.endsWith('.json') &&
                      _readObject(file)['cellId'] == cell,
                )
                .toList()
          : const <File>[];
      if (matches.length != 1) {
        throw StateError('Expected one current-run native manifest for $cell.');
      }
      final destination = File('${output.path}/native/$cell.json');
      await destination.parent.create(recursive: true);
      await matches.single.copy(destination.path);
      digests.add(<String, Object?>{
        'path': 'native/$cell.json',
        'kind': 'native-manifest',
        'sha256': await _digest(destination),
      });
    }
    for (final path in _strings(policy['repositoryArtifacts'])) {
      final source = File('${root.path}/$path');
      if (!source.existsSync()) {
        throw StateError('Required repository artifact is missing: $path.');
      }
      final destination = File('${output.path}/repository/$path');
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
      digests.add(<String, Object?>{
        'path': 'repository/$path',
        'kind': 'repository-artifact',
        'sha256': await _digest(destination),
      });
    }
    digests.sort(
      (left, right) =>
          (left['path']! as String).compareTo(right['path']! as String),
    );
    final runId = int.parse(_required(environment, 'GITHUB_RUN_ID'));
    final runAttempt = int.parse(_required(environment, 'GITHUB_RUN_ATTEMPT'));
    final repository = _required(environment, 'GITHUB_REPOSITORY');
    final manifest = <String, Object?>{
      'schemaVersion': 1,
      'artifact': 'actions-readiness-v1',
      'authority': 'github-actions',
      'workflow': 'CI',
      'requiredCheck': 'CI / Required',
      'sourceSha': sourceSha,
      'sourceTree': sourceTree,
      'ref': 'refs/heads/main',
      'event': 'push',
      'runId': runId,
      'runAttempt': runAttempt,
      'repository': repository,
      'url': 'https://github.com/$repository/actions/runs/$runId',
      'jobs': jobs,
      'artifactDigests': digests,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    final manifestName = (_object(policy['artifact'])['manifest']! as String);
    await File('${output.path}/$manifestName').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      flush: true,
    );
    stdout.writeln('Created actions-readiness-v1 for $sourceSha.');
  } on Object catch (error) {
    stderr.writeln('Actions readiness creation failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

Future<String> _run(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

String _required(Map<String, String> environment, String key) {
  final value = environment[key];
  if (value == null || value.trim().isEmpty) {
    throw StateError('Required Actions environment $key is absent.');
  }
  return value;
}

Map<String, Object?> _readObject(File file) =>
    _decodeObject(file.readAsStringSync());

Map<String, Object?> _decodeObject(String source) {
  final value = jsonDecode(source);
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected one JSON object.');
  }
  return value;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object field.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}
