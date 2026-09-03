import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/src/codex/codex_skill_synchronizer.dart'
    show setupFlutterCodexSkills;
import 'package:dartitect_cli/src/codex/skill_catalog.dart';
import 'package:test/test.dart';

final _managedSkills = dartitectSkillCatalog.map((skill) => skill.name).toList()
  ..sort();

void main() {
  test('sync installs every catalog skill and is idempotent', () async {
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
      hasLength(_managedSkills.length),
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
    expect(installed, hasLength(dartitectSkillCatalog.length + 1));

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
        allOf(
          contains('Is it business-neutral, difficult to implement correctly'),
          contains('repetitive infrastructure in consumer applications?'),
        ),
      );
      expect(metadata, contains('default_prompt: "Use \$$name '));
      expect(metadata, contains('allow_implicit_invocation: true'));
      expect(manifest['schemaVersion'], 1);
      expect(manifest['sdkVersion'], '1.1.0');
      expect(manifest['contentHash'], matches(RegExp(r'^[0-9a-f]{8}$')));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('preview updates a managed manifest from an older SDK cohort', () async {
    final root = await _temporaryRoot();
    final synchronizer = CodexSkillSynchronizer(root);
    await synchronizer.sync();
    final manifest = File(
      '${root.path}/.agents/skills/dartitect-design/.dartitect-skill.json',
    );
    final decoded =
        jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    decoded['sdkVersion'] = '1.1.0-rc.2';
    await manifest.writeAsString(jsonEncode(decoded));

    final preview = await synchronizer.preview();

    expect(
      preview.operations,
      contains('UPDATE .agents/skills/dartitect-design'),
    );
  });

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

  test(
    'Flutter setup manages only catalog assets and yields 16 NO-OPs',
    () async {
      final root = await _temporaryRoot();
      final synchronizer = CodexSkillSynchronizer(root);

      final applied = await setupFlutterCodexSkills(
        synchronizer,
        dryRun: false,
      );
      final preview = await setupFlutterCodexSkills(synchronizer, dryRun: true);

      expect(applied.dryRun, isFalse);
      expect(await File('${root.path}/AGENTS.md').exists(), isFalse);
      expect(preview.operations, hasLength(16));
      expect(
        preview.operations.every((operation) => operation.startsWith('NO-OP ')),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('Flutter setup dry-run plans recovery without writing', () async {
    final root = await _temporaryRoot();
    final synchronizer = CodexSkillSynchronizer(root);
    await setupFlutterCodexSkills(synchronizer, dryRun: false);
    final skills = Directory('${root.path}/.agents/skills');
    final target = Directory('${skills.path}/dartitect-runtime');
    final expected = await File('${target.path}/SKILL.md').readAsString();
    final backup = Directory('${root.path}/.dartitect-codex-backup');
    await backup.create();
    await target.rename('${backup.path}/dartitect-runtime');
    await target.create();
    await File('${target.path}/SKILL.md').writeAsString('partial\n');
    final journal = File('${root.path}/.dartitect-codex-sync.json');
    await journal.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'phase': 'staged',
        'skills': <String>['dartitect-runtime'],
      }),
    );

    final preview = await setupFlutterCodexSkills(synchronizer, dryRun: true);

    expect(preview.operations.first, startsWith('RECOVER '));
    expect(await File('${target.path}/SKILL.md').readAsString(), 'partial\n');
    expect(await journal.exists(), isTrue);
    await setupFlutterCodexSkills(synchronizer, dryRun: false);
    expect(await File('${target.path}/SKILL.md').readAsString(), expected);
    expect(await journal.exists(), isFalse);
    expect(await backup.exists(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'irrecoverable Flutter setup fails before touching managed assets',
    () async {
      final root = await _temporaryRoot();
      final synchronizer = CodexSkillSynchronizer(root);
      await setupFlutterCodexSkills(synchronizer, dryRun: false);
      final skill = File(
        '${root.path}/.agents/skills/dartitect-runtime/SKILL.md',
      );
      final expected = await skill.readAsString();
      await File('${root.path}/.dartitect-codex-sync.json')
          .writeAsString('{invalid');

      await expectLater(
        setupFlutterCodexSkills(synchronizer, dryRun: false),
        throwsA(isA<FileSystemException>()),
      );

      expect(await skill.readAsString(), expected);
      expect(
        await File('${root.path}/.dartitect-codex-sync.json').readAsString(),
        '{invalid',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
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
