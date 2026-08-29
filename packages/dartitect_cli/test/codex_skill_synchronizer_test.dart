import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

const _managedSkills = <String>[
  'dartitect-adapters',
  'dartitect-audit',
  'dartitect-design',
  'dartitect-mcp',
  'dartitect-modeling',
  'dartitect-observability',
  'dartitect-offline-first',
  'dartitect-reactive',
  'dartitect-runtime',
  'dartitect-testing',
  'dartitect-tooling',
];

void main() {
  test('sync installs eleven valid skills and is idempotent', () async {
    final root = await _temporaryRoot();
    final localSkill = Directory(
      '${root.path}/.agents/skills/repository-contribution',
    );
    await localSkill.create(recursive: true);
    final localEntrypoint = File('${localSkill.path}/SKILL.md');
    await localEntrypoint.writeAsString('consumer-owned\n');

    final synchronizer = CodexSkillSynchronizer(root);
    final first = await synchronizer.sync();
    final second = await synchronizer.sync();

    expect(
      first.operations.where(
        (operation) => operation.startsWith('CREATE .agents/skills/'),
      ),
      hasLength(11),
    );
    expect(
      second.operations,
      unorderedEquals(
        _managedSkills.map((name) => 'NO-OP .agents/skills/$name'),
      ),
    );
    expect(await localEntrypoint.readAsString(), 'consumer-owned\n');
    expect(
      File('${localSkill.path}/.dartitect-skill.json').existsSync(),
      isFalse,
    );

    final installed = await Directory('${root.path}/.agents/skills')
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .map((entity) => _basename(entity.path))
        .toList();
    installed.sort();
    expect(
      installed,
      <String>[..._managedSkills, 'repository-contribution']..sort(),
    );

    for (final name in _managedSkills) {
      final directory = Directory('${root.path}/.agents/skills/$name');
      final entrypoint = await File('${directory.path}/SKILL.md')
          .readAsString();
      final metadata = await File('${directory.path}/agents/openai.yaml')
          .readAsString();
      final manifest = jsonDecode(
        await File('${directory.path}/.dartitect-skill.json').readAsString(),
      ) as Map<String, Object?>;

      expect(entrypoint, startsWith('---\nname: $name\ndescription: '));
      expect(entrypoint, contains('\n## When to use\n'));
      expect(entrypoint, contains('\n## When not to use\n'));
      expect(entrypoint, contains('\n## Invariants\n'));
      expect(entrypoint, contains('\n## Workflow\n'));
      expect(entrypoint, contains('\n## Validate\n'));
      expect(entrypoint, contains('\n## Dartitect inclusion gate\n'));
      expect(
        entrypoint,
        contains(
          'É business-neutral, difícil de implementar corretamente e gera '
          'infraestrutura repetitiva no consumidor?',
        ),
      );
      expect(metadata, contains('default_prompt: "Use \$$name '));
      expect(metadata, contains('allow_implicit_invocation: true'));
      expect(manifest['schemaVersion'], 1);
      expect(manifest['sdkVersion'], '1.0.0-rc.6');
      expect(manifest['contentHash'], matches(RegExp(r'^[0-9a-f]{8}$')));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('preview protects locally modified managed skills', () async {
    final root = await _temporaryRoot();
    final synchronizer = CodexSkillSynchronizer(root);
    await synchronizer.sync();
    final entrypoint = File(
      '${root.path}/.agents/skills/dartitect-runtime/SKILL.md',
    );
    await entrypoint.writeAsString(
      '${await entrypoint.readAsString()}\nlocal change\n',
    );

    await expectLater(
      synchronizer.preview(),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('--overwrite-managed'),
        ),
      ),
    );
    final overwrite = await synchronizer.preview(overwriteManaged: true);
    expect(
      overwrite.operations,
      contains('UPDATE .agents/skills/dartitect-runtime'),
    );
  });

  test('preview refuses an unmanaged collision', () async {
    final root = await _temporaryRoot();
    final collision = Directory('${root.path}/.agents/skills/dartitect-design');
    await collision.create(recursive: true);
    await File('${collision.path}/SKILL.md').writeAsString('local skill\n');

    await expectLater(
      CodexSkillSynchronizer(root).preview(),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('unmanaged skill'),
        ),
      ),
    );
    expect(
      await File('${collision.path}/SKILL.md').readAsString(),
      'local skill\n',
    );
  });
}

Future<Directory> _temporaryRoot() async {
  final root = await Directory.systemTemp.createTemp('dartitect-codex-test-');
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  return root;
}

String _basename(String path) => path
    .split(Platform.pathSeparator)
    .where((segment) => segment.isNotEmpty)
    .last;
