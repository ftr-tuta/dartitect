import 'dart:convert';
import 'dart:io';

/// Validates V1S-17 tooling or the complete installed-RC evidence set.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final contractOnly = options.contractOnly;
    final root =
        options.root ?? File.fromUri(Platform.script).parent.parent.absolute;
    final contract = _read(root, 'tool/rc_validation_contract.json');
    final stable = _read(root, 'tool/stable_readiness_decision.json');
    final ledger = _read(root, 'tool/goal_gates.json');
    final errors = <String>[];
    _validateContract(contract, stable, ledger, errors);
    if (!contractOnly && errors.isEmpty) {
      await _validateFormal(root, contract, stable, ledger, errors);
    }
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      contractOnly
          ? 'RC validation tooling contract passed at ${stable['state']}.'
          : 'Installed RC, native matrix, upgrade, residuals, and stable '
                'readiness passed.',
    );
  } on Object catch (error) {
    stderr.writeln('RC validation evidence could not be read: $error');
    exitCode = 1;
  }
}

void _validateContract(
  Map<String, Object?> contract,
  Map<String, Object?> stable,
  Map<String, Object?> ledger,
  List<String> errors,
) {
  final remote = _objectOrNull(contract['remoteInstall']);
  final upgrade = _objectOrNull(contract['upgrade']);
  final stableContract = _objectOrNull(contract['stableDecision']);
  if (contract['schemaVersion'] != 1 ||
      contract['goal'] != 'V1S-17' ||
      contract['supportedChannel'] != 'signed-bundle' ||
      contract['toolingState'] != 'PRE_VALIDATION_READY' ||
      contract['requiresMaterializedArtifacts'] != true ||
      remote?['provider'] != 'github-release-download' ||
      remote?['monorepoPathResolution'] != false ||
      remote?['dependencyOverrides'] != false ||
      remote?['archiveDigestVerification'] != true ||
      !_same(_strings(contract['requiredCanaries']), const <String>[
        'minimal',
        'offline_first',
        'native_capabilities',
      ]) ||
      contract['requiredNativeCells'] != 9 ||
      contract['requiredResidualCensus'] != 0) {
    errors.add('The installed RC validation contract is incomplete.');
  }
  if (upgrade?['realRcToRc'] != true ||
      upgrade?['twoCandidateBundlesWhenNoSecondRc'] != true ||
      !_same(_strings(upgrade?['persistedStores']), const <String>[
        'objectbox',
        'outbox',
        'journal',
        'checkpoint',
        'generator-manifest',
      ])) {
    errors.add('The RC upgrade validation contract is incomplete.');
  }
  if (stableContract?['record'] != 'tool/stable_readiness_decision.json' ||
      stableContract?['state'] != 'READY_FOR_1_0' ||
      stableContract?['separateFromRcReadiness'] != true) {
    errors.add('The stable readiness decision contract is incomplete.');
  }
  final authority = _objectOrNull(
    _objectOrNull(ledger['statusPolicy'])?['reviewAuthority'],
  )?['name'];
  final state = stable['state'];
  if (stable['schemaVersion'] != 1 || stable['goal'] != 'V1S-17') {
    errors.add('The stable readiness record identity is invalid.');
  } else if (state == 'NOT_READY_FOR_1_0') {
    if (stable['decisionId'] != null ||
        stable['rcSourceSha'] != null ||
        stable['rcManifestSha256'] != null ||
        stable['recordedAt'] != null ||
        !_empty(stable['reviewedBy']) ||
        _strings(stable['blockers']).isEmpty) {
      errors.add('NOT_READY_FOR_1_0 must remain unsigned with blockers.');
    }
  } else if (state == 'READY_FOR_1_0') {
    if (!_nonEmpty(stable['decisionId']) ||
        !_sha(stable['rcSourceSha'], 40) ||
        !_sha(stable['rcManifestSha256'], 64) ||
        !_utc(stable['recordedAt']) ||
        stable['reviewedBy'] is! List<Object?> ||
        (stable['reviewedBy']! as List<Object?>).length != 1 ||
        (stable['reviewedBy']! as List<Object?>).single != authority ||
        _strings(stable['blockers']).isNotEmpty) {
      errors.add('READY_FOR_1_0 evidence is incomplete.');
    }
  } else {
    errors.add('Unknown stable readiness state: $state.');
  }
}

