import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Signs, tags, uploads, and verifies one authorized V1S-16 bundle.
///
/// Every external mutation is preceded by the formal V1S-15 gate. Existing
/// same-name remote assets are downloaded and digest-checked, never replaced.
Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root =
        options.root ?? File.fromUri(Platform.script).parent.parent.absolute;
    await _requireReadiness(root);
    final decision = _readObject(root, 'tool/rc_readiness_decision.json');
    final authorization = _readObject(
      root,
      'tool/rc_distribution_authorization.json',
    );
    final release = _readObject(root, 'tool/package_release_contract.json');
    final contract = _readObject(root, 'tool/rc_bundle_contract.json');
    if (authorization['channel'] != 'signed-bundle' ||
        authorization['state'] != 'AUTHORIZED') {
      throw StateError('V1S-15 did not authorize the signed-bundle channel.');
    }
    final sourceSha = decision['sourceSha']! as String;
    final cohort = release['cohortVersion']! as String;
    final bundle =
        options.bundle ??
        Directory(
          '${root.path}/${contract['outputDirectory']}/$cohort/$sourceSha',
        );
    final manifest = File('${bundle.path}/bundle-manifest.json');
    final signature = File('${manifest.path}.asc');
    final ledger = File('${bundle.path}/materialization-ledger.jsonl');
    final receipt = File('${bundle.path}/materialization-receipt.json');
    if (!manifest.existsSync()) {
      throw StateError('Prepare the exact authorized bundle before signing.');
    }
    final manifestValue = _object(jsonDecode(manifest.readAsStringSync()));
    if (manifestValue['state'] != 'CANDIDATE_BUNDLE' ||
        manifestValue['sourceSha'] != sourceSha ||
        manifestValue['sourceTree'] != decision['sourceTree'] ||
        manifestValue['cohortVersion'] != cohort ||
        manifestValue['channel'] != 'signed-bundle') {
      throw StateError('The staged bundle is not the authorized candidate.');
    }
    final dirty = await _run(root, 'git', const <String>[
      'status',
      '--porcelain=v1',
      '--untracked-files=no',
    ]);
    if (dirty.stdout.trim().isNotEmpty) {
      throw StateError('Materialization requires a clean tracked tree.');
    }
    if (receipt.existsSync()) {
      final verification = await _run(
        root,
        Platform.resolvedExecutable,
        <String>[
          'run',
          'tool/check_rc_artifacts.dart',
          '--bundle',
          bundle.path,
        ],
        allowFailure: true,
      );
      if (verification.exitCode == 0) {
        stdout.writeln('The authorized RC bundle is already materialized.');
        return;
      }
      throw StateError(
        'A final receipt exists but verification failed; preserve the bundle '
        'for incident review.\n${verification.stderr}',
      );
    }

    final fingerprint = await _secretFingerprint(root, options.signingKey);
    await _append(
      ledger,
      _event(sourceSha, cohort, 'materialization-started', 'pending'),
    );
    if (signature.existsSync()) {
      await _requireSignature(root, signature, manifest, fingerprint);
      await _append(
        ledger,
        _event(sourceSha, cohort, 'manifest-signature-resumed', 'verified'),
      );
    } else {
      final signed = await _run(root, 'gpg', <String>[
        '--batch',
        '--armor',
        '--detach-sign',
        '--local-user',
        fingerprint,
        '--output',
        signature.path,
        manifest.path,
      ], allowFailure: true);
      if (signed.exitCode != 0) {
        await _append(
          ledger,
          _event(sourceSha, cohort, 'manifest-signature-failed', 'failed'),
        );
        throw StateError('Manifest signing failed: ${signed.stderr}');
      }
      await _requireSignature(root, signature, manifest, fingerprint);
      await _append(
        ledger,
        _event(sourceSha, cohort, 'manifest-signed', 'verified'),
      );
    }

    final tag = 'v$cohort';
    final existingTag = await _run(root, 'git', <String>[
      'rev-list',
      '-n',
      '1',
      'refs/tags/$tag',
    ], allowFailure: true);
    if (existingTag.exitCode == 0) {
      if (existingTag.stdout.trim() != sourceSha) {
        throw StateError('$tag already points to another source SHA.');
      }
      await _requireTagSignature(root, tag);
      await _append(
        ledger,
        _event(sourceSha, cohort, 'signed-tag-resumed', 'verified'),
      );
    } else {
      final created = await _run(root, 'git', <String>[
        'tag',
        '-s',
        '-u',
        fingerprint,
        '-m',
        'Dartitect $cohort signed bundle',
        tag,
        sourceSha,
      ], allowFailure: true);
      if (created.exitCode != 0) {
        await _append(
          ledger,
          _event(sourceSha, cohort, 'signed-tag-failed', 'failed'),
        );
        throw StateError('Signed tag creation failed: ${created.stderr}');
      }
      await _requireTagSignature(root, tag);
      await _append(
        ledger,
        _event(sourceSha, cohort, 'signed-tag-created', 'verified'),
      );
    }

    final remoteTag = await _run(root, 'git', <String>[
      'ls-remote',
      '--tags',
      options.remote,
      'refs/tags/$tag^{}',
    ], allowFailure: true);
    if (remoteTag.exitCode != 0 || remoteTag.stdout.trim().isEmpty) {
      final pushed = await _run(root, 'git', <String>[
        'push',
        options.remote,
        'refs/tags/$tag:refs/tags/$tag',
      ], allowFailure: true);
      if (pushed.exitCode != 0) {
        await _append(
          ledger,
          _event(sourceSha, cohort, 'signed-tag-push-failed', 'failed'),
        );
        throw StateError('Signed tag push failed: ${pushed.stderr}');
      }
      final pushedTag = await _run(root, 'git', <String>[
        'ls-remote',
        '--tags',
        options.remote,
        'refs/tags/$tag^{}',
      ], allowFailure: true);
      if (pushedTag.exitCode != 0 ||
          !pushedTag.stdout.trim().startsWith(sourceSha)) {
        throw StateError('The pushed signed tag cannot be verified remotely.');
      }
    } else if (!remoteTag.stdout.trim().startsWith(sourceSha)) {
      throw StateError('Remote $tag resolves to another source SHA.');
    }
    await _append(
      ledger,
      _event(sourceSha, cohort, 'remote-signed-tag-verified', 'verified'),
    );

    var releaseView = await _releaseView(root, options.repository, tag);
    if (releaseView == null) {
      final created = await _run(root, 'gh', <String>[
        'release',
        'create',
        tag,
        '--repo',
        options.repository,
        '--verify-tag',
        '--prerelease',
        '--title',
        'Dartitect $cohort',
        '--notes',
        'Signed RC bundle for exact source $sourceSha.',
      ], allowFailure: true);
      if (created.exitCode != 0) {
        await _append(
          ledger,
          _event(
            sourceSha,
            cohort,
            'github-prerelease-create-failed',
            'failed',
          ),
        );
        throw StateError(
          'GitHub prerelease creation failed: ${created.stderr}',
        );
      }
      releaseView = await _releaseView(root, options.repository, tag);
    }
    if (releaseView == null ||
        releaseView['isPrerelease'] != true ||
        releaseView['tagName'] != tag ||
        !_absoluteUrl(releaseView['url'])) {
      throw StateError('The GitHub prerelease identity is invalid.');
    }
    var verifiedRelease = releaseView;

    final packageValues = _objects(manifestValue['packages']);
    final remotePackages = <Map<String, Object?>>[];
    for (final package in packageValues) {
      final archive = File('${bundle.path}/${package['archive']}');
      final asset = await _uploadOrVerifyAsset(
        root: root,
        repository: options.repository,
        tag: tag,
        releaseView: verifiedRelease,
        file: archive,
        expectedDigest: package['archiveSha256']! as String,
      );
      remotePackages.add(<String, Object?>{
        'package': package['package'],
        'orderIndex': package['orderIndex'],
        'archiveSha256': package['archiveSha256'],
        'state': 'verified',
        'remoteAssetUrl': asset['url'],
      });
      await _append(
        ledger,
        _event(
          sourceSha,
          cohort,
          'package-asset-verified',
          'verified',
          package: package['package']! as String,
          orderIndex: package['orderIndex']! as int,
        ),
      );
      verifiedRelease =
          await _releaseView(root, options.repository, tag) ?? verifiedRelease;
    }
    for (final asset in <File>[manifest, signature]) {
      await _uploadOrVerifyAsset(
        root: root,
        repository: options.repository,
        tag: tag,
        releaseView: verifiedRelease,
        file: asset,
        expectedDigest: await _sha256File(asset),
      );
      verifiedRelease =
          await _releaseView(root, options.repository, tag) ?? verifiedRelease;
    }

    final finalReceipt = <String, Object?>{
      'schemaVersion': 1,
      'goal': 'V1S-16',
      'state': 'MATERIALIZED',
      'channel': 'signed-bundle',
      'sourceSha': sourceSha,
      'cohortVersion': cohort,
      'manifestSha256': await _sha256File(manifest),
      'signatureSha256': await _sha256File(signature),
      'signingFingerprint': fingerprint,
      'tag': tag,
      'remoteReleaseUrl': verifiedRelease['url'],
      'remoteDigestVerified': true,
      'materializedAt': DateTime.now().toUtc().toIso8601String(),
      'packages': remotePackages,
    };
    await _append(
      ledger,
      _event(sourceSha, cohort, 'remote-cohort-verified', 'passed'),
    );
    await receipt.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(finalReceipt)}\n',
      flush: true,
    );
    final verification = await _run(root, Platform.resolvedExecutable, <String>[
      'run',
      'tool/check_rc_artifacts.dart',
      '--bundle',
      bundle.path,
    ], allowFailure: true);
    if (verification.exitCode != 0) {
      throw StateError(
        'Post-materialization verification failed: ${verification.stderr}',
      );
    }
    stdout.writeln(
      'Materialized and verified $cohort at ${verifiedRelease['url']}.',
    );
  } on Object catch (error) {
    stderr.writeln('RC bundle materialization stopped: $error');
    exitCode = 1;
  }
}

