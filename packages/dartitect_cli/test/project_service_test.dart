import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'CLI inspect is the project service JSON without text parsing',
    () async {
      final root = await _project();
      final output = StringBuffer();
      final errors = StringBuffer();
      final exitCode = await DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: errors,
      ).run(<String>['inspect', '--json']);
      final service = await DartitectProjectService(root).inspectProject();

      expect(exitCode, service.exitCode);
      expect(jsonDecode(output.toString()), service.toJson());
      expect(errors.toString(), isEmpty);
    },
  );

  test('service rejects a stale baseline plan before commit', () async {
    final root = await _project(
      source: "import 'package:flutter/widgets.dart';\n",
      sourcePath: 'lib/features/example/domain/model.dart',
    );
    final service = DartitectProjectService(root);
    final plan = await service.previewChange(DartitectChangeKind.baseline);
    await File('${root.path}/lib/features/example/domain/model.dart')
        .writeAsString('BuildContext? context;\n');

    await expectLater(
      service.applyChange(plan),
      throwsA(
        isA<DartitectChangeException>().having(
          (error) => error.code,
          'code',
          'stale_plan',
        ),
      ),
    );
    expect(File('${root.path}/.dartitect/baseline.json').existsSync(), isFalse);
  });

  test(
    'baseline commit is idempotent and leaves no transaction artifacts',
    () async {
      final root = await _project();
      final service = DartitectProjectService(root);
      final first = await service.previewChange(DartitectChangeKind.baseline);
      final receipt = await service.applyChange(first);
      expect(receipt.changed, isTrue);
      final second = await service.previewChange(DartitectChangeKind.baseline);
      final noOp = await service.applyChange(second);
      expect(noOp.changed, isFalse);
      for (final path in <String>[
        'baseline.json.stage',
        'baseline.json.backup',
        'baseline.transaction.json',
      ]) {
        expect(File('${root.path}/.dartitect/$path').existsSync(), isFalse);
      }
    },
  );

  test('baseline commit recovers an interrupted backup before replacing', () async {
    final root = await _project(
      source: "import 'package:flutter/widgets.dart';\n",
      sourcePath: 'lib/features/example/domain/model.dart',
    );
    final directory = Directory('${root.path}/.dartitect');
    await directory.create();
    final original = DartitectBaseline(const <String>['old']).encode();
    await File('${directory.path}/baseline.json.backup')
        .writeAsString(original);
    await File('${directory.path}/baseline.json').writeAsString('partial');
    await File('${directory.path}/baseline.json.stage').writeAsString('stage');
    await File('${directory.path}/baseline.transaction.json').writeAsString(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'phase': 'backedUp'})}\n',
    );

    final service = DartitectProjectService(root);
    final plan = await service.previewChange(DartitectChangeKind.baseline);
    await service.applyChange(plan);

    final restored = await DartitectBaseline.load(
      File('${directory.path}/baseline.json'),
    );
    expect(restored.fingerprints, isNot(<String>{'old'}));
    for (final path in <String>[
      'baseline.json.stage',
      'baseline.json.backup',
      'baseline.transaction.json',
    ]) {
      expect(File('${directory.path}/$path').existsSync(), isFalse);
    }
  });

  test(
    'Codex sync recovery restores the pre-transaction managed skill',
    () async {
      final root = await _project();
      final synchronizer = CodexSkillSynchronizer(root);
      await synchronizer.sync();
      final skills = Directory('${root.path}/.agents/skills');
      final target = Directory('${skills.path}/dartitect-runtime');
      final oldSkill = File('${target.path}/SKILL.md');
      final oldContent = await oldSkill.readAsString();
      final backup = Directory('${root.path}/.dartitect-codex-backup');
      await backup.create();
      await target.rename('${backup.path}/dartitect-runtime');
      await target.create();
      await File('${target.path}/SKILL.md').writeAsString('partial\n');
      await File('${root.path}/.dartitect-codex-sync.json').writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'phase': 'staged',
          'skills': <String>['dartitect-runtime'],
        }),
      );

      await synchronizer.recover();

      expect(await File('${target.path}/SKILL.md').readAsString(), oldContent);
      expect(await backup.exists(), isFalse);
      expect(
        await File('${root.path}/.dartitect-codex-sync.json').exists(),
        isFalse,
      );
    },
  );
}

Future<Directory> _project({
  String source = 'void main() {}\n',
  String sourcePath = 'lib/main.dart',
}) async {
  final root = await Directory.systemTemp.createTemp('dartitect-service-test-');
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  await File('${root.path}/pubspec.yaml').writeAsString('''name: fixture
environment:
  sdk: ^3.13.0
''');
  final file = File('${root.path}/$sourcePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(source);
  return root;
}
