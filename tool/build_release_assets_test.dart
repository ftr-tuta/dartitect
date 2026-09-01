import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _sha = '1111111111111111111111111111111111111111';
const _tree = '2222222222222222222222222222222222222222';

void main() {
  test('builds the exact deterministic immutable Release asset set', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final first = Directory('${fixture.root.path}/first');
    final second = Directory('${fixture.root.path}/second');

    expect((await fixture.build(first)).exitCode, 0);
    expect((await fixture.build(second)).exitCode, 0);

    final names =
        first
            .listSync(followLinks: false)
            .whereType<File>()
            .map((file) => _basename(file.path))
            .toList()
          ..sort();
    expect(names, <String>[
      'SHA256SUMS',
      'actions-readiness-v1.json',
      'dartitect-git-manifest.json',
      'dependency-licenses.json',
      'dependency-snippets.zip',
      'release-provenance.json',
      'sbom.spdx.json',
    ]);
    for (final name in names) {
      expect(
        await File('${first.path}/$name').readAsBytes(),
        await File('${second.path}/$name').readAsBytes(),
        reason: name,
      );
    }
    final sums = await File('${first.path}/SHA256SUMS').readAsLines();
    expect(sums, hasLength(6));
    for (final line in sums) {
      final match = RegExp(r'^([0-9a-f]{64})  ([^/]+)$').firstMatch(line);
      expect(match, isNotNull, reason: line);
      final asset = File('${first.path}/${match!.group(2)}');
      expect(
        sha256.convert(await asset.readAsBytes()).toString(),
        match.group(1),
      );
    }
    final zipText = utf8.decode(
      await File('${first.path}/dependency-snippets.zip').readAsBytes(),
      allowMalformed: true,
    );
    expect(zipText, contains('packages/dartitect.yaml'));
    expect(zipText, contains('packages/dartitect_workmanager.yaml'));
    for (final profile in const <String>[
      'core',
      'flutter',
      'drift',
      'objectbox',
      'tooling',
    ]) {
      expect(zipText, contains('profiles/$profile.yaml'));
    }
  });

  test('rejects readiness identity drift', () async {
    final fixture = await _Fixture.create(sourceSha: '0' * 40);
    addTearDown(fixture.dispose);

    final result = await fixture.build(Directory('${fixture.root.path}/out'));

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Readiness identity differs'));
  });

  test('rejects a candidate workspace before creating assets', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final contract = File(
      '${fixture.root.path}/tool/package_release_contract.json',
    );
    final source = jsonDecode(await contract.readAsString());
    final workspace =
        (source as Map<String, Object?>)['workspaceCohort']!
            as Map<String, Object?>;
    workspace
      ..['version'] = '1.1.0-rc.1'
      ..['channel'] = 'candidate'
      ..['derivedTag'] = 'v1.1.0-rc.1'
      ..['tagMaterialized'] = false;
    await contract.writeAsString(jsonEncode(source));

    final result = await fixture.build(Directory('${fixture.root.path}/out'));

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Release assets reject the candidate'));
  });
}

final class _Fixture {
  const _Fixture(this.root, this.readiness);

  final Directory root;
  final File readiness;

  static Future<_Fixture> create({String sourceSha = _sha}) async {
    final root = await Directory.systemTemp.createTemp('release-assets-');
    for (final path in const <String>[
      'tool/package_release_contract.json',
      'docs/release/sbom.spdx.json',
      'docs/release/dependency-licenses.json',
    ]) {
      final target = File('${root.path}/$path');
      await target.parent.create(recursive: true);
      await File('${Directory.current.path}/$path').copy(target.path);
    }
    final contractFile = File(
      '${root.path}/tool/package_release_contract.json',
    );
    final contract =
        jsonDecode(await contractFile.readAsString()) as Map<String, Object?>;
    final workspace = contract['workspaceCohort']! as Map<String, Object?>;
    workspace
      ..['version'] = '1.0.0'
      ..['channel'] = 'stable'
      ..['derivedTag'] = 'v1.0.0'
      ..['tagMaterialized'] = true;
    await contractFile.writeAsString(jsonEncode(contract));
    final readiness = File('${root.path}/actions-readiness-v1.json');
    await readiness.writeAsString(
      jsonEncode(<String, Object?>{
        'sourceSha': sourceSha,
        'sourceTree': _tree,
        'runId': 123,
        'runAttempt': 2,
      }),
    );
    return _Fixture(root, readiness);
  }

  Future<ProcessResult> build(Directory output) =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/build_release_assets.dart',
        '--output=${output.path}',
        '--readiness=${readiness.path}',
        '--source-sha=$_sha',
        '--source-tree=$_tree',
        '--ci-run-id=123',
        '--ci-run-attempt=2',
        '--root=${root.path}',
      ], workingDirectory: Directory.current.path);

  Future<void> dispose() => root.delete(recursive: true);
}

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;