Future<void> _requireReadiness(Directory root) async {
  final result = await _run(root, Platform.resolvedExecutable, const <String>[
    'run',
    'tool/check_rc_readiness.dart',
  ], allowFailure: true);
  if (result.exitCode != 0) {
    throw StateError(
      'Formal V1S-15 readiness is required before any external write.\n'
      '${result.stderr}',
    );
  }
}

Future<String> _secretFingerprint(Directory root, String key) async {
  final result = await _run(root, 'gpg', <String>[
    '--batch',
    '--with-colons',
    '--fingerprint',
    '--list-secret-keys',
    key,
  ], allowFailure: true);
  if (result.exitCode != 0) {
    throw StateError('The configured OpenPGP secret key is unavailable.');
  }
  final fingerprints = const LineSplitter()
      .convert(result.stdout)
      .where((line) => line.startsWith('fpr:'))
      .map((line) => line.split(':')[9])
      .where((value) => RegExp(r'^[0-9A-F]{40,64}$').hasMatch(value))
      .toList();
  if (fingerprints.isEmpty) {
    throw StateError('GPG returned no signing fingerprint for $key.');
  }
  return fingerprints.first;
}

Future<void> _requireSignature(
  Directory root,
  File signature,
  File manifest,
  String fingerprint,
) async {
  final result = await _run(root, 'gpg', <String>[
    '--batch',
    '--status-fd=1',
    '--verify',
    signature.path,
    manifest.path,
  ], allowFailure: true);
  if (result.exitCode != 0 ||
      !const LineSplitter()
          .convert(result.stdout)
          .any(
            (line) =>
                line.startsWith('[GNUPG:] VALIDSIG ') &&
                line.split(' ').contains(fingerprint),
          )) {
    throw StateError('The existing manifest signature is invalid.');
  }
}

