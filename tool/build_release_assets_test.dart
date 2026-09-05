import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'fixtures/titect_evidence_fixture.dart';

const _sha = '1111111111111111111111111111111111111111';
const _tree = '2222222222222222222222222222222222222222';

void main() {
  test('prepared release snippets use its tag while provenance preserves prior distribution', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final contractFile = File(
      '${fixture.root.path}/tool/package_release_contract.json',
    );
    final source =
        jsonDecode(await contractFile.readAsString()) as Map<String, Object?>;
    final prior = source['distributedCohort'];
    (source['workspaceCohort']! as Map<String, Object?>).addAll({
      'version': '1.2.0',
      'channel': 'stable',
      'derivedTag': 'v1.2.0',
      'tagMaterialized': false,
    });
    (source['workspaceInternalDependency']!
            as Map<String, Object?>)['version'] =
        '1.2.0';
    await contractFile.writeAsString(jsonEncode(source));
    final before = await contractFile.readAsBytes();
    final output = Directory('${fixture.root.path}/prepared');
    final result = await fixture.build(output);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final zip = utf8.decode(
      await File('${output.path}/dependency-snippets.zip').readAsBytes(),
      allowMalformed: true,
    );
    expect(zip, contains('version: 1.2.0'));
    expect(zip, isNot(contains('version: 1.1.0')));
    final provenance = jsonDecode(
      await File('${output.path}/release-provenance.json').readAsString(),
    ) as Map<String, Object?>;
    expect(provenance['previousDistribution'], prior);
    expect(provenance['sourceTagMaterialized'], false);
    final manifest = jsonDecode(
      await File('${output.path}/dartitect-git-manifest.json').readAsString(),
    ) as Map<String, Object?>;
    expect(manifest['releaseTag'], 'v1.2.0');
    final packages = (manifest['packages']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(packages, hasLength(25));
    expect(packages.every((p) => p['version'] == '1.2.0'), isTrue);
    expect(await contractFile.readAsBytes(), before);
  });

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
      'titect-chrome.json',
      'titect-conformance.json',
      'titect-python.json',
      'titect-recovery.json',
      'titect-vm.json',
      'titect-web.json',
    ]);
    for (final name in names) {
      expect(
        await File('${first.path}/$name').readAsBytes(),
        await File('${second.path}/$name').readAsBytes(),
        reason: name,
      );
    }
    final sums = await File('${first.path}/SHA256SUMS').readAsLines();
    expect(sums, hasLength(12));
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
    expect(result.stderr, contains('prerelease or inconsistent stable cohort'));
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
    final digests = await createTitectEvidenceFixture(
      root: root,
      artifactRoot: root,
      sha: sourceSha,
      tree: _tree,
      runAttempt: 2,
    );
    final readiness = File('${root.path}/actions-readiness-v1.json');
    await readiness.writeAsString(
      jsonEncode(<String, Object?>{
        'sourceSha': sourceSha,
        'sourceTree': _tree,
        'runId': 123,
        'runAttempt': 2,
        'artifactDigests': digests,
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
