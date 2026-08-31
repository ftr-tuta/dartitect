import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('classifies objective errors and advisory warnings', () async {
    final root = await _fixture();
    addTearDown(() => root.delete(recursive: true));

    final normal = await DartitectUiAuditor(root).audit();
    final strict = await DartitectUiAuditor(root).audit(strict: true);

    expect(normal.violations.map((finding) => finding.code), <String>[
      'DT3002',
      'DT3001',
    ]);
    expect(normal.findings.map((finding) => finding.code), <String>[
      'DT3103',
      'DT3101',
      'DT3104',
      'DT3105',
      'DT3106',
    ]);
    expect(normal.exitCode, 1);
    expect(strict.exitCode, 1);
    expect(
      normal.violations.followedBy(normal.findings),
      everyElement(
        isA<DartitectFinding>()
            .having((finding) => finding.path, 'path', 'lib/ui.dart')
            .having((finding) => finding.line, 'line', isNotNull),
      ),
    );
  });

  test('strict promotes warning-only audit to a failure', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-ui-warning-');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/ui.dart');
    await source.parent.create(recursive: true);
    await source.writeAsString('''
import 'package:flutter/widgets.dart';

Widget build(BuildContext context) => OrientationBuilder(
  builder: (context, orientation) => const SizedBox(),
);
''');

    expect((await DartitectUiAuditor(root).audit()).exitCode, 0);
    expect((await DartitectUiAuditor(root).audit(strict: true)).exitCode, 1);
  });

  test('reviewed config suppression applies to CLI UI findings', () async {
    final root = await _fixture();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/dartitect.json').writeAsString(
      DartitectConfig(
        suppressions: <DartitectSuppression>[
          DartitectSuppression(
            code: 'DT3001',
            path: 'lib/ui.dart',
            reason: 'Migration is tracked in the fixture.',
            owner: 'ui-platform',
            expiresAt: DateTime.utc(2099, 12, 31),
          ),
        ],
      ).encode(),
    );

    final result = await DartitectUiAuditor(root).audit();

    expect(result.violations.map((finding) => finding.code), <String>[
      'DT3002',
    ]);
  });

  test('CLI emits JSON and SARIF for UI audits', () async {
    final root = await _fixture();
    addTearDown(() => root.delete(recursive: true));
    final jsonOutput = StringBuffer();
    final sarifOutput = StringBuffer();

    expect(
      await DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: jsonOutput,
        stderrSink: StringBuffer(),
      ).run(<String>['ui', 'audit', '--json']),
      1,
    );
    expect(
      await DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: sarifOutput,
        stderrSink: StringBuffer(),
      ).run(<String>['ui', 'audit', '--sarif']),
      1,
    );

    final json = jsonDecode(jsonOutput.toString()) as Map<String, Object?>;
    final sarif = jsonDecode(sarifOutput.toString()) as Map<String, Object?>;
    expect(json['command'], 'ui-audit');
    expect(sarif['version'], '2.1.0');
    expect(jsonOutput.toString(), isNot(contains(root.path)));
  });
}

Future<Directory> _fixture() async {
  final root = await Directory.systemTemp.createTemp('dartitect-ui-audit-');
  final source = File('${root.path}/lib/ui.dart');
  await source.parent.create(recursive: true);
  await source.writeAsString('''
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget build(BuildContext context) {
  SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  MediaQuery.of(context);
  return Column(children: <Widget>[
    RawMaterialButton(onPressed: () {}),
    OrientationBuilder(builder: (context, orientation) => const SizedBox()),
    GestureDetector(onTap: () {}, child: const SizedBox()),
    Container(color: Colors.red),
    IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
  ]);
}
''');
  return root;
}