Future<void> _requireTagSignature(Directory root, String tag) async {
  final result = await _run(root, 'git', <String>[
    'verify-tag',
    tag,
  ], allowFailure: true);
  if (result.exitCode != 0) {
    throw StateError('The existing $tag signature is invalid.');
  }
}

Future<Map<String, Object?>?> _releaseView(
  Directory root,
  String repository,
  String tag,
) async {
  final result = await _run(root, 'gh', <String>[
    'release',
    'view',
    tag,
    '--repo',
    repository,
    '--json',
    'assets,isPrerelease,tagName,url',
  ], allowFailure: true);
  return result.exitCode == 0 ? _object(jsonDecode(result.stdout)) : null;
}

Future<Map<String, Object?>> _uploadOrVerifyAsset({
  required Directory root,
  required String repository,
  required String tag,
  required Map<String, Object?> releaseView,
  required File file,
  required String expectedDigest,
}) async {
  final name = file.uri.pathSegments.last;
  var matches = _objects(releaseView['assets'])
      .where((asset) => asset['name'] == name);
  if (matches.length > 1) {
    throw StateError('GitHub contains duplicate assets named $name.');
  }
  if (matches.isEmpty) {
    final uploaded = await _run(root, 'gh', <String>[
      'release',
      'upload',
      tag,
      file.path,
      '--repo',
      repository,
    ], allowFailure: true);
    if (uploaded.exitCode != 0) {
      throw StateError('Upload stopped at $name: ${uploaded.stderr}');
    }
    final refreshed = await _releaseView(root, repository, tag);
    if (refreshed == null) throw StateError('Cannot re-query uploaded $name.');
    matches = _objects(refreshed['assets'])
        .where((asset) => asset['name'] == name);
  }
  if (matches.length != 1 || !_absoluteUrl(matches.single['url'])) {
    throw StateError('Cannot identify immutable remote asset $name.');
  }
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-rc-remote-asset-',
  );
  try {
    final downloaded = await _run(root, 'gh', <String>[
      'release',
      'download',
      tag,
      '--repo',
      repository,
      '--pattern',
      name,
      '--dir',
      temporary.path,
    ], allowFailure: true);
    final remoteFile = File('${temporary.path}/$name');
    if (downloaded.exitCode != 0 ||
        !remoteFile.existsSync() ||
        await _sha256File(remoteFile) != expectedDigest) {
      throw StateError('Remote asset digest mismatch for $name.');
    }
  } finally {
    await temporary.delete(recursive: true);
  }
  return matches.single;
}

