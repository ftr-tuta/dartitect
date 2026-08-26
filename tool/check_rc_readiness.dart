import 'dart:convert';
import 'dart:io';

const _notReady = 'NOT_READY_FOR_1_0_RC';
const _ready = 'READY_FOR_1_0_RC';
const _notAuthorized = 'NOT_AUTHORIZED';
const _authorized = 'AUTHORIZED';
const _unselected = 'UNSELECTED';
const _allowedChannels = <String>{'pub-dev-prerelease', 'signed-bundle'};
final _sha = RegExp(r'^[0-9a-f]{40}$');

/// Validates the separate RC-readiness decision and distribution authorization.
///
/// The structural mode is suitable for pre-RC CI: it proves that an incomplete
/// record remains explicitly fail-closed. The default formal mode succeeds only
/// for an exact, fully evidenced `READY_FOR_1_0_RC` decision.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root =
        options.root ?? File.fromUri(Platform.script).parent.parent.absolute;
    final errors = <String>[];
    final decision = _readObject(root, 'tool/rc_readiness_decision.json');
    final authorization = _readObject(
      root,
      'tool/rc_distribution_authorization.json',
    );
    final release = _readObject(root, 'tool/package_release_contract.json');
    final candidate = _readObject(root, 'tool/rc_candidate_contract.json');
    final ledger = _readObject(root, 'tool/goal_gates.json');

    _validateContract(
      decision: decision,
      authorization: authorization,
      release: release,
      candidate: candidate,
      ledger: ledger,
      errors: errors,
    );
    if (!options.contractOnly && errors.isEmpty) {
      await _validateFormalReadiness(
        root: root,
        decision: decision,
        authorization: authorization,
        candidate: candidate,
        ledger: ledger,
        errors: errors,
      );
    }
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    if (options.contractOnly) {
      stdout.writeln(
        'RC readiness decision contract is valid and fail-closed at '
        '${decision['state']}.',
      );
    } else {
      stdout.writeln(
        'RC readiness passed for ${decision['sourceSha']} with separately '
        'authorized ${authorization['channel']} materialization.',
      );
    }
  } on Object catch (error) {
    stderr.writeln('RC readiness evidence could not be read: $error');
    exitCode = 1;
  }
}

