import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('inspect JSON uses schema v1 and relative project paths', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-cli-json-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    final output = StringBuffer();
    final errors = StringBuffer();

    final exitCode = await DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    ).run(<String>['inspect', '--json']);
    final json = jsonDecode(output.toString()) as Map<String, Object?>;

    expect(exitCode, 0);
    expect(json['schemaVersion'], 1);
    expect(json['command'], 'inspect');
    expect((json['project'] as Map<String, Object?>)['root'], '.');
    expect(output.toString(), isNot(contains(root.path)));
    expect(errors.toString(), isEmpty);
  });

  test('init dry-run previews and init never overwrites', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-cli-init-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    );

    expect(await runner.run(<String>['init', '--dry-run']), 0);
    expect(await File('${root.path}/dartitect.json').exists(), isFalse);
    expect(await runner.run(<String>['init']), 0);
    final original = await File('${root.path}/dartitect.json').readAsString();
    expect(await runner.run(<String>['init']), 0);
    expect(await File('${root.path}/dartitect.json').readAsString(), original);
  });

  test('unknown command and flag return stable usage code', () async {
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      stdoutSink: StringBuffer(),
      stderrSink: errors,
    );

    expect(await runner.run(<String>['unknown']), 2);
    expect(await runner.run(<String>['scan', '--wat']), 2);
    expect(errors.toString(), contains('Unknown'));
  });

  test('doctor validates Android and iOS launch resources read-only', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-splash-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    await Directory('${root.path}/android').create();
    await Directory('${root.path}/ios').create();
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    );

    expect(await runner.run(<String>['doctor', '--json']), 1);
    expect(output.toString(), contains('DT1024'));
    expect(output.toString(), contains('DT1025'));
    expect(
      await File(
        '${root.path}/android/app/src/main/res/drawable/launch_background.xml',
      ).exists(),
      isFalse,
    );
  });

  test(
    'baseline hides existing violations but no-baseline reveals them',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-baseline-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
      await Directory('${root.path}/lib/domain').create(recursive: true);
      await File('${root.path}/lib/domain/a.dart')
          .writeAsString("import 'package:flutter/widgets.dart';\n");
      final output = StringBuffer();
      final runner = DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: StringBuffer(),
      );

      expect(await runner.run(<String>['baseline', 'create']), 0);
      expect(await runner.run(<String>['scan']), 0);
      expect(await runner.run(<String>['scan', '--no-baseline']), 1);
    },
  );

  test('codex sync is idempotent and preserves existing AGENTS.md', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-codex-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/AGENTS.md').writeAsString('consumer owned\n');
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    );

    expect(await runner.run(<String>['codex', 'sync']), 0);
    expect(await runner.run(<String>['codex', 'sync']), 0);
    expect(
      await File('${root.path}/AGENTS.md').readAsString(),
      'consumer owned\n',
    );
    expect(
      output.toString(),
      contains('NO-OP .agents/skills/dartitect-runtime'),
    );
    expect(
      RegExp(
        r'^NO-OP \.agents/skills/dartitect-',
        multiLine: true,
      ).allMatches(output.toString()),
      hasLength(11),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
