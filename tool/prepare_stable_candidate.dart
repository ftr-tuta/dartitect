import 'dart:convert';
import 'dart:io';

/// Prepares only the reviewable working-tree promotion from the final RC.
///
/// The script performs no tag, push, release, package publication, signature,
/// or network write. Formal V1S-17 evidence is checked before any file write.
Future<void> main(List<String> arguments) async {
  try {
    final root = _root(arguments);
    await _requireStableReadiness(root);
    final contract = _read(root, 'tool/stable_candidate_contract.json');
    final structural = await _run(root, Platform.resolvedExecutable, const [
      'run',
      'tool/check_stable_candidate.dart',
      '--contract-only',
    ]);
    if (structural.exitCode != 0) {
      throw StateError('The V1-18 tooling contract is invalid.');
    }
    final preparation = _object(contract['preparation']);
    if (preparation['externalWrites'] != false) {
      throw StateError('Stable preparation must forbid external writes.');
    }
    final decision = _read(root, 'tool/stable_readiness_decision.json');
    final release = _read(root, 'tool/package_release_contract.json');
    final rcVersion = release['cohortVersion'];
    final stableVersion = contract['stableVersion'];
    final stableConstraint = contract['stableInternalConstraint'];
    if (decision['state'] != 'READY_FOR_1_0' ||
        decision['rcSourceSha'] is! String ||
        rcVersion is! String ||
        stableVersion is! String ||
        stableConstraint is! String ||
        !RegExp(contract['finalRcVersionPattern']! as String)
            .hasMatch(rcVersion)) {
      throw StateError('The final RC identity is not promotable.');
    }
    final branch = await _git(root, const <String>['branch', '--show-current']);
    if (branch.trim() != 'main') {
      throw StateError('Stable preparation requires the main branch.');
    }
    final dirty = await _git(root, const <String>[
      'status',
      '--porcelain=v1',
      '--untracked-files=no',
    ]);
    if (dirty.trim().isNotEmpty) {
      throw StateError('Stable preparation requires a clean tracked tree.');
    }
    final ancestry = await _run(root, 'git', <String>[
      'merge-base',
      '--is-ancestor',
      decision['rcSourceSha']! as String,
      'HEAD',
    ]);
    if (ancestry.exitCode != 0) {
      throw StateError('The final RC is not an ancestor of main HEAD.');
    }

    final order = _strings(release['publicationOrder']);
    if (order.length != contract['requiredPackageCount'] ||
        order.toSet().length != order.length) {
      throw StateError('The release order is not the exact stable cohort.');
    }
    final historical = _strings(preparation['historicalRcPaths']).toSet();
    final edits = <String, String>{};
    final tracked = await _trackedPaths(root);
    for (final path in tracked) {
      if (historical.contains(path) ||
          path == 'tool/package_release_contract.json' ||
          RegExp(r'^packages/[^/]+/CHANGELOG\.md$').hasMatch(path)) {
        continue;
      }
      final file = File('${root.path}/$path');
      String source;
      try {
        source = utf8.decode(file.readAsBytesSync());
      } on FormatException {
        continue;
      }
      if (!source.contains(rcVersion)) continue;
      edits[path] = source
          .replaceAll('>=$rcVersion <1.0.0', stableConstraint)
          .replaceAll(rcVersion, stableVersion);
    }

    final promotedRelease = Map<String, Object?>.from(release)
      ..['cohortVersion'] = stableVersion
      ..['internalConstraint'] = stableConstraint;
    edits['tool/package_release_contract.json'] =
        '${const JsonEncoder.withIndent('  ').convert(promotedRelease)}\n';
    for (final package in order) {
      final pubspecPath = 'packages/$package/pubspec.yaml';
      final pubspec =
          edits[pubspecPath] ??
          File('${root.path}/$pubspecPath').readAsStringSync();
      if (_field(pubspec, 'name') != package ||
          _field(pubspec, 'version') != stableVersion) {
        throw StateError('$package could not be promoted to $stableVersion.');
      }
      final changelogPath = 'packages/$package/CHANGELOG.md';
      final oldChangelog = File('${root.path}/$changelogPath')
          .readAsStringSync();
      if (!_startsWithHeading(oldChangelog, rcVersion)) {
        throw StateError('$package changelog does not begin with $rcVersion.');
      }
      edits[changelogPath] =
          '## $stableVersion\n\n'
          '- Promote the final validated RC without functional changes.\n\n'
          '$oldChangelog';
    }

    final inventoryPath = 'tool/sdk_inventory.json';
    final inventory = _object(
      jsonDecode(
        edits[inventoryPath] ??
            File('${root.path}/$inventoryPath').readAsStringSync(),
      ),
    )..['status'] = 'STABLE_CANDIDATE';
    edits[inventoryPath] =
        '${const JsonEncoder.withIndent('  ').convert(inventory)}\n';
    final candidate = _read(root, 'tool/stable_candidate_record.json');
    final authorization = _read(
      root,
      'tool/stable_publication_authorization.json',
    );
    if (candidate['state'] != 'NOT_ASSEMBLED' ||
        authorization['state'] != 'NOT_AUTHORIZED') {
      throw StateError(
        'Promotion records must remain fail-closed while editing.',
      );
    }

    for (final entry in edits.entries) {
      File('${root.path}/${entry.key}').writeAsStringSync(entry.value);
    }
    stdout.writeln(
      'Prepared ${edits.length} tracked release-metadata files for '
      '$stableVersion. Review the diff, refresh generated supply-chain and '
      'lock artifacts, run all gates, and commit a new candidate SHA. No '
      'external write was performed.',
    );
  } on Object catch (error) {
    stderr.writeln('Stable candidate preparation stopped: $error');
    exitCode = 1;
  }
}

Future<void> _requireStableReadiness(Directory root) async {
  final result = await _run(root, Platform.resolvedExecutable, const <String>[
    'run',
    'tool/check_rc_validation.dart',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Formal V1S-17 READY_FOR_1_0 evidence is required before any file write.',
    );
  }
}

Directory _root(List<String> arguments) {
  if (arguments.isEmpty) {
    return File.fromUri(Platform.script).parent.parent.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments[1]).absolute;
  }
  throw const FormatException(
    'Usage: dart run tool/prepare_stable_candidate.dart [--root PATH]',
  );
}

Future<List<String>> _trackedPaths(Directory root) async {
  final value = await _git(root, const <String>['ls-files', '-z']);
  return value
      .split('\u0000')
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
}

Future<String> _git(Directory root, List<String> arguments) async {
  final result = await _run(root, 'git', arguments);
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<ProcessResult> _run(
  Directory root,
  String executable,
  List<String> arguments,
) => Process.run(executable, arguments, workingDirectory: root.path);

Map<String, Object?> _read(Directory root, String path) =>
    _object(jsonDecode(File('${root.path}/$path').readAsStringSync()));

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string list.');
  }
  return value.cast<String>();
}

String? _field(String source, String name) => RegExp(
  '^${RegExp.escape(name)}:\\s*([^\\s]+)',
  multiLine: true,
).firstMatch(source)?.group(1);

bool _startsWithHeading(String source, String version) =>
    RegExp('^##\\s+${RegExp.escape(version)}(?:\\s|\$)').hasMatch(source);
