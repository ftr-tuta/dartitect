import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Downloads the materialized signed bundle and runs all packaged canaries.
Future<void> main(List<String> arguments) async {
  Directory? temporary;
  try {
    final repository = _repository(arguments);
    final root = File.fromUri(Platform.script).parent.parent.absolute;
    final artifacts = await _run(
      root,
      Platform.resolvedExecutable,
      const <String>['run', 'tool/check_rc_artifacts.dart'],
      allowFailure: true,
    );
    if (artifacts.exitCode != 0) {
      throw StateError(
        'A verified materialized RC is required before channel canaries.\n'
        '${artifacts.stderr}',
      );
    }
    final decision = _read(root, 'tool/rc_readiness_decision.json');
    final release = _read(root, 'tool/package_release_contract.json');
    final contract = _read(root, 'tool/rc_bundle_contract.json');
    final sourceSha = decision['sourceSha']! as String;
    final cohort = release['cohortVersion']! as String;
    final localBundle = Directory(
      '${root.path}/${contract['outputDirectory']}/$cohort/$sourceSha',
    );
    final materialization = _object(
      jsonDecode(
        File('${localBundle.path}/materialization-receipt.json')
            .readAsStringSync(),
      ),
    );
    temporary = await Directory.systemTemp.createTemp(
      'dartitect-materialized-rc-',
    );
    final downloaded = await _run(root, 'gh', <String>[
      'release',
      'download',
      materialization['tag']! as String,
      '--repo',
      repository,
      '--dir',
      temporary.path,
    ], allowFailure: true);
    if (downloaded.exitCode != 0) {
      throw StateError('RC channel download failed: ${downloaded.stderr}');
    }
    final remoteManifest = File('${temporary.path}/bundle-manifest.json');
    final remoteSignature = File('${remoteManifest.path}.asc');
    if (!remoteManifest.existsSync() ||
        !remoteSignature.existsSync() ||
        await _digest(remoteManifest) != materialization['manifestSha256'] ||
        await _digest(remoteSignature) != materialization['signatureSha256']) {
      throw StateError('Downloaded RC manifest/signature digest mismatch.');
    }
    for (final name in const <String>[
      'materialization-receipt.json',
      'materialization-ledger.jsonl',
    ]) {
      await File('${localBundle.path}/$name').copy('${temporary.path}/$name');
    }
    final manifest = _object(jsonDecode(remoteManifest.readAsStringSync()));
    for (final package in _objects(manifest['packages'])) {
      final archive = File('${temporary.path}/${package['archive']}');
      // GitHub release downloads flatten asset names. Restore the manifest
      // layout only inside the disposable channel directory.
      final flattened = File(
        '${temporary.path}/${(package['archive']! as String).split('/').last}',
      );
      if (!archive.existsSync() && flattened.existsSync()) {
        await archive.parent.create(recursive: true);
        await flattened.rename(archive.path);
      }
      if (!archive.existsSync() ||
          await _digest(archive) != package['archiveSha256']) {
        throw StateError(
          'Downloaded ${package['package']} archive digest mismatch.',
        );
      }
    }
    final canaries = await _run(root, Platform.resolvedExecutable, <String>[
      'run',
      'tool/check_canaries.dart',
      '--bundle=${temporary.path}',
    ], allowFailure: true);
    stdout.write(canaries.stdout);
    if (canaries.exitCode != 0) {
      throw StateError(
        'Materialized channel canaries failed: ${canaries.stderr}',
      );
    }
    final canaryReceipt = File(
      '${root.path}/build/canary-receipts/v1s17-$sourceSha.json',
    );
    if (!canaryReceipt.existsSync()) {
      throw StateError('V1S-17 canary receipt was not produced.');
    }
    final wrapperDirectory = Directory('${root.path}/build/rc-validation');
    await wrapperDirectory.create(recursive: true);
    final wrapper = File('${wrapperDirectory.path}/canaries-$sourceSha.json');
    await wrapper.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'goal': 'V1S-17', 'sourceSha': sourceSha, 'cohortVersion': cohort, 'channel': 'signed-bundle', 'remoteReleaseUrl': materialization['remoteReleaseUrl'], 'manifestSha256': materialization['manifestSha256'], 'canaryReceipt': 'build/canary-receipts/v1s17-$sourceSha.json', 'canaryReceiptSha256': await _digest(canaryReceipt), 'result': 'passed', 'completedAt': DateTime.now().toUtc().toIso8601String()})}\n',
      flush: true,
    );
    stdout.writeln('Materialized RC channel canaries passed for $sourceSha.');
  } on Object catch (error) {
    stderr.writeln('RC channel canaries stopped: $error');
    exitCode = 1;
  } finally {
    if (temporary case final directory? when directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

String _repository(List<String> arguments) {
  if (arguments.length != 1 || !arguments.single.startsWith('--repository=')) {
    throw ArgumentError('Required --repository=<owner/name>.');
  }
  final value = arguments.single.substring('--repository='.length);
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(value)) {
    throw ArgumentError('Invalid GitHub repository name.');
  }
  return value;
}

Map<String, Object?> _read(Directory root, String path) =>
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

Future<String> _digest(File file) async =>
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
