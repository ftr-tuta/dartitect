import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts the fail-closed signed-bundle tooling contract', () async {
    final fixture = await _ArtifactFixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(contractOnly: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('no materialization was asserted'));
  });

  test('rejects a forceable release tag contract', () async {
    final fixture = await _ArtifactFixture.create();
    addTearDown(fixture.dispose);
    final contract = fixture.contract;
    (contract['tag']! as Map<String, Object?>)['force'] = true;
    await fixture.writeContract(contract);

    final result = await fixture.check(contractOnly: true);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('tag contract is invalid'));
  });

  test('formal artifact gate refuses absent readiness authorization', () async {
    final fixture = await _ArtifactFixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('materialization is unauthorized'));
  });

  test('preparer emits reproducible topological package archives', () async {
    final fixture = await _BundleFixture.create();
    addTearDown(fixture.dispose);
    final first = Directory('${fixture.root.path}/build/first');
    final second = Directory('${fixture.root.path}/build/second');

    final firstResult = await fixture.prepare(first);
    final secondResult = await fixture.prepare(second);

    expect(
      firstResult.exitCode,
      0,
      reason: '${firstResult.stdout}\n${firstResult.stderr}',
    );
    expect(
      secondResult.exitCode,
      0,
      reason: '${secondResult.stdout}\n${secondResult.stderr}',
    );
    final firstManifest = _json('${first.path}/bundle-manifest.json');
    final secondManifest = _json('${second.path}/bundle-manifest.json');
    final firstPackages = firstManifest['packages']! as List<Object?>;
    final secondPackages = secondManifest['packages']! as List<Object?>;
    expect(firstPackages, hasLength(16));
    expect(
      <Object?>[
        for (final value in firstPackages)
          (value! as Map<String, Object?>)['archiveSha256'],
      ],
      <Object?>[
        for (final value in secondPackages)
          (value! as Map<String, Object?>)['archiveSha256'],
      ],
    );
    expect(
      <Object?>[
        for (final value in firstPackages)
          (value! as Map<String, Object?>)['canonicalSourceSha256'],
      ],
      <Object?>[
        for (final value in secondPackages)
          (value! as Map<String, Object?>)['canonicalSourceSha256'],
      ],
    );
    expect(firstManifest['materialization'], <String, Object?>{
      'authorized': false,
      'signed': false,
      'tagCreated': false,
      'uploaded': false,
    });
  });

  test(
    'materializer refuses before any tag when readiness is absent',
    () async {
      final fixture = await _BundleFixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.materialize();
      final tags = await _run(fixture.root, 'git', const <String>[
        'tag',
        '--list',
      ]);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('Formal V1S-15 readiness is required'));
      expect(tags.stdout.toString().trim(), isEmpty);
    },
  );
}

final class _ArtifactFixture {
  const _ArtifactFixture(this.root, this.contract);

  final Directory root;
  final Map<String, Object?> contract;

  static Future<_ArtifactFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-rc-artifacts-',
    );
    await Directory('${root.path}/tool').create(recursive: true);
    final contract = _json(
      '${Directory.current.path}/tool/rc_bundle_contract.json',
    );
    final fixture = _ArtifactFixture(root, contract);
    await fixture.writeContract(contract);
    await File('${root.path}/tool/package_release_contract.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'publicationOrder': <String>[
          for (var index = 0; index < 16; index += 1) 'package_$index',
        ],
      }),
    );
    return fixture;
  }

  Future<void> writeContract(Map<String, Object?> value) =>
      File('${root.path}/tool/rc_bundle_contract.json')
          .writeAsString(jsonEncode(value));

  Future<ProcessResult> check({bool contractOnly = false}) {
    final checker = '${Directory.current.path}/tool/check_rc_artifacts.dart';
    return Process.run(Platform.resolvedExecutable, <String>[
      checker,
      '--root',
      root.path,
      if (contractOnly) '--contract-only',
    ]);
  }

  Future<void> dispose() => root.delete(recursive: true);
}

final class _BundleFixture {
  const _BundleFixture(this.root);

  final Directory root;

  static Future<_BundleFixture> create() async {
    final root = await Directory.systemTemp.createTemp('dartitect-rc-bundle-');
    await Directory('${root.path}/tool').create(recursive: true);
    await Directory('${root.path}/docs/release').create(recursive: true);
    final names = <String>[
      for (var index = 0; index < 16; index += 1)
        'dartitect_fixture_${index.toString().padLeft(2, '0')}',
    ];
    for (final name in names) {
      final package = Directory('${root.path}/packages/$name');
      await package.create(recursive: true);
      await File('${package.path}/pubspec.yaml').writeAsString('''
name: $name
version: 1.0.0-rc.1
environment:
  sdk: ^3.13.0
''');
      await File('${package.path}/README.md').writeAsString('# $name\n');
    }
    final layers = <List<String>>[
      names.sublist(0, 6),
      names.sublist(6, 12),
      names.sublist(12),
    ];
    await File('${root.path}/tool/package_release_contract.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'cohortVersion': '1.0.0-rc.1',
        'publicationOrder': names,
        'publicationLayers': layers,
      }),
    );
    await File('${root.path}/tool/rc_bundle_contract.json').writeAsString(
      File('${Directory.current.path}/tool/rc_bundle_contract.json')
          .readAsStringSync(),
    );
    for (final path in const <String>[
      'sbom.spdx.json',
      'dependency-licenses.json',
      'advisory-audit.adoc',
    ]) {
      await File('${root.path}/docs/release/$path').writeAsString('$path\n');
    }
    await _run(root, 'git', const <String>['init', '-q']);
    await _run(root, 'git', const <String>['config', 'user.name', 'ftr']);
    await _run(root, 'git', const <String>[
      'config',
      'user.email',
      'ftr@tuta.com',
    ]);
    await _run(root, 'git', const <String>['add', '.']);
    await _run(root, 'git', const <String>['commit', '-qm', 'candidate']);
    return _BundleFixture(root);
  }

  Future<ProcessResult> prepare(Directory output) {
    final preparer = '${Directory.current.path}/tool/prepare_rc_bundle.dart';
    return Process.run(Platform.resolvedExecutable, <String>[
      preparer,
      '--root',
      root.path,
      '--output',
      output.path,
    ]);
  }

  Future<ProcessResult> materialize() {
    final materializer =
        '${Directory.current.path}/tool/materialize_rc_bundle.dart';
    return Process.run(Platform.resolvedExecutable, <String>[
      materializer,
      '--root',
      root.path,
      '--signing-key=unavailable',
      '--repository=example/project',
    ]);
  }

  Future<void> dispose() => root.delete(recursive: true);
}

Map<String, Object?> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Future<ProcessResult> _run(
  Directory root,
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed: ${result.stderr}',
    );
  }
  return result;
}
