import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final _sha = RegExp(r'^[0-9a-f]{40}$');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// Verifies V1S-16 signed-bundle tooling or a materialized RC channel.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root =
        options.root ?? File.fromUri(Platform.script).parent.parent.absolute;
    final contract = _readObject(root, 'tool/rc_bundle_contract.json');
    final release = _readObject(root, 'tool/package_release_contract.json');
    final errors = <String>[];
    _validateContract(contract, release, errors);
    if (!options.contractOnly && errors.isEmpty) {
      await _validateMaterialized(root, contract, release, options, errors);
    }
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    if (options.contractOnly) {
      stdout.writeln(
        'RC signed-bundle tooling contract passed; no materialization was '
        'asserted.',
      );
    } else {
      stdout.writeln('RC signed bundle and materialization receipt passed.');
    }
  } on Object catch (error) {
    stderr.writeln('RC artifact evidence could not be read: $error');
    exitCode = 1;
  }
}

void _validateContract(
  Map<String, Object?> contract,
  Map<String, Object?> release,
  List<String> errors,
) {
  final archive = _objectOrNull(contract['archive']);
  final signature = _objectOrNull(contract['signature']);
  final tag = _objectOrNull(contract['tag']);
  final remote = _objectOrNull(contract['remote']);
  final receipt = _objectOrNull(contract['receipt']);
  if (contract['schemaVersion'] != 1 ||
      contract['goal'] != 'V1S-16' ||
      contract['supportedChannel'] != 'signed-bundle' ||
      contract['toolingState'] != 'PRE_MATERIALIZATION_READY' ||
      contract['materializationRequiresFormalReadiness'] != true ||
      contract['publicationOrderAuthority'] !=
          'tool/package_release_contract.json' ||
      contract['outputDirectory'] != 'build/rc-bundles') {
    errors.add('The RC signed-bundle root contract is invalid.');
  }
  if (archive?['format'] != 'tar.gz' ||
      archive?['source'] != 'git-archive-exact-source-sha' ||
      archive?['compression'] != 'git-archive-deterministic' ||
      archive?['digest'] != 'sha256' ||
      archive?['canonicalSourceDigest'] !=
          'sha256(path-utf8,zero,file-bytes,zero)') {
    errors.add('The RC archive reproducibility contract is invalid.');
  }
  if (signature?['format'] != 'openpgp-armored-detached' ||
      signature?['manifest'] != 'bundle-manifest.json' ||
      signature?['suffix'] != '.asc') {
    errors.add('The RC signature contract is invalid.');
  }
  if (tag?['prefix'] != 'v' ||
      tag?['signed'] != true ||
      tag?['exactSourceSha'] != true ||
      tag?['force'] != false) {
    errors.add('The RC tag contract is invalid.');
  }
  if (remote?['provider'] != 'github-release' ||
      remote?['prerelease'] != true ||
      remote?['immutablePackageAssets'] != true ||
      remote?['digestVerificationAfterUpload'] != true) {
    errors.add('The RC remote-channel contract is invalid.');
  }
  if (receipt?['appendOnlyLedger'] != 'materialization-ledger.jsonl' ||
      receipt?['finalReceipt'] != 'materialization-receipt.json' ||
      receipt?['partialFailureStopsCohort'] != true ||
      receipt?['automaticRetry'] != false) {
    errors.add('The RC materialization receipt contract is invalid.');
  }
  final order = _stringsOrNull(release['publicationOrder']);
  if (release['schemaVersion'] != 1 ||
      order == null ||
      order.length != 16 ||
      order.toSet().length != 16) {
    errors.add('The release contract is not a complete 16-package cohort.');
  }
}

