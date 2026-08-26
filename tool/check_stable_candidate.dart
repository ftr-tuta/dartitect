import 'dart:convert';
import 'dart:io';

final _sha = RegExp(r'^[0-9a-f]{40}$');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// Validates the V1-18 promotion contract, RC diff, and stable evidence.
///
/// `--contract-only` proves that the pre-stable state remains fail-closed.
/// `--compare <rc> <stable>` exercises only the release-diff policy and never
/// asserts candidate validation or publication authorization.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root =
        options.root ?? File.fromUri(Platform.script).parent.parent.absolute;
    final contract = _read(root, 'tool/stable_candidate_contract.json');
    final record = _read(root, 'tool/stable_candidate_record.json');
    final authorization = _read(
      root,
      'tool/stable_publication_authorization.json',
    );
    final ledger = _read(root, 'tool/goal_gates.json');
    final errors = <String>[];
    _validateContract(contract, record, authorization, ledger, errors);
    if (errors.isEmpty && options.compare != null) {
      await _validateDiff(
        root,
        contract,
        options.compare!.$1,
        options.compare!.$2,
        errors,
      );
    } else if (errors.isEmpty && !options.contractOnly) {
      await _validateFormal(
        root,
        contract,
        record,
        authorization,
        ledger,
        options.requirePublicationAuthorization,
        errors,
      );
    }
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    if (options.compare != null) {
      stdout.writeln(
        'Stable release diff policy passed; no readiness or publication was asserted.',
      );
    } else if (options.contractOnly) {
      stdout.writeln(
        'Stable candidate tooling is valid and fail-closed at ${record['state']}/${authorization['state']}.',
      );
    } else if (options.requirePublicationAuthorization) {
      stdout.writeln(
        'Stable candidate and separate publication authorization passed for ${record['sourceSha']}.',
      );
    } else {
      stdout.writeln(
        'Stable 1.0.0 candidate evidence passed for ${record['sourceSha']}; publication remains a separate decision.',
      );
    }
  } on Object catch (error) {
    stderr.writeln('Stable candidate evidence could not be read: $error');
    exitCode = 1;
  }
}

