import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts canonical managed skills', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('rejects a reference that is no longer linked', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final skill = fixture.file('dartitect-adapters/SKILL.md');
    await skill.writeAsString(
      (await skill.readAsString()).replaceFirst(
        '- Sentry: [references/sentry.md](references/sentry.md)',
        '- Sentry details are provider-specific.',
      ),
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('references are not fully declared and linked'),
    );
  });

  test('rejects a stale managed-skill content hash', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final manifest = fixture.file('dartitect-design/.dartitect-skill.json');
    final value = jsonDecode(await manifest.readAsString());
    final object = value as Map<String, Object?>;
    object['contentHash'] = '00000000';
    await manifest.writeAsString('${jsonEncode(object)}\n');

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Stale managed-skill content hash'));
  });

  test('rejects a snapshot that diverges from the catalog', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final reference = fixture.file(
      'dartitect-design/references/selection-matrix.md',
    );
    await reference.writeAsString(
      '${await reference.readAsString()}Changed.\n',
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('snapshot diverges from canonical catalog'));
  });

  test('rejects inconsistent Codex metadata', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final metadata = fixture.file('dartitect-runtime/agents/openai.yaml');
    await metadata.writeAsString(
      (await metadata.readAsString()).replaceFirst(
        r'Use $dartitect-runtime',
        'Use the runtime skill',
      ),
    );

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Invalid Codex metadata'));
  });

  test('requires the consumer-owned repository contribution skill', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.file('repository-contribution/SKILL.md').delete();

    final result = await fixture.check();

    expect(result.exitCode, 1);
    expect(
      result.stderr,
      contains('Invalid consumer-owned repository-contribution skill'),
    );
  });
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  static Future<_Fixture> create() async {
    final source = Directory.current.absolute;
    final root = await Directory.systemTemp.createTemp('skill-coverage-');
    await Directory('${root.path}/tool').create(recursive: true);
    for (final name in const <String>[
      'skill_coverage.json',
      'package_release_contract.json',
    ]) {
      await File('${source.path}/tool/$name').copy('${root.path}/tool/$name');
    }
    await _copyDirectory(
      Directory('${source.path}/.agents/skills'),
      Directory('${root.path}/.agents/skills'),
    );
    return _Fixture(root);
  }

  File file(String relative) => File('${root.path}/.agents/skills/$relative');

  Future<ProcessResult> check() =>
      Process.run(Platform.resolvedExecutable, <String>[
        '${Directory.current.path}/tool/check_skill_coverage.dart',
        '--root',
        root.path,
        '--skills-only',
      ]);

  Future<void> dispose() => root.delete(recursive: true);
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = entity.path
        .split(Platform.pathSeparator)
        .where((part) => part.isNotEmpty)
        .last;
    if (entity is Directory) {
      await _copyDirectory(entity, Directory('${destination.path}/$name'));
    } else if (entity is File) {
      await entity.copy('${destination.path}/$name');
    }
  }
}
