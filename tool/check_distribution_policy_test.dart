import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'check_distribution_policy.dart' as distribution_policy;

void main() {
  test('normalizes workflow basenames across platforms', () {
    expect(
      distribution_policy.portableBasename(
        r'D:\a\dartitect\.github\workflows\release.yaml',
      ),
      'release.yaml',
    );
    expect(
      distribution_policy.portableBasename('.github/workflows/release.yaml'),
      'release.yaml',
    );
  });

  test('accepts the complete GitHub-only fixture', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  for (final mutation in <String, Future<void> Function(_Fixture)>{
    'missing publish_to': (fixture) => fixture.replace(
      'packages/dartitect/pubspec.yaml',
      'publish_to: none\n',
      '',
    ),
    'divergent version': (fixture) => fixture.replace(
      'packages/dartitect/pubspec.yaml',
      'version: 1.1.0-rc.1',
      'version: 1.1.0-rc.2',
    ),
    'wrong Git URL': (fixture) => fixture.replace(
      'packages/dartitect_dio/pubspec.yaml',
      'url: https://github.com/ftr-tuta/dartitect.git',
      'url: https://example.invalid/dartitect.git',
    ),
    'wrong Git path': (fixture) => fixture.replace(
      'packages/dartitect_dio/pubspec.yaml',
      'path: packages/dartitect',
      'path: packages/dartitect_dio',
    ),
    'wrong tag pattern': (fixture) => fixture.replace(
      'packages/dartitect_dio/pubspec.yaml',
      "tag_pattern: 'v{{version}}'",
      "tag_pattern: 'release-{{version}}'",
    ),
    'hosted Dartitect dependency': (fixture) => fixture.replacePattern(
      'packages/dartitect_dio/pubspec.yaml',
      RegExp(
        r'  dartitect:\n    git:\n      url: [^\n]+\n      path: [^\n]+\n      tag_pattern: [^\n]+\n    version: 1\.1\.0-rc\.1',
      ),
      '  dartitect: 1.1.0-rc.1',
    ),
    'registry publication mechanism': (fixture) => fixture.append(
      '.github/workflows/release.yaml',
      '\n# dart pub publish\n',
    ),
    'write permission outside Release': (fixture) => fixture.replace(
      '.github/workflows/ci.yaml',
      'contents: read',
      'contents: write',
    ),
    'Repository Administration call in Release': (fixture) => fixture.append(
      '.github/workflows/release.yaml',
      '\n# /immutable-releases\n',
    ),
    'wrong public ruleset gate': (fixture) => fixture.replace(
      '.github/workflows/release.yaml',
      '/rulesets/21525640',
      '/rulesets/99999999',
    ),
    'missing post-publication immutability gate': (fixture) =>
        fixture.replaceAll(
          '.github/workflows/release.yaml',
          '.immutable == true',
          '.immutable == false',
        ),
    'missing prerelease refusal gate': (fixture) => fixture.replace(
      '.github/workflows/release.yaml',
      'Release refuses workspace cohort',
      'Release contract rejected',
    ),
    'generated Dartitect override': (fixture) => fixture.append(
      'tool/generated_project_matrix.dart',
      '\n// dependency_overrides:\n',
    ),
  }.entries) {
    test('rejects ${mutation.key}', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await mutation.value(fixture);

      final result = await fixture.check();

      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    });
  }
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  static Future<_Fixture> create() async {
    final source = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp('distribution-policy-');
    final policy = jsonDecode(
      File('${source.path}/tool/distribution_policy.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final paths = <String>{
      'tool/distribution_policy.json',
      'tool/package_release_contract.json',
      'tool/generated_project_matrix.dart',
      'pubspec.yaml',
      'tool/dartitect_devtools_extension/pubspec.yaml',
      'packages/dartitect_media/ios/dartitect_media.podspec',
      'packages/dartitect_privacy/ios/dartitect_privacy.podspec',
      for (final file in Directory(
        '${source.path}/packages',
      ).listSync(followLinks: false).whereType<Directory>())
        'packages/${_basename(file.path)}/pubspec.yaml',
      for (final file in Directory(
        '${source.path}/.github/workflows',
      ).listSync(followLinks: false).whereType<File>())
        '.github/workflows/${_basename(file.path)}',
      for (final path
          in (policy['activeDocuments']! as List<Object?>).cast<String>())
        path,
    };
    for (final path in paths) {
      final from = File('${source.path}/$path');
      final to = File('${root.path}/$path');
      await to.parent.create(recursive: true);
      await from.copy(to.path);
    }
    return _Fixture(root);
  }

  Future<ProcessResult> check() =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/check_distribution_policy.dart',
        '--root',
        root.path,
      ]);

  Future<void> replace(String path, String before, String after) async {
    final file = File('${root.path}/$path');
    final source = await file.readAsString();
    if (!source.contains(before)) throw StateError('$path lacks $before');
    await file.writeAsString(source.replaceFirst(before, after));
  }

  Future<void> replaceAll(String path, String before, String after) async {
    final file = File('${root.path}/$path');
    final source = await file.readAsString();
    if (!source.contains(before)) throw StateError('$path lacks $before');
    await file.writeAsString(source.replaceAll(before, after));
  }

  Future<void> replacePattern(String path, RegExp before, String after) async {
    final file = File('${root.path}/$path');
    final source = await file.readAsString();
    if (!before.hasMatch(source)) throw StateError('$path lacks $before');
    await file.writeAsString(source.replaceFirst(before, after));
  }

  Future<void> append(String path, String value) =>
      File('${root.path}/$path').writeAsString(value, mode: FileMode.append);

  Future<void> dispose() => root.delete(recursive: true);
}

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;