void _validateContract({
  required Map<String, Object?> decision,
  required Map<String, Object?> authorization,
  required Map<String, Object?> release,
  required Map<String, Object?> candidate,
  required Map<String, Object?> ledger,
  required List<String> errors,
}) {
  final cohort = release['cohortVersion'];
  if (cohort is! String ||
      !RegExp(r'^1\.0\.0-rc\.[1-9][0-9]*$').hasMatch(cohort)) {
    errors.add('The release contract does not identify an RC cohort.');
  }
  if (decision['schemaVersion'] != 1 ||
      decision['goal'] != 'V1S-15' ||
      decision['cohortVersion'] != cohort ||
      candidate['cohortVersion'] != cohort) {
    errors.add('The readiness decision does not match the RC cohort.');
  }
  final roadmap = _objectOrNull(ledger['roadmap']);
  final configuredRequired = _stringsOrNull(roadmap?['requiredGoalIds']);
  final required = _stringsOrNull(decision['requiredGoalIds']);
  final expectedRequired = <String>[
    for (var index = 0; index <= 14; index += 1)
      'V1S-${index.toString().padLeft(2, '0')}',
  ];
  if (configuredRequired == null ||
      required == null ||
      !_same(required, expectedRequired) ||
      !configuredRequired.toSet().containsAll(required)) {
    errors.add('The readiness prerequisite goal set is incomplete.');
  }
  if (!_same(
    _stringsOrNull(decision['requiredWorkflowNames']) ?? const <String>[],
    const <String>['CI', 'Security'],
  )) {
    errors.add('RC readiness must require same-SHA CI and Security.');
  }

  final authority = _objectOrNull(
    _objectOrNull(ledger['statusPolicy'])?['reviewAuthority'],
  );
  final authorityName = authority?['name'];
  if (authority?['kind'] != 'MAINTAINER_DELEGATED_AUTOMATION' ||
      authorityName is! String ||
      authorityName.trim().isEmpty) {
    errors.add('The delegated review authority is not configured.');
  }

  final state = decision['state'];
  final blockers = _stringsOrNull(decision['blockers']);
  if (state != _notReady && state != _ready) {
    errors.add('Unknown RC readiness decision state: $state.');
  } else if (state == _notReady) {
    if (decision['decisionId'] != null ||
        decision['sourceSha'] != null ||
        decision['sourceTree'] != null ||
        decision['recordedAt'] != null ||
        !_emptyStrings(decision['reviewedBy']) ||
        blockers == null ||
        blockers.isEmpty) {
      errors.add('NOT_READY_FOR_1_0_RC must remain unsigned with blockers.');
    }
  } else {
    if (!_nonEmpty(decision['decisionId']) ||
        !_validSha(decision['sourceSha']) ||
        !_validSha(decision['sourceTree']) ||
        !_utc(decision['recordedAt']) ||
        blockers == null ||
        blockers.isNotEmpty ||
        !_exactReviewer(decision['reviewedBy'], authorityName)) {
      errors.add('READY_FOR_1_0_RC decision evidence is incomplete.');
    }
  }

  if (authorization['schemaVersion'] != 1 ||
      authorization['goal'] != 'V1S-15' ||
      authorization['cohortVersion'] != cohort ||
      authorization['separateFromReadinessDecision'] != true ||
      !_same(
        _stringsOrNull(authorization['allowedChannels']) ?? const <String>[],
        const <String>['pub-dev-prerelease', 'signed-bundle'],
      )) {
    errors.add('The RC distribution authorization contract is incomplete.');
  }
  final authorizationState = authorization['state'];
  if (authorizationState == _notAuthorized) {
    if (authorization['authorizationId'] != null ||
        authorization['readinessDecisionId'] != null ||
        authorization['sourceSha'] != null ||
        authorization['channel'] != _unselected ||
        authorization['recordedAt'] != null ||
        !_emptyStrings(authorization['reviewedBy'])) {
      errors.add('The non-authorized distribution record is not fail-closed.');
    }
  } else if (authorizationState == _authorized) {
    if (state != _ready ||
        !_nonEmpty(authorization['authorizationId']) ||
        authorization['authorizationId'] == decision['decisionId'] ||
        authorization['readinessDecisionId'] != decision['decisionId'] ||
        authorization['sourceSha'] != decision['sourceSha'] ||
        !_allowedChannels.contains(authorization['channel']) ||
        !_utc(authorization['recordedAt']) ||
        !_exactReviewer(authorization['reviewedBy'], authorityName)) {
      errors.add('The RC distribution authorization is incomplete or coupled.');
    }
    final decisionAt = DateTime.tryParse('${decision['recordedAt']}');
    final authorizationAt = DateTime.tryParse('${authorization['recordedAt']}');
    if (decisionAt != null &&
        authorizationAt != null &&
        !authorizationAt.isAfter(decisionAt)) {
      errors.add('Distribution authorization must follow readiness decision.');
    }
  } else {
    errors.add(
      'Unknown RC distribution authorization state: $authorizationState.',
    );
  }
}

