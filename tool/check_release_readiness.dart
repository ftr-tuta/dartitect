import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'titect_evidence.dart';

final _gitSha = RegExp(r'^[0-9a-f]{40}$');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final environment = Platform.environment;
    final ciRunAttempt = int.tryParse(environment['CI_RUN_ATTEMPT'] ?? '');
    if (environment['GITHUB_ACTIONS'] != 'true' ||
        environment['RUNNER_ENVIRONMENT'] != 'github-hosted' ||
        environment['GITHUB_WORKFLOW'] != 'Release' ||
        environment['GITHUB_EVENT_NAME'] != 'workflow_dispatch' ||
        ciRunAttempt == null ||
        ciRunAttempt <= 0) {
      throw StateError(
        'Release readiness is restricted to the manual hosted Release workflow.',
      );
    }
    final root = options.root;
    final policy = _object(
      jsonDecode(
        File('${root.path}/tool/actions_readiness_policy.json')
            .readAsStringSync(),
      ),
    );
    final release = _object(policy['release']);
    if (release['workflowPath'] != '.github/workflows/release.yaml' ||
        release['manualOnly'] != true ||
        !_sameStrings(_strings(release['requiredInputs']), const <String>[
          'source_sha',
          'ci_run_id',
        ])) {
      throw const FormatException('Release readiness policy is incomplete.');
    }
    final stableValidation = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '${root.path}/tool/check_stable_candidate.dart',
        '--root=${root.path}',
        '--contract-only',
      ],
      workingDirectory: root.path,
    );
    if (stableValidation.exitCode != 0) {
      throw StateError(
        'Stable release rejected candidate evidence: '
        '${stableValidation.stderr}',
      );
    }
    final head = (await _git(root, const <String>['rev-parse', 'HEAD'])).trim();
    final tree = (await _git(root, const <String>[
      'show',
      '-s',
      '--format=%T',
      'HEAD',
    ])).trim();
    if (head != options.sourceSha) {
      throw StateError('source_sha does not match the checked-out commit.');
    }
    final manifest = _object(jsonDecode(options.manifest.readAsStringSync()));
    if (manifest['schemaVersion'] != 1 ||
        manifest['artifact'] != 'actions-readiness-v1' ||
        manifest['authority'] != 'github-actions' ||
        manifest['workflow'] != 'CI' ||
        manifest['requiredCheck'] != 'CI / Required' ||
        manifest['sourceSha'] != options.sourceSha ||
        manifest['sourceTree'] != tree ||
        manifest['ref'] != 'refs/heads/main' ||
        manifest['event'] != 'push' ||
        manifest['runId'] != options.ciRunId ||
        manifest['runAttempt'] != ciRunAttempt) {
      throw StateError(
        'Readiness artifact does not match source_sha and ci_run_id.',
      );
    }
    final jobs = _objects(manifest['jobs']);
    final requiredJobs = _strings(policy['requiredJobs']);
    if (jobs.length != requiredJobs.length ||
        jobs.asMap().entries.any(
          (entry) =>
              entry.value['id'] != requiredJobs[entry.key] ||
              entry.value['conclusion'] != 'success',
        )) {
      throw StateError(
        'The referenced CI run did not pass every required job.',
      );
    }
    final digests = _objects(manifest['artifactDigests']);
    final expectedPaths = <String>{
      for (final name in titectEvidenceFiles) 'titect/$name',
      for (final cell in _strings(policy['nativeCells'])) 'native/$cell.json',
      for (final path in _strings(policy['repositoryArtifacts']))
        'repository/$path',
    };
    if (digests.length != expectedPaths.length ||
        !digests
            .map((item) => item['path'])
            .toSet()
            .containsAll(expectedPaths)) {
      throw StateError('Readiness artifact digest inventory is incomplete.');
    }
    for (final item in digests) {
      final path = item['path'];
      final expected = item['sha256'];
      if (path is! String ||
          !expectedPaths.contains(path) ||
          expected is! String ||
          !_sha256.hasMatch(expected)) {
        throw StateError('Readiness artifact digest entry is invalid.');
      }
      final file = File('${options.manifest.parent.path}/$path');
      if (!file.existsSync() || await _digest(file) != expected) {
        throw StateError('Readiness artifact is expired, missing, or altered.');
      }
    }
    validateTitectEvidence(
      root: root,
      evidence: Directory('${options.manifest.parent.path}/titect'),
      sourceSha: options.sourceSha,
      sourceTree: tree,
      runId: options.ciRunId,
      runAttempt: ciRunAttempt,
    );
    stdout.writeln(
      'Release source ${options.sourceSha} is authorized by CI run '
      '${options.ciRunId}; actor ${environment['GITHUB_ACTOR']}.',
    );
  } on Object catch (error) {
    stderr.writeln('Release readiness rejected: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

Future<String> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return result.stdout as String;
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?> ||
      value.any((item) => item is! Map<String, Object?>)) {
    throw const FormatException('Expected a JSON object list.');
  }
  return value.cast<Map<String, Object?>>();
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

final class _Options {
  const _Options({
    required this.root,
    required this.sourceSha,
    required this.ciRunId,
    required this.manifest,
  });

  factory _Options.parse(List<String> arguments) {
    Directory? root;
    String? sourceSha;
    int? ciRunId;
    File? manifest;
    for (final argument in arguments) {
      if (argument.startsWith('--root=')) {
        if (root != null) throw const FormatException('Duplicate root.');
        root = Directory(argument.substring('--root='.length)).absolute;
      } else if (argument.startsWith('--source-sha=')) {
        if (sourceSha != null)
          throw const FormatException('Duplicate source SHA.');
        sourceSha = argument.substring('--source-sha='.length);
      } else if (argument.startsWith('--ci-run-id=')) {
        if (ciRunId != null)
          throw const FormatException('Duplicate CI run ID.');
        ciRunId = int.tryParse(argument.substring('--ci-run-id='.length));
      } else if (argument.startsWith('--manifest=')) {
        if (manifest != null)
          throw const FormatException('Duplicate manifest.');
        manifest = File(argument.substring('--manifest='.length)).absolute;
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    if (sourceSha == null ||
        !_gitSha.hasMatch(sourceSha) ||
        ciRunId == null ||
        ciRunId <= 0 ||
        manifest == null ||
        !manifest.existsSync() ||
        (root != null && !root.existsSync())) {
      throw const FormatException(
        'Required valid --source-sha, --ci-run-id, and --manifest.',
      );
    }
    return _Options(
      root: root ?? File.fromUri(Platform.script).parent.parent.absolute,
      sourceSha: sourceSha,
      ciRunId: ciRunId,
      manifest: manifest,
    );
  }

  final Directory root;
  final String sourceSha;
  final int ciRunId;
  final File manifest;
}