Future<void> _validateFormal(
  Directory root,
  Map<String, Object?> contract,
  Map<String, Object?> stable,
  Map<String, Object?> ledger,
  List<String> errors,
) async {
  final artifacts = await _run(root, 'tool/check_rc_artifacts.dart');
  if (artifacts != 0) errors.add('The materialized RC artifact gate failed.');
  final decision = _read(root, 'tool/rc_readiness_decision.json');
  final release = _read(root, 'tool/package_release_contract.json');
  final bundleContract = _read(root, 'tool/rc_bundle_contract.json');
  final sourceSha = decision['sourceSha'];
  if (sourceSha is! String) {
    errors.add('The RC source SHA is absent.');
    return;
  }
  final canary = File(
    '${root.path}/build/canary-receipts/v1s17-$sourceSha.json',
  );
  if (!canary.existsSync()) {
    errors.add('The materialized-channel canary receipt is absent.');
  } else {
    final value = _object(jsonDecode(canary.readAsStringSync()));
    final canaries = value['canaries'];
    if (value['goal'] != 'V1S-17' ||
        value['sourceSha'] != sourceSha ||
        value['artifactSource'] != 'materialized-signed-bundle' ||
        value['result'] != 'passed' ||
        canaries is! List<Object?> ||
        canaries.length != 3 ||
        canaries.any(
          (item) =>
              item is! Map<String, Object?> ||
              item['result'] != 'passed' ||
              item['residualResourceCensus'] != 0,
        )) {
      errors.add('The materialized-channel canary receipt is invalid.');
    }
  }
  final native = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'tool/check_native_evidence.dart',
    '--source-sha=$sourceSha',
  ], workingDirectory: root.path);
  if (native.exitCode != 0) {
    errors.add('The same-SHA five-cell native matrix is incomplete.');
  }
  final upgrade = File(
    '${root.path}/build/rc-validation/upgrade-$sourceSha.json',
  );
  if (!upgrade.existsSync()) {
    errors.add('The candidate upgrade receipt is absent.');
  } else {
    final value = _object(jsonDecode(upgrade.readAsStringSync()));
    if (value['goal'] != 'V1S-17' ||
        value['sourceSha'] != sourceSha ||
        value['result'] != 'passed' ||
        value['residualResourceCensus'] != 0 ||
        (value['upgradeMode'] != 'rc-to-rc' &&
            value['upgradeMode'] != 'two-candidate-bundles') ||
        !_nonEmpty(value['fromVersion']) ||
        !_nonEmpty(value['toVersion']) ||
        value['fromVersion'] == value['toVersion'] ||
        value['persistedStores'] is! List<Object?> ||
        !_same(
          (value['persistedStores']! as List<Object?>).cast<String>(),
          _strings(_objectOrNull(contract['upgrade'])?['persistedStores']),
        )) {
      errors.add('The candidate upgrade receipt is invalid.');
    }
  }
  final cohort = release['cohortVersion'];
  final bundleReceipt = cohort is String
      ? File(
          '${root.path}/${bundleContract['outputDirectory']}/$cohort/'
          '$sourceSha/materialization-receipt.json',
        )
      : File('');
  final materialization = bundleReceipt.existsSync()
      ? _object(jsonDecode(bundleReceipt.readAsStringSync()))
      : const <String, Object?>{};
  if (stable['state'] != 'READY_FOR_1_0' ||
      stable['rcSourceSha'] != sourceSha ||
      stable['rcManifestSha256'] != materialization['manifestSha256'] ||
      ledger['releaseStatus'] != 'READY_FOR_1_0') {
    errors.add('The separate READY_FOR_1_0 decision is absent.');
  }
}

Future<int> _run(Directory root, String script) async => (await Process.run(
  Platform.resolvedExecutable,
  <String>['run', script],
  workingDirectory: root.path,
)).exitCode;

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

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string list.');
  }
  return value.cast<String>();
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((value) => value);

bool _empty(Object? value) => value is List<Object?> && value.isEmpty;
bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;
bool _sha(Object? value, int length) =>
    value is String && RegExp('^[0-9a-f]{$length}\$').hasMatch(value);
bool _utc(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed != null && parsed.isUtc;
}

final class _Options {
  const _Options({required this.contractOnly, this.root});

  factory _Options.parse(List<String> arguments) {
    var contractOnly = false;
    Directory? root;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument == '--contract-only') {
        if (contractOnly) throw ArgumentError('Duplicate --contract-only.');
        contractOnly = true;
      } else if (argument == '--root' && index + 1 < arguments.length) {
        if (root != null) throw ArgumentError('Duplicate --root.');
        root = Directory(arguments[++index]).absolute;
      } else {
        throw ArgumentError('Unknown or incomplete argument: $argument');
      }
    }
    return _Options(contractOnly: contractOnly, root: root);
  }

  final bool contractOnly;
  final Directory? root;
}