Future<void> _validateFormalReadiness({
  required Directory root,
  required Map<String, Object?> decision,
  required Map<String, Object?> authorization,
  required Map<String, Object?> candidate,
  required Map<String, Object?> ledger,
  required List<String> errors,
}) async {
  if (decision['state'] != _ready || authorization['state'] != _authorized) {
    final blockers = _stringsOrNull(decision['blockers']) ?? const <String>[];
    errors.add(
      'Formal RC readiness is not granted'
      '${blockers.isEmpty ? '.' : ': ${blockers.join('; ')}'}',
    );
    return;
  }
  final sourceSha = decision['sourceSha']! as String;
  if (ledger['releaseStatus'] != _ready) {
    errors.add('The goal authority does not record READY_FOR_1_0_RC.');
  }
  if (candidate['candidateState'] != 'ASSEMBLED' ||
      candidate['sourceSha'] != sourceSha ||
      candidate['sourceTree'] != decision['sourceTree'] ||
      candidate['targetChannel'] != authorization['channel']) {
    errors.add(
      'The assembled candidate does not match the authorized decision.',
    );
  }

  final goals = <String, Map<String, Object?>>{
    for (final value in _objectsOrEmpty(ledger['goals']))
      if (value['id'] is String) value['id']! as String: value,
  };
  final authorityName = _objectOrNull(
    _objectOrNull(ledger['statusPolicy'])?['reviewAuthority'],
  )?['name'];
  for (final id in _stringsOrNull(decision['requiredGoalIds'])!) {
    final goal = goals[id];
    if (goal == null ||
        goal['status'] != 'COMPLETE' ||
        goal['sourceSha'] != sourceSha ||
        !_exactReviewer(goal['reviewedBy'], authorityName) ||
        !_utc(goal['completedAt'])) {
      errors.add('$id lacks same-SHA delegated completion evidence.');
    }
  }

  final baselines = _objectOrNull(ledger['baselines']);
  final rcCandidates = _objectsOrEmpty(baselines?['rcCandidates']);
  final matchingBaselines = rcCandidates.where(
    (value) => value['sha'] == sourceSha,
  );
  final baseline = matchingBaselines.length == 1
      ? matchingBaselines.single
      : null;
  if (baseline == null || baseline['tree'] != decision['sourceTree']) {
    errors.add('The exact RC candidate baseline is absent from the ledger.');
  } else {
    final runs = _objectsOrEmpty(baseline['workflowRuns']);
    for (final workflow in _stringsOrNull(decision['requiredWorkflowNames'])!) {
      final matching = runs.where(
        (run) =>
            run['workflow'] == workflow &&
            run['sourceSha'] == sourceSha &&
            run['conclusion'] == 'success' &&
            run['runId'] is int &&
            _nonEmpty(run['url']),
      );
      if (matching.length != 1) {
        errors.add('Missing unique successful $workflow run for $sourceSha.');
      }
    }
  }

  final tree = await _git(root, <String>[
    'show',
    '-s',
    '--format=%T',
    sourceSha,
  ]);
  if (tree == null || tree.trim() != decision['sourceTree']) {
    errors.add('The authorized source tree cannot be reproduced locally.');
  }
  final ancestor = await Process.run('git', <String>[
    'merge-base',
    '--is-ancestor',
    sourceSha,
    'HEAD',
  ], workingDirectory: root.path);
  if (ancestor.exitCode != 0) {
    errors.add(
      'The authorized RC SHA is not an ancestor of the decision HEAD.',
    );
  }
}

Map<String, Object?> _readObject(Directory root, String path) {
  final value = jsonDecode(File('${root.path}/$path').readAsStringSync());
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must contain one JSON object.');
  }
  return value;
}

Map<String, Object?>? _objectOrNull(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<Map<String, Object?>> _objectsOrEmpty(Object? value) =>
    value is List<Object?> &&
        value.every((item) => item is Map<String, Object?>)
    ? value.cast<Map<String, Object?>>()
    : const <Map<String, Object?>>[];

List<String>? _stringsOrNull(Object? value) =>
    value is List<Object?> && value.every((item) => item is String)
    ? value.cast<String>()
    : null;

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((value) => value);

bool _emptyStrings(Object? value) => value is List<Object?> && value.isEmpty;

bool _exactReviewer(Object? value, Object? reviewer) =>
    reviewer is String &&
    value is List<Object?> &&
    value.length == 1 &&
    value.single == reviewer;

bool _validSha(Object? value) => value is String && _sha.hasMatch(value);

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

bool _utc(Object? value) {
  if (value is! String) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.isUtc;
}

Future<String?> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  return result.exitCode == 0 ? result.stdout as String : null;
}

final class _Options {
  const _Options({required this.contractOnly, this.root});

  factory _Options.parse(List<String> arguments) {
    var contractOnly = false;
    Directory? root;
    for (var index = 0; index < arguments.length; index += 1) {
      switch (arguments[index]) {
        case '--contract-only':
          if (contractOnly) throw ArgumentError('Duplicate --contract-only.');
          contractOnly = true;
        case '--root':
          if (root != null || index + 1 == arguments.length) {
            throw ArgumentError('Invalid or duplicate --root.');
          }
          root = Directory(arguments[++index]).absolute;
        default:
          throw ArgumentError('Unknown argument: ${arguments[index]}');
      }
    }
    return _Options(contractOnly: contractOnly, root: root);
  }

  final bool contractOnly;
  final Directory? root;
}