void _validateContract(
  Map<String, Object?> contract,
  Map<String, Object?> record,
  Map<String, Object?> authorization,
  Map<String, Object?> ledger,
  List<String> errors,
) {
  final diff = _objectOrNull(contract['diffPolicy']);
  final preparation = _objectOrNull(contract['preparation']);
  final publication = _objectOrNull(contract['publication']);
  final releaseRecords = _stringsOrNull(diff?['releaseRecordPaths']);
  if (contract['schemaVersion'] != 1 ||
      contract['goal'] != 'V1-18' ||
      contract['toolingState'] != 'PREPARATION_READY' ||
      contract['stableVersion'] != '1.0.0' ||
      contract['stableInternalConstraint'] != '>=1.0.0 <1.1.0' ||
      contract['finalRcVersionPattern'] != r'^1\.0\.0-rc\.[1-9][0-9]*$' ||
      contract['requiresNewSourceSha'] != true ||
      contract['requiresExactMainSha'] != true ||
      contract['requiredPackageCount'] != 16 ||
      contract['requiredPublicEntrypointCount'] != 17) {
    errors.add('The stable candidate root contract is incomplete.');
  }
  if (preparation?['script'] != 'tool/prepare_stable_candidate.dart' ||
      preparation?['requiresFormalStableReadiness'] != true ||
      preparation?['requiresMainBranch'] != true ||
      preparation?['requiresCleanTrackedTree'] != true ||
      preparation?['externalWrites'] != false ||
      !_same(
        _stringsOrNull(preparation?['historicalRcPaths']) ?? const <String>[],
        const <String>[
          'tool/rc_candidate_contract.json',
          'tool/rc_readiness_decision.json',
          'tool/rc_distribution_authorization.json',
          'tool/check_rc_candidate.dart',
          'tool/check_rc_readiness_test.dart',
          'tool/check_rc_artifacts_test.dart',
          'tool/check_rc_validation_test.dart',
          'tool/check_package_release_contract_test.dart',
        ],
      )) {
    errors.add('The stable working-tree preparation contract is invalid.');
  }
  if (diff?['addedFiles'] != false ||
      diff?['deletedFiles'] != false ||
      diff?['renamedFiles'] != false ||
      diff?['versionLiteralReplacementOnly'] != true ||
      diff?['changelogStablePrefixOnly'] != true ||
      releaseRecords == null ||
      releaseRecords.length != releaseRecords.toSet().length ||
      !_same(releaseRecords, const <String>[
        'tool/package_release_contract.json',
        'tool/rc_candidate_contract.json',
        'tool/sdk_inventory.json',
        'tool/api_surface.snapshot.json',
        'tool/goal_gates.json',
        'tool/stable_candidate_record.json',
        'docs/implementation-status.adoc',
        'docs/release/1.0-readiness.adoc',
        'docs/release/sbom.spdx.json',
        'docs/release/dependency-licenses.json',
        'docs/release/advisory-audit.adoc',
        'docs/release/pub-dev-identity-audit.adoc',
        'docs/release/publication-runbook.adoc',
      ])) {
    errors.add('The stable release diff allowlist is invalid or broadened.');
  }
  if (!_same(
        _stringsOrNull(contract['repeatedEvidence']) ?? const <String>[],
        const <String>[
          'CI',
          'Security',
          'clean-clone',
          'release-audit',
          'sbom',
          'licenses',
          'publish-dry-runs',
        ],
      ) ||
      publication?['authorizationRecord'] !=
          'tool/stable_publication_authorization.json' ||
      publication?['tag'] != 'v1.0.0' ||
      publication?['signedTag'] != true ||
      publication?['channel'] != 'pub.dev' ||
      publication?['manualTopologicalOrder'] != true ||
      publication?['automaticRetry'] != false ||
      publication?['overwritePublishedVersion'] != false) {
    errors.add('The repeated-gate or stable publication contract is invalid.');
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
  if (record['schemaVersion'] != 1 ||
      record['goal'] != 'V1-18' ||
      record['stableVersion'] != contract['stableVersion']) {
    errors.add('The stable candidate record identity is invalid.');
  } else if (record['state'] == 'NOT_ASSEMBLED') {
    if (record['candidateId'] != null ||
        record['sourceSha'] != null ||
        record['sourceTree'] != null ||
        record['finalRcSourceSha'] != null ||
        record['finalRcManifestSha256'] != null ||
        record['validatedAt'] != null ||
        !_empty(record['reviewedBy']) ||
        !_empty(record['workflowRuns']) ||
        !_empty(record['gateReceipts']) ||
        !_empty(record['artifactDigests']) ||
        (_stringsOrNull(record['blockers'])?.isEmpty ?? true)) {
      errors.add('NOT_ASSEMBLED must remain unbound and list blockers.');
    }
  } else if (record['state'] == 'VALIDATED') {
    if (!_nonEmpty(record['candidateId']) ||
        !_validSha(record['sourceSha']) ||
        !_validSha(record['sourceTree']) ||
        !_validSha(record['finalRcSourceSha']) ||
        !_validDigest(record['finalRcManifestSha256']) ||
        !_utc(record['validatedAt']) ||
        !_exactReviewer(record['reviewedBy'], authorityName) ||
        !_empty(record['blockers'])) {
      errors.add('The VALIDATED stable candidate record is incomplete.');
    }
  } else {
    errors.add('Unknown stable candidate state: ${record['state']}.');
  }

  if (authorization['schemaVersion'] != 1 ||
      authorization['goal'] != 'V1-18' ||
      authorization['separateFromStableReadiness'] != true ||
      authorization['separateFromCandidateValidation'] != true) {
    errors.add('The stable publication authorization identity is invalid.');
  } else if (authorization['state'] == 'NOT_AUTHORIZED') {
    if (authorization['authorizationId'] != null ||
        authorization['candidateId'] != null ||
        authorization['sourceSha'] != null ||
        authorization['tag'] != null ||
        authorization['channel'] != null ||
        !_empty(authorization['authorizedActions']) ||
        authorization['recordedAt'] != null ||
        !_empty(authorization['reviewedBy'])) {
      errors.add('NOT_AUTHORIZED must remain unbound and actionless.');
    }
  } else if (authorization['state'] == 'AUTHORIZED') {
    if (record['state'] != 'VALIDATED' ||
        !_nonEmpty(authorization['authorizationId']) ||
        authorization['authorizationId'] == record['candidateId'] ||
        authorization['candidateId'] != record['candidateId'] ||
        authorization['sourceSha'] != record['sourceSha'] ||
        authorization['tag'] != publication?['tag'] ||
        authorization['channel'] != publication?['channel'] ||
        !_same(
          _stringsOrNull(authorization['authorizedActions']) ??
              const <String>[],
          const <String>['create-signed-tag', 'publish-pub-dev-cohort'],
        ) ||
        !_utc(authorization['recordedAt']) ||
        !_exactReviewer(authorization['reviewedBy'], authorityName)) {
      errors.add(
        'The stable publication authorization is incomplete or coupled.',
      );
    }
    final validatedAt = DateTime.tryParse('${record['validatedAt']}');
    final authorizedAt = DateTime.tryParse('${authorization['recordedAt']}');
    if (validatedAt != null &&
        authorizedAt != null &&
        !authorizedAt.isAfter(validatedAt)) {
      errors.add('Stable publication authorization must follow validation.');
    }
  } else {
    errors.add('Unknown stable publication authorization state.');
  }
}

Future<void> _validateFormal(
  Directory root,
  Map<String, Object?> contract,
  Map<String, Object?> record,
  Map<String, Object?> authorization,
  Map<String, Object?> ledger,
  bool requireAuthorization,
  List<String> errors,
) async {
  if (record['state'] != 'VALIDATED') {
    errors.add('Formal stable candidate validation is not complete.');
    return;
  }
  if (requireAuthorization && authorization['state'] != 'AUTHORIZED') {
    errors.add('Stable tag and pub.dev publication are not authorized.');
    return;
  }
  final stableSha = record['sourceSha']! as String;
  final rcSha = record['finalRcSourceSha']! as String;
  final stableReadiness = _read(root, 'tool/stable_readiness_decision.json');
  if (stableReadiness['state'] != 'READY_FOR_1_0' ||
      stableReadiness['rcSourceSha'] != rcSha ||
      stableReadiness['rcManifestSha256'] != record['finalRcManifestSha256']) {
    errors.add('The final RC READY_FOR_1_0 decision does not match.');
  }
  final goals = <String, Map<String, Object?>>{
    for (final goal in _objectsOrEmpty(ledger['goals']))
      if (goal['id'] is String) goal['id']! as String: goal,
  };
  if (goals['V1S-17']?['status'] != 'COMPLETE' ||
      goals['V1S-17']?['sourceSha'] != rcSha) {
    errors.add('V1S-17 lacks final-RC completion evidence.');
  }
  final stableBaseline = _objectOrNull(
    _objectOrNull(ledger['baselines'])?['stableCandidate'],
  );
  if (stableBaseline?['sha'] != stableSha ||
      stableBaseline?['tree'] != record['sourceTree'] ||
      stableBaseline?['finalRcSha'] != rcSha) {
    errors.add('The exact stable candidate baseline is absent.');
  }
  final tree = await _git(root, <String>[
    'show',
    '-s',
    '--format=%T',
    stableSha,
  ]);
  if (tree?.trim() != record['sourceTree']) {
    errors.add('The stable candidate tree cannot be reproduced.');
  }
  final ancestry = await Process.run('git', <String>[
    'merge-base',
    '--is-ancestor',
    rcSha,
    stableSha,
  ], workingDirectory: root.path);
  if (ancestry.exitCode != 0 || rcSha == stableSha) {
    errors.add('The stable candidate is not a new descendant of the final RC.');
  }
  final mainContains = await Process.run('git', <String>[
    'merge-base',
    '--is-ancestor',
    stableSha,
    'refs/remotes/origin/main',
  ], workingDirectory: root.path);
  if (mainContains.exitCode != 0) {
    errors.add('The stable candidate SHA is not contained in origin/main.');
  }
  await _validateDiff(root, contract, rcSha, stableSha, errors);
  await _validateStableCohort(root, contract, stableSha, errors);
  _validateRepeatedEvidence(contract, record, stableSha, errors);
  if (requireAuthorization && authorization['sourceSha'] != stableSha) {
    errors.add('The publication authorization is cross-SHA.');
  }
}

Future<void> _validateDiff(
  Directory root,
  Map<String, Object?> contract,
  String rcRef,
  String stableRef,
  List<String> errors,
) async {
  final rcVersion = await _cohortAt(root, rcRef);
  final stableVersion = contract['stableVersion']! as String;
  if (rcVersion == null ||
      !RegExp(contract['finalRcVersionPattern']! as String)
          .hasMatch(rcVersion)) {
    errors.add('The comparison base is not a final 1.0.0-rc.N cohort.');
    return;
  }
  if (await _cohortAt(root, stableRef) != stableVersion) {
    errors.add('The comparison target is not the 1.0.0 cohort.');
    return;
  }
  final result = await Process.run('git', <String>[
    'diff',
    '--name-status',
    '--no-renames',
    rcRef,
    stableRef,
    '--',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    errors.add('The RC-to-stable diff could not be enumerated.');
    return;
  }
  final records = _stringsOrNull(
    _objectOrNull(contract['diffPolicy'])?['releaseRecordPaths'],
  )!.toSet();
  for (final line in const LineSplitter().convert(result.stdout as String)) {
    if (line.trim().isEmpty) continue;
    final columns = line.split('\t');
    if (columns.length != 2 || columns.first != 'M') {
      errors.add('Stable promotion forbids add/delete/rename: $line.');
      continue;
    }
    final path = columns[1];
    final before = await _show(root, rcRef, path);
    final after = await _show(root, stableRef, path);
    if (before == null || after == null) {
      errors.add('Stable promotion could not read both versions of $path.');
      continue;
    }
    if (RegExp(r'^packages/[^/]+/CHANGELOG\.md$').hasMatch(path)) {
      if (!_validChangelogPromotion(before, after, stableVersion)) {
        errors.add('$path contains more than a stable changelog prefix.');
      }
      continue;
    }
    if (records.contains(path)) continue;
    final normalized = before
        .replaceAll(
          '>=$rcVersion <1.0.0',
          contract['stableInternalConstraint']! as String,
        )
        .replaceAll(rcVersion, stableVersion);
    if (normalized != after || before == after) {
      errors.add('$path contains a non-release change outside the allowlist.');
    }
  }
}

Future<void> _validateStableCohort(
  Directory root,
  Map<String, Object?> contract,
  String stableSha,
  List<String> errors,
) async {
  final releaseSource = await _show(
    root,
    stableSha,
    'tool/package_release_contract.json',
  );
  if (releaseSource == null) {
    errors.add('The stable package release contract is absent.');
    return;
  }
  final release = _object(jsonDecode(releaseSource));
  final order = _stringsOrNull(release['publicationOrder']);
  if (release['cohortVersion'] != contract['stableVersion'] ||
      release['internalConstraint'] != contract['stableInternalConstraint'] ||
      order == null ||
      order.length != contract['requiredPackageCount'] ||
      order.toSet().length != order.length) {
    errors.add('The stable package release contract is incomplete.');
    return;
  }
  for (final package in order) {
    final pubspec = await _show(
      root,
      stableSha,
      'packages/$package/pubspec.yaml',
    );
    final changelog = await _show(
      root,
      stableSha,
      'packages/$package/CHANGELOG.md',
    );
    if (pubspec == null ||
        _field(pubspec, 'name') != package ||
        _field(pubspec, 'version') != contract['stableVersion'] ||
        changelog == null ||
        !_startsWithStableHeading(
          changelog,
          contract['stableVersion']! as String,
        )) {
      errors.add('$package is not an exact stable cohort member.');
      continue;
    }
    final internalLines = const LineSplitter().convert(pubspec).where((line) {
      final match = RegExp(r'^  (dartitect(?:_[a-z0-9_]+)?):\s+(.+)$')
          .firstMatch(line);
      return match != null && order.contains(match.group(1));
    });
    for (final line in internalLines) {
      final constraint = line.substring(line.indexOf(':') + 1).trim();
      if (constraint != "'${contract['stableInternalConstraint']}'" &&
          constraint != '"${contract['stableInternalConstraint']}"') {
        errors.add('$package has a non-stable internal constraint: $line.');
      }
    }
  }
}

void _validateRepeatedEvidence(
  Map<String, Object?> contract,
  Map<String, Object?> record,
  String sourceSha,
  List<String> errors,
) {
  final workflows = _objectsOrEmpty(record['workflowRuns']);
  if (workflows.length != 2 ||
      workflows.any(
        (item) => item['workflow'] != 'CI' && item['workflow'] != 'Security',
      )) {
    errors.add('Stable workflow evidence must contain only CI and Security.');
  }
  for (final name in const <String>['CI', 'Security']) {
    final matching = workflows.where(
      (item) =>
          item['workflow'] == name &&
          item['sourceSha'] == sourceSha &&
          item['conclusion'] == 'success' &&
          item['runId'] is int &&
          _nonEmpty(item['url']),
    );
    if (matching.length != 1) {
      errors.add('Missing unique successful $name run for $sourceSha.');
    }
  }
  final gateItems = _objectsOrEmpty(record['gateReceipts']);
  final gates = <String, Map<String, Object?>>{
    for (final item in gateItems)
      if (item['gate'] is String) item['gate']! as String: item,
  };
  final expectedGates =
      (_stringsOrNull(contract['repeatedEvidence']) ?? const <String>[])
          .where((name) => name != 'CI' && name != 'Security')
          .toList(growable: false);
  if (gateItems.length != expectedGates.length ||
      gates.length != expectedGates.length ||
      !gates.keys.toSet().containsAll(expectedGates)) {
    errors.add('The repeated stable gate receipt set is not exact.');
  }
  for (final name in expectedGates) {
    final receipt = gates[name];
    if (receipt?['sourceSha'] != sourceSha ||
        receipt?['result'] != 'passed' ||
        !_utc(receipt?['completedAt'])) {
      errors.add('Missing same-SHA repeated gate receipt: $name.');
    }
  }
  final digests = _objectsOrEmpty(record['artifactDigests']);
  if (digests.length != 3 ||
      digests.any(
        (item) =>
            item['artifact'] != 'sbom' &&
            item['artifact'] != 'licenses' &&
            item['artifact'] != 'package-manifest',
      )) {
    errors.add('The stable artifact digest set is not exact.');
  }
  for (final name in const <String>['sbom', 'licenses', 'package-manifest']) {
    final matching = digests.where(
      (item) =>
          item['artifact'] == name &&
          item['sourceSha'] == sourceSha &&
          _validDigest(item['sha256']),
    );
    if (matching.length != 1) {
      errors.add('Missing stable artifact digest: $name.');
    }
  }
}

bool _validChangelogPromotion(String before, String after, String stable) {
  if (!_startsWithStableHeading(after, stable)) return false;
  final next = after.indexOf('\n## ', 1);
  return next >= 0 && after.substring(next + 1) == before;
}

bool _startsWithStableHeading(String source, String stable) =>
    RegExp('^##\\s+${RegExp.escape(stable)}(?:\\s|\$)').hasMatch(source);

Future<String?> _cohortAt(Directory root, String ref) async {
  final source = await _show(root, ref, 'tool/package_release_contract.json');
  if (source == null) return null;
  final value = jsonDecode(source);
  return value is Map<String, Object?> && value['cohortVersion'] is String
      ? value['cohortVersion']! as String
      : null;
}

Future<String?> _show(Directory root, String ref, String path) =>
    _git(root, <String>['show', '$ref:$path']);

Future<String?> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  return result.exitCode == 0 ? result.stdout as String : null;
}

Map<String, Object?> _read(Directory root, String path) =>
    _object(jsonDecode(File('${root.path}/$path').readAsStringSync()));

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
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

String? _field(String source, String name) => RegExp(
  '^${RegExp.escape(name)}:\\s*([^\\s]+)',
  multiLine: true,
).firstMatch(source)?.group(1);

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((value) => value);

bool _empty(Object? value) => value is List<Object?> && value.isEmpty;
bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;
bool _validSha(Object? value) => value is String && _sha.hasMatch(value);
bool _validDigest(Object? value) => value is String && _sha256.hasMatch(value);
bool _exactReviewer(Object? value, Object? reviewer) =>
    reviewer is String &&
    value is List<Object?> &&
    value.length == 1 &&
    value.single == reviewer;
bool _utc(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed != null && parsed.isUtc;
}

final class _Options {
  const _Options({
    required this.contractOnly,
    required this.requirePublicationAuthorization,
    this.root,
    this.compare,
  });

  factory _Options.parse(List<String> arguments) {
    var contractOnly = false;
    var requireAuthorization = false;
    Directory? root;
    (String, String)? compare;
    for (var index = 0; index < arguments.length; index += 1) {
      switch (arguments[index]) {
        case '--contract-only':
          if (contractOnly) throw ArgumentError('Duplicate --contract-only.');
          contractOnly = true;
        case '--require-publication-authorization':
          if (requireAuthorization) {
            throw ArgumentError('Duplicate publication authorization option.');
          }
          requireAuthorization = true;
        case '--root':
          if (root != null || index + 1 >= arguments.length) {
            throw ArgumentError('Invalid or duplicate --root.');
          }
          root = Directory(arguments[++index]).absolute;
        case '--compare':
          if (compare != null || index + 2 >= arguments.length) {
            throw ArgumentError('Invalid or duplicate --compare.');
          }
          compare = (arguments[++index], arguments[++index]);
        default:
          throw ArgumentError('Unknown argument: ${arguments[index]}');
      }
    }
    if ((contractOnly && compare != null) ||
        (contractOnly && requireAuthorization) ||
        (compare != null && requireAuthorization)) {
      throw ArgumentError('Stable checker modes are mutually exclusive.');
    }
    return _Options(
      contractOnly: contractOnly,
      requirePublicationAuthorization: requireAuthorization,
      root: root,
      compare: compare,
    );
  }

  final bool contractOnly;
  final bool requirePublicationAuthorization;
  final Directory? root;
  final (String, String)? compare;
}