Future<void> _validateMaterialized(
  Directory root,
  Map<String, Object?> contract,
  Map<String, Object?> release,
  _Options options,
  List<String> errors,
) async {
  final readiness = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'tool/check_rc_readiness.dart',
  ], workingDirectory: root.path);
  if (readiness.exitCode != 0) {
    errors.add(
      'RC materialization is unauthorized: '
      '${(readiness.stderr as String).trim()}',
    );
    return;
  }
  final decision = _readObject(root, 'tool/rc_readiness_decision.json');
  final authorization = _readObject(
    root,
    'tool/rc_distribution_authorization.json',
  );
  if (authorization['state'] != 'AUTHORIZED' ||
      authorization['channel'] != 'signed-bundle' ||
      authorization['sourceSha'] != decision['sourceSha']) {
    errors.add('The selected RC channel is not an authorized signed bundle.');
    return;
  }
  final sourceSha = decision['sourceSha'];
  final cohort = release['cohortVersion'];
  if (sourceSha is! String || !_sha.hasMatch(sourceSha) || cohort is! String) {
    errors.add('The authorized RC identity is invalid.');
    return;
  }
  final bundle =
      options.bundle ??
      Directory(
        '${root.path}/${contract['outputDirectory']}/$cohort/$sourceSha',
      );
  final manifestFile = File('${bundle.path}/bundle-manifest.json');
  final signatureFile = File('${manifestFile.path}.asc');
  final receiptFile = File('${bundle.path}/materialization-receipt.json');
  final ledgerFile = File('${bundle.path}/materialization-ledger.jsonl');
  for (final file in <File>[
    manifestFile,
    signatureFile,
    receiptFile,
    ledgerFile,
  ]) {
    if (!file.existsSync() || file.lengthSync() == 0) {
      errors.add('Missing RC materialization artifact: ${file.path}.');
    }
  }
  if (errors.isNotEmpty) return;

  final manifest = _object(jsonDecode(manifestFile.readAsStringSync()));
  final receipt = _object(jsonDecode(receiptFile.readAsStringSync()));
  final order = _stringsOrNull(release['publicationOrder'])!;
  final packages = _objectsOrEmpty(manifest['packages']);
  if (manifest['schemaVersion'] != 1 ||
      manifest['goal'] != 'V1S-16' ||
      manifest['state'] != 'CANDIDATE_BUNDLE' ||
      manifest['channel'] != 'signed-bundle' ||
      manifest['cohortVersion'] != cohort ||
      manifest['sourceSha'] != sourceSha ||
      manifest['sourceTree'] != decision['sourceTree'] ||
      manifest['trackedTreeClean'] != true ||
      manifest['archiveFormat'] != 'tar.gz' ||
      manifest['digestAlgorithm'] != 'sha256' ||
      manifest['packageCount'] != 16 ||
      packages.length != 16) {
    errors.add('The RC bundle manifest identity is invalid.');
  }
  for (var index = 0; index < order.length; index += 1) {
    final package = packages.length > index ? packages[index] : null;
    final hostedPubspec = package == null
        ? null
        : _objectOrNull(package['hostedPubspec']);
    if (package == null ||
        package['package'] != order[index] ||
        package['version'] != cohort ||
        package['orderIndex'] != index ||
        package['layer'] is! int ||
        package['archive'] is! String ||
        package['archiveBytes'] is! int ||
        !_validDigest(package['archiveSha256']) ||
        !_validDigest(package['canonicalSourceSha256']) ||
        hostedPubspec?['name'] != order[index] ||
        hostedPubspec?['version'] != cohort) {
      errors.add('Invalid package artifact at topological index $index.');
      continue;
    }
    final archive = File('${bundle.path}/${package['archive']}');
    if (!archive.existsSync() ||
        archive.lengthSync() != package['archiveBytes'] ||
        await _sha256File(archive) != package['archiveSha256']) {
      errors.add('${order[index]} archive digest/length does not match.');
    }
  }
  final manifestDigest = await _sha256File(manifestFile);
  final signatureDigest = await _sha256File(signatureFile);
  final tag = 'v$cohort';
  if (receipt['schemaVersion'] != 1 ||
      receipt['goal'] != 'V1S-16' ||
      receipt['state'] != 'MATERIALIZED' ||
      receipt['channel'] != 'signed-bundle' ||
      receipt['sourceSha'] != sourceSha ||
      receipt['cohortVersion'] != cohort ||
      receipt['manifestSha256'] != manifestDigest ||
      receipt['signatureSha256'] != signatureDigest ||
      receipt['tag'] != tag ||
      !_nonEmpty(receipt['signingFingerprint']) ||
      !_utc(receipt['materializedAt']) ||
      !_absoluteUrl(receipt['remoteReleaseUrl']) ||
      receipt['remoteDigestVerified'] != true) {
    errors.add('The final RC materialization receipt is invalid.');
  }
  final receiptPackages = _objectsOrEmpty(receipt['packages']);
  if (receiptPackages.length != packages.length) {
    errors.add('The final receipt does not cover all package artifacts.');
  } else {
    for (var index = 0; index < packages.length; index += 1) {
      if (receiptPackages[index]['package'] != packages[index]['package'] ||
          receiptPackages[index]['orderIndex'] != index ||
          receiptPackages[index]['archiveSha256'] !=
              packages[index]['archiveSha256'] ||
          receiptPackages[index]['state'] != 'verified' ||
          !_absoluteUrl(receiptPackages[index]['remoteAssetUrl'])) {
        errors.add('Package ${order[index]} lacks a verified remote receipt.');
      }
    }
  }

  final signature = await Process.run('gpg', <String>[
    '--batch',
    '--status-fd=1',
    '--verify',
    signatureFile.path,
    manifestFile.path,
  ], workingDirectory: root.path);
  if (signature.exitCode != 0 ||
      !const LineSplitter()
          .convert(signature.stdout as String)
          .any(
            (line) =>
                line.startsWith('[GNUPG:] VALIDSIG ') &&
                line.split(' ').contains(receipt['signingFingerprint']),
          )) {
    errors.add('The detached RC bundle signature could not be verified.');
  }
  final tagTarget = await _gitOrNull(root, <String>[
    'rev-list',
    '-n',
    '1',
    'refs/tags/$tag',
  ]);
  final tagVerification = await Process.run('git', <String>[
    'verify-tag',
    tag,
  ], workingDirectory: root.path);
  if (tagTarget?.trim() != sourceSha || tagVerification.exitCode != 0) {
    errors.add('The signed RC tag is absent, invalid, or cross-SHA.');
  }

  final ledgerEntries = <Map<String, Object?>>[];
  for (final line in ledgerFile.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    ledgerEntries.add(_object(jsonDecode(line)));
  }
  if (ledgerEntries.isEmpty ||
      ledgerEntries.any(
        (entry) =>
            entry['schemaVersion'] != 1 ||
            entry['sourceSha'] != sourceSha ||
            entry['cohortVersion'] != cohort ||
            !_utc(entry['observedAt']),
      ) ||
      !ledgerEntries.any(
        (entry) =>
            entry['event'] == 'remote-cohort-verified' &&
            entry['result'] == 'passed',
      )) {
    errors.add('The append-only RC materialization ledger is incomplete.');
  }
}

