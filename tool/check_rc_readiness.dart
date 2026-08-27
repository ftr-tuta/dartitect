import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

/// Validates the immutable Actions readiness policy or a formal current-run
/// manifest. Structural mode is intentionally unable to declare readiness.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root = options.root ?? File.fromUri(Platform.script).parent.parent;
    final policy = _read(root, 'tool/actions_readiness_policy.json');
    final errors = <String>[];
    _validatePolicy(root, policy, errors);
    if (!options.contractOnly && errors.isEmpty) {
      await _validateFormal(root, policy, options.manifest!, errors);
    }
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    if (options.contractOnly) {
      stdout.writeln(
        'Actions readiness policy is structurally valid; local mode cannot '
        'declare release readiness.',
      );
    } else {
      stdout.writeln(
        'Formal Actions readiness passed for the current main CI execution.',
      );
    }
  } on Object catch (error) {
    stderr.writeln('Actions readiness could not be validated: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

void _validatePolicy(
  Directory root,
  Map<String, Object?> policy,
  List<String> errors,
) {
  final artifact = _objectOrNull(policy['artifact']);
  final publication = _objectOrNull(policy['publication']);
  if (policy['schemaVersion'] != 1 ||
      policy['authority'] != 'github-actions' ||
      policy['workflow'] != 'CI' ||
      policy['workflowPath'] != '.github/workflows/ci.yaml' ||
      !_same(_stringsOrNull(policy['events']), const <String>[
        'pull_request',
        'merge_group',
        'push-main',
      ]) ||
      policy['requiredCheck'] != 'CI / Required' ||
      policy['releaseBranch'] != 'refs/heads/main' ||
      policy['formalEvent'] != 'push' ||
      artifact?['name'] != 'actions-readiness-v1' ||
      artifact?['manifest'] != 'actions-readiness-v1.json' ||
      artifact?['retentionDays'] != 90 ||
      policy['localValidationCanDeclareReadiness'] != false ||
      policy['hostedRunnersOnly'] != true) {
    errors.add('The immutable Actions readiness policy is incomplete.');
  }
  if (!_same(_stringsOrNull(policy['requiredJobs']), const <String>[
    'linux',
    'windows',
    'macos',
    'android-emulator',
    'drift-web',
    'clean-clone',
    'git-consumption',
    'osv',
  ])) {
    errors.add('The required Actions job set is not exact.');
  }
  if (!_same(_stringsOrNull(policy['nativeCells']), const <String>[
    'android-media-floor-build',
    'android-media-current-emulator',
    'ios-media-floor-build',
    'ios-privacy-floor-build',
    'ios-current-simulator',
  ])) {
    errors.add('The readiness policy native matrix is not the nominal five.');
  }
  if (!_same(_stringsOrNull(policy['repositoryArtifacts']), const <String>[
    'docs/release/sbom.spdx.json',
    'docs/release/dependency-licenses.json',
    'tool/api_surface.snapshot.json',
    'tool/package_release_contract.json',
  ])) {
    errors.add('The readiness repository artifact set is not exact.');
  }
  if (publication?['workflowPath'] != '.github/workflows/publish.yaml' ||
      publication?['manualOnly'] != true ||
      !_same(_stringsOrNull(publication?['requiredInputs']), const <String>[
        'source_sha',
        'ci_run_id',
        'channel',
      ]) ||
      !_same(_stringsOrNull(publication?['channels']), const <String>[
        'github-release',
        'pub-dev-prerelease',
        'pub-dev-stable',
      ])) {
    errors.add('The manual publication policy is incomplete.');
  }
  for (final path in const <String>[
    '.github/workflows/ci.yaml',
    '.github/workflows/publish.yaml',
    'tool/native_evidence_contract.json',
  ]) {
    if (!File('${root.path}/$path').existsSync()) {
      errors.add('Actions readiness policy dependency is missing: $path.');
    }
  }
}

Future<void> _validateFormal(
  Directory root,
  Map<String, Object?> policy,
  File manifestFile,
  List<String> errors,
) async {
  final environment = Platform.environment;
  if (environment['GITHUB_ACTIONS'] != 'true' ||
      environment['RUNNER_ENVIRONMENT'] != 'github-hosted' ||
      environment['GITHUB_WORKFLOW'] != policy['workflow'] ||
      environment['GITHUB_EVENT_NAME'] != policy['formalEvent'] ||
      environment['GITHUB_REF'] != policy['releaseBranch']) {
    errors.add(
      'Formal readiness is restricted to the current hosted CI push on main.',
    );
    return;
  }
  if (!manifestFile.existsSync()) {
    errors.add('The current-run readiness manifest is missing.');
    return;
  }
  final manifest = _decodeObject(manifestFile.readAsStringSync());
  if (!_sameSet(manifest.keys.toSet(), const <String>{
    'schemaVersion',
    'artifact',
    'authority',
    'workflow',
    'requiredCheck',
    'sourceSha',
    'sourceTree',
    'ref',
    'event',
    'runId',
    'runAttempt',
    'repository',
    'url',
    'jobs',
    'artifactDigests',
    'createdAt',
  })) {
    errors.add('Readiness manifest fields do not match schema v1.');
  }
  final sourceSha = environment['GITHUB_SHA'];
  final runId = int.tryParse(environment['GITHUB_RUN_ID'] ?? '');
  final runAttempt = int.tryParse(environment['GITHUB_RUN_ATTEMPT'] ?? '');
  final repository = environment['GITHUB_REPOSITORY'];
  final sourceTree = sourceSha == null
      ? ''
      : (await _git(root, <String>[
          'show',
          '-s',
          '--format=%T',
          sourceSha,
        ])).trim();
  if (manifest['schemaVersion'] != 1 ||
      manifest['artifact'] != _objectOrNull(policy['artifact'])?['name'] ||
      manifest['authority'] != policy['authority'] ||
      manifest['workflow'] != policy['workflow'] ||
      manifest['requiredCheck'] != policy['requiredCheck'] ||
      manifest['sourceSha'] != sourceSha ||
      manifest['sourceTree'] != sourceTree ||
      manifest['ref'] != policy['releaseBranch'] ||
      manifest['event'] != policy['formalEvent'] ||
      manifest['runId'] != runId ||
      manifest['runAttempt'] != runAttempt ||
      manifest['repository'] != repository ||
      manifest['url'] != 'https://github.com/$repository/actions/runs/$runId' ||
      !_validUtc(manifest['createdAt'])) {
    errors.add('Readiness manifest is not bound to the current CI execution.');
  }

  final jobs = _objectsOrNull(manifest['jobs']);
  final requiredJobs = _stringsOrNull(policy['requiredJobs']);
  if (jobs == null ||
      requiredJobs == null ||
      jobs.length != requiredJobs.length ||
      jobs.asMap().entries.any(
        (entry) =>
            entry.value['id'] != requiredJobs[entry.key] ||
            entry.value['conclusion'] != 'success' ||
            !_sameSet(entry.value.keys.toSet(), const <String>{
              'id',
              'conclusion',
            }),
      )) {
    errors.add('Readiness job conclusions are missing, skipped, or failed.');
  }

  final digests = _objectsOrNull(manifest['artifactDigests']);
  final nativeCells = _stringsOrNull(policy['nativeCells']) ?? const <String>[];
  final repositoryArtifacts =
      _stringsOrNull(policy['repositoryArtifacts']) ?? const <String>[];
  final expectedPaths = <String>{
    for (final cell in nativeCells) 'native/$cell.json',
    for (final path in repositoryArtifacts) 'repository/$path',
  };
  if (digests == null ||
      digests.length != expectedPaths.length ||
      digests.map((item) => item['path']).toSet().length != digests.length ||
      !digests.map((item) => item['path']).toSet().containsAll(expectedPaths)) {
    errors.add('Readiness artifact digest set is not exact.');
    return;
  }
  final artifactRoot = manifestFile.parent;
  for (final item in digests) {
    final path = item['path'];
    final expected = item['sha256'];
    if (path is! String ||
        !expectedPaths.contains(path) ||
        expected is! String ||
        !_digestPattern.hasMatch(expected) ||
        (item['kind'] != 'native-manifest' &&
            item['kind'] != 'repository-artifact') ||
        !_sameSet(item.keys.toSet(), const <String>{
          'path',
          'kind',
          'sha256',
        })) {
      errors.add('Readiness artifact digest entry is invalid.');
      continue;
    }
    final file = File('${artifactRoot.path}/$path');
    if (!file.existsSync() || await _digest(file) != expected) {
      errors.add('Readiness artifact was altered or is missing: $path.');
    }
  }
}

Future<String> _git(Directory root, List<String> arguments) async {
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

Map<String, Object?> _read(Directory root, String path) =>
    _decodeObject(File('${root.path}/$path').readAsStringSync());

Map<String, Object?> _decodeObject(String source) {
  final value = jsonDecode(source);
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected one JSON object.');
  }
  return value;
}

Map<String, Object?>? _objectOrNull(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<Map<String, Object?>>? _objectsOrNull(Object? value) =>
    value is List<Object?> &&
        value.every((item) => item is Map<String, Object?>)
    ? value.cast<Map<String, Object?>>()
    : null;

List<String>? _stringsOrNull(Object? value) =>
    value is List<Object?> && value.every((item) => item is String)
    ? value.cast<String>()
    : null;

bool _same(List<String>? left, List<String> right) =>
    left != null &&
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

bool _sameSet(Set<Object?> left, Set<Object?> right) =>
    left.length == right.length && left.containsAll(right);

bool _validUtc(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed != null && parsed.isUtc && (value as String).endsWith('Z');
}

final class _Options {
  const _Options({
    required this.contractOnly,
    required this.manifest,
    this.root,
  });

  factory _Options.parse(List<String> arguments) {
    var contractOnly = false;
    Directory? root;
    File? manifest;
    for (final argument in arguments) {
      if (argument == '--contract-only') {
        if (contractOnly)
          throw const FormatException('Duplicate --contract-only.');
        contractOnly = true;
      } else if (argument.startsWith('--root=')) {
        if (root != null || argument.substring(7).trim().isEmpty) {
          throw const FormatException('Invalid or duplicate --root=.');
        }
        root = Directory(argument.substring(7)).absolute;
      } else if (argument.startsWith('--manifest=')) {
        if (manifest != null || argument.substring(11).trim().isEmpty) {
          throw const FormatException('Invalid or duplicate --manifest=.');
        }
        manifest = File(argument.substring(11)).absolute;
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    if (contractOnly == (manifest != null)) {
      throw const FormatException(
        'Use exactly one mode: --contract-only or --manifest=<path>.',
      );
    }
    return _Options(contractOnly: contractOnly, manifest: manifest, root: root);
  }

  final bool contractOnly;
  final File? manifest;
  final Directory? root;
}