Map<String, Object?> _event(
  String sourceSha,
  String cohort,
  String event,
  String result, {
  String? package,
  int? orderIndex,
}) => <String, Object?>{
  'schemaVersion': 1,
  'goal': 'V1S-16',
  'sourceSha': sourceSha,
  'cohortVersion': cohort,
  'event': event,
  'result': result,
  if (package != null) 'package': package,
  if (orderIndex != null) 'orderIndex': orderIndex,
  'observedAt': DateTime.now().toUtc().toIso8601String(),
};

Future<void> _append(File file, Map<String, Object?> event) async {
  await file.parent.create(recursive: true);
  await file.writeAsString('${jsonEncode(event)}\n', mode: FileMode.append);
}

Map<String, Object?> _readObject(Directory root, String path) =>
    _object(jsonDecode(File('${root.path}/$path').readAsStringSync()));

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

bool _absoluteUrl(Object? value) =>
    value is String && Uri.tryParse(value)?.hasAbsolutePath == true;

Future<String> _sha256File(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<_Result> _run(
  Directory root,
  String executable,
  List<String> arguments, {
  bool allowFailure = false,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: root.path,
  );
  final value = _Result(
    result.exitCode,
    result.stdout as String,
    result.stderr as String,
  );
  if (!allowFailure && value.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed: ${value.stderr}',
    );
  }
  return value;
}

final class _Result {
  const _Result(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

final class _Options {
  const _Options({
    required this.signingKey,
    required this.repository,
    required this.remote,
    this.root,
    this.bundle,
  });

  factory _Options.parse(List<String> arguments) {
    String? signingKey;
    String? repository;
    var remote = 'origin';
    Directory? root;
    Directory? bundle;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument.startsWith('--signing-key=')) {
        signingKey = argument.substring('--signing-key='.length);
      } else if (argument.startsWith('--repository=')) {
        repository = argument.substring('--repository='.length);
      } else if (argument.startsWith('--remote=')) {
        remote = argument.substring('--remote='.length);
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
    if (signingKey == null || signingKey.trim().isEmpty) {
      throw ArgumentError('Required --signing-key=<OpenPGP key>.');
    }
    if (repository == null ||
        !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw ArgumentError('Required --repository=<owner/name>.');
    }
    if (!RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(remote)) {
      throw ArgumentError('Invalid --remote name.');
    }
    return _Options(
      signingKey: signingKey,
      repository: repository,
      remote: remote,
      root: root,
      bundle: bundle,
    );
  }

  final String signingKey;
  final String repository;
  final String remote;
  final Directory? root;
  final Directory? bundle;
}