Map<String, Object?> _readObject(Directory root, String path) =>
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

bool _validDigest(Object? value) => value is String && _sha256.hasMatch(value);

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

bool _utc(Object? value) {
  if (value is! String) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.isUtc;
}

bool _absoluteUrl(Object? value) =>
    value is String && Uri.tryParse(value)?.hasAbsolutePath == true;

Future<String> _sha256File(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<String?> _gitOrNull(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  return result.exitCode == 0 ? result.stdout as String : null;
}

final class _Options {
  const _Options({required this.contractOnly, this.root, this.bundle});

  factory _Options.parse(List<String> arguments) {
    var contractOnly = false;
    Directory? root;
    Directory? bundle;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument == '--contract-only') {
        if (contractOnly) throw ArgumentError('Duplicate --contract-only.');
        contractOnly = true;
      } else if (argument == '--root' && index + 1 < arguments.length) {
        if (root != null) throw ArgumentError('Duplicate --root.');
        root = Directory(arguments[++index]).absolute;
      } else if (argument == '--bundle' && index + 1 < arguments.length) {
        if (bundle != null) throw ArgumentError('Duplicate --bundle.');
        bundle = Directory(arguments[++index]).absolute;
      } else {
        throw ArgumentError('Unknown or incomplete argument: $argument');
      }
    }
    return _Options(contractOnly: contractOnly, root: root, bundle: bundle);
  }

  final bool contractOnly;
  final Directory? root;
  final Directory? bundle;
}
