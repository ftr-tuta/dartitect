import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts the permanent 25-package lockstep contract', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('25 packages'));
    expect(result.stdout, contains('workspace lockstep cohort'));
  });

  test('rejects package metadata outside lockstep', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.updateContract((contract) {
      final packages = contract['packages']! as Map<String, Object?>;
      final sync = packages['dartitect_sync']! as Map<String, Object?>;
      sync['version'] = '1.0.1';
    });

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('stable release metadata'));
  });

  test('rejects a workspace package version outside lockstep', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final pubspec = File(
      '${fixture.root.path}/packages/dartitect_sync/pubspec.yaml',
    );
    await pubspec.writeAsString(
      (await pubspec.readAsString()).replaceFirst(
        'version: 1.1.0-rc.2',
        'version: 1.1.0-rc.3',
      ),
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('must declare the lockstep version'));
  });

  test('rejects a non-canonical package path', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.updateContract((contract) {
      final paths = contract['packagePaths']! as Map<String, Object?>;
      paths['dartitect_sync'] = 'packages/dartitect';
    });

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('non-canonical package path'));
  });

  test('rejects a dependency order that is not topological', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.updateContract((contract) {
      final order = contract['dependencyOrder']! as List<Object?>;
      final dependency = order.indexOf('dartitect');
      final consumer = order.indexOf('dartitect_sync');
      final value = order.removeAt(dependency);
      order.insert(consumer, value);
    });

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Dependency order is not topological'));
  });

  test('rejects legacy independent-publication semantics', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.updateContract((contract) {
      contract['compatibility'] = <String, Object?>{
        'stableIndependentPatches': true,
      };
    });

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Independent-patch'));
  });

  test('rejects a materialized prerelease workspace tag', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.updateContract((contract) {
      final workspace = contract['workspaceCohort']! as Map<String, Object?>;
      workspace
        ..['version'] = '1.1.0-rc.1'
        ..['channel'] = 'candidate'
        ..['derivedTag'] = 'v1.1.0-rc.1'
        ..['tagMaterialized'] = true;
    });

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('tag materialization'));
  });

  test('accepts package-specific non-empty Unreleased entries', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final changelog = File(
      '${fixture.root.path}/packages/dartitect_sync/CHANGELOG.md',
    );
    await changelog.writeAsString(
      (await changelog.readAsString()).replaceFirst(
        '## Unreleased\n\n',
        '## Unreleased\n\n- Package-specific candidate note.\n',
      ),
    );

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('rejects a partial Unreleased changelog cohort', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final changelog = File(
      '${fixture.root.path}/packages/dartitect_sync/CHANGELOG.md',
    );
    await changelog.writeAsString(
      (await changelog.readAsString()).replaceFirst(
        RegExp(r'## Unreleased\n\n.*?\n\n(?=## )', dotAll: true),
        '',
      ),
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Unreleased changelog cohort is partial'));
  });
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  static Future<_Fixture> create() async {
    final source = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp(
      'package-release-contract-',
    );
    final contract = File('${root.path}/tool/package_release_contract.json');
    await contract.parent.create(recursive: true);
    await File('${source.path}/tool/package_release_contract.json')
        .copy(contract.path);
    final contractData =
        jsonDecode(await contract.readAsString()) as Map<String, Object?>;
    final versionSources =
        contractData['workspaceVersionSources']! as Map<String, Object?>;
    for (final path in <String>{
      ...(versionSources['manifests']! as List<Object?>).cast<String>(),
      ...(versionSources['nativeManifests']! as List<Object?>).cast<String>(),
      ...(versionSources['structuredDerivatives']! as List<Object?>)
          .cast<String>(),
    }) {
      final destination = File('${root.path}/$path');
      await destination.parent.create(recursive: true);
      await File('${source.path}/$path').copy(destination.path);
    }
    for (final package in Directory(
      '${source.path}/packages',
    ).listSync(followLinks: false).whereType<Directory>()) {
      final name = _basename(package.path);
      final destination = Directory('${root.path}/packages/$name');
      await destination.create(recursive: true);
      await File('${package.path}/pubspec.yaml')
          .copy('${destination.path}/pubspec.yaml');
      await File('${package.path}/CHANGELOG.md')
          .copy('${destination.path}/CHANGELOG.md');
    }
    return _Fixture(root);
  }

  Future<void> updateContract(
    void Function(Map<String, Object?> contract) update,
  ) async {
    final file = File('${root.path}/tool/package_release_contract.json');
    final contract =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    update(contract);
    await file.writeAsString(jsonEncode(contract));
  }

  Future<ProcessResult> check() =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/check_package_release_contract.dart',
        '--root',
        root.path,
      ]);

  Future<void> dispose() => root.delete(recursive: true);
}

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;
