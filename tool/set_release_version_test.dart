import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('previews the exact candidate update without writing', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final before = await fixture.contract.readAsString();

    final result = await fixture.run('1.1.0-rc.1');

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Previewing workspace cohort'));
    expect(
      result.stdout,
      contains('UPDATE tool/package_release_contract.json'),
    );
    expect(await fixture.contract.readAsString(), before);
  });

  test(
    'applies candidate sources while retaining stable distribution',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.run('1.1.0-rc.1', apply: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final contract = jsonDecode(
        await fixture.contract.readAsString(),
      ) as Map<String, Object?>;
      expect(
        contract['workspaceCohort'],
        containsPair('version', '1.1.0-rc.1'),
      );
      expect(contract['workspaceCohort'], containsPair('channel', 'candidate'));
      expect(
        contract['workspaceCohort'],
        containsPair('tagMaterialized', false),
      );
      expect(contract['distributedCohort'], containsPair('version', '1.0.0'));
      expect(
        await File(
          '${fixture.root.path}/packages/dartitect_observability/pubspec.yaml',
        ).readAsString(),
        contains('version: 1.1.0-rc.1'),
      );
      expect(
        await File('${fixture.root.path}/tool/canaries/canary_contract.json')
            .readAsString(),
        contains('v1.1.0-rc.1'),
      );
      expect(
        await File('${fixture.root.path}/tool/api_surface.snapshot.json')
            .readAsString(),
        contains('"sdkVersion": "1.1.0-rc.1"'),
      );
    },
  );

  test('rejects a version behind the distributed stable cohort', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final before = await fixture.contract.readAsString();

    final result = await fixture.run('0.9.9', apply: true);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('not precede distributed 1.0.0'));
    expect(await fixture.contract.readAsString(), before);
  });

  test('validates every declared target before the first write', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final before = await fixture.contract.readAsString();
    await File(
      '${fixture.root.path}/tool/dartitect_devtools_extension/pubspec.yaml',
    ).delete();

    final result = await fixture.run('1.1.0-rc.1', apply: true);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Missing version source'));
    expect(await fixture.contract.readAsString(), before);
  });
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  File get contract => File('${root.path}/tool/package_release_contract.json');

  static Future<_Fixture> create() async {
    final sourceRoot = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp('release-version-');
    final contractSource = File(
      '${sourceRoot.path}/tool/package_release_contract.json',
    );
    final contract =
        jsonDecode(await contractSource.readAsString()) as Map<String, Object?>;
    final packagePaths = (contract['packagePaths']! as Map<String, Object?>)
        .values
        .cast<String>();
    final sources =
        contract['workspaceVersionSources']! as Map<String, Object?>;
    final paths = <String>{
      'tool/package_release_contract.json',
      for (final path in packagePaths) '$path/pubspec.yaml',
      ...(sources['manifests']! as List<Object?>).cast<String>(),
      ...(sources['nativeManifests']! as List<Object?>).cast<String>(),
      ...(sources['structuredDerivatives']! as List<Object?>).cast<String>(),
    };
    for (final path in paths) {
      final target = File('${root.path}/$path');
      await target.parent.create(recursive: true);
      await File('${sourceRoot.path}/$path').copy(target.path);
    }
    return _Fixture(root);
  }

  Future<ProcessResult> run(String version, {bool apply = false}) =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/set_release_version.dart',
        version,
        '--root=${root.path}',
        if (apply) '--apply',
      ], workingDirectory: Directory.current.path);

  Future<void> dispose() => root.delete(recursive: true);
}
