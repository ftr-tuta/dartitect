import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/src/cli/dartitect_cli_runner.dart';
import 'package:dartitect_cli/src/inspect/flutter_quality.dart';
import 'package:test/test.dart';

void main() {
  test('applies fail, notEvidenced, warning, pass precedence', () {
    FlutterQualityTechnique technique(FlutterQualityStatus status) =>
        FlutterQualityTechnique(status: status, evidence: const <String>['x']);

    expect(
      FlutterQualityInspection.aggregateStatus(<FlutterQualityTechnique>[
        technique(FlutterQualityStatus.pass),
        technique(FlutterQualityStatus.warning),
        technique(FlutterQualityStatus.notEvidenced),
        technique(FlutterQualityStatus.fail),
      ]),
      FlutterQualityStatus.fail,
    );
    expect(
      FlutterQualityInspection.aggregateStatus(<FlutterQualityTechnique>[
        technique(FlutterQualityStatus.pass),
        technique(FlutterQualityStatus.warning),
        technique(FlutterQualityStatus.notEvidenced),
      ]),
      FlutterQualityStatus.notEvidenced,
    );
    expect(
      FlutterQualityInspection.aggregateStatus(<FlutterQualityTechnique>[
        technique(FlutterQualityStatus.pass),
        technique(FlutterQualityStatus.warning),
      ]),
      FlutterQualityStatus.warning,
    );
    expect(
      FlutterQualityInspection.aggregateStatus(<FlutterQualityTechnique>[
        technique(FlutterQualityStatus.notApplicable),
      ]),
      FlutterQualityStatus.notApplicable,
    );
  });

  test(
    'returns notApplicable only when no Flutter technique applies',
    () async {
      final root = await _root('pure_dart');
      await File('${root.path}/pubspec.yaml')
          .writeAsString('name: pure_dart\nenvironment:\n  sdk: ^3.13.0\n');

      final report = await FlutterQualityInspector(root).inspect();

      expect(report.overallStatus, FlutterQualityStatus.notApplicable);
      expect(report.exitCode, 0);
      expect(
        report.techniques.values.map((entry) => entry.status).toSet(),
        <FlutterQualityStatus>{FlutterQualityStatus.notApplicable},
      );
    },
  );

  test('reports all seven techniques and payload-free JSON', () async {
    final root = await _root('flutter_quality');
    await File('${root.path}/pubspec.yaml').writeAsString(
      'name: flutter_quality\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    final lib = Directory('${root.path}/lib/presentation');
    await lib.create(recursive: true);
    await File('${lib.path}/tasks_view.dart').writeAsString('''
import 'package:flutter/widgets.dart';
class TasksViewModel extends DartitectViewModel {}
abstract interface class TaskRepository {}
Widget view() => LayoutBuilder(builder: (_, __) => const SizedBox());
''');
    final testDirectory = Directory('${root.path}/test');
    await testDirectory.create();
    await File('${testDirectory.path}/tasks_test.dart').writeAsString(
      'void main() { testWidgets("tasks", (WidgetTester tester) async {}); }',
    );
    await File('${root.path}/lib/tasks_preview.dart').writeAsString(
      '@DartitectPreviewMatrix()\nWidget preview() => const SizedBox();\n',
    );
    for (final platform in <String>[
      'android',
      'ios',
      'linux',
      'macos',
      'windows',
      'web',
    ]) {
      await Directory('${root.path}/$platform').create();
    }
    final tool = Directory('${root.path}/tool');
    await tool.create();
    await File('${tool.path}/flutter_quality_runtime_evidence.json')
        .writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'flutterMcp': 'real',
            'uploadsScreenContent': false,
          }),
        );

    final report = await FlutterQualityInspector(root).inspect();
    final json = report.toJson();

    expect(report.techniques.keys, hasLength(7));
    expect(report.overallStatus, FlutterQualityStatus.pass);
    expect(report.exitCode, 0);
    expect(json['schemaVersion'], 1);
    expect(json['command'], 'inspect flutter-quality');
    expect(json['overallStatus'], 'pass');
    expect(json['exitCode'], 0);
    expect(jsonEncode(json), isNot(contains(root.path)));
  });

  test('fails when a preview reaches prohibited native I/O', () async {
    final root = await _root('unsafe_preview');
    await File('${root.path}/pubspec.yaml').writeAsString(
      'name: unsafe_preview\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    final lib = Directory('${root.path}/lib');
    await lib.create();
    await File('${lib.path}/preview.dart').writeAsString(
      "import 'dart:io';\n@Preview()\nObject preview() => File('x');\n",
    );

    final report = await FlutterQualityInspector(root).inspect();

    expect(report.overallStatus, FlutterQualityStatus.fail);
    expect(report.exitCode, 1);
    expect(
      report.techniques['reusableWidgetsPreviews']!.status,
      FlutterQualityStatus.fail,
    );
  });

  test('CLI emits the schema and reserves usage exit code 64', () async {
    final root = await _root('quality_cli');
    await File('${root.path}/pubspec.yaml')
        .writeAsString('name: quality_cli\nenvironment:\n  sdk: ^3.13.0\n');
    final output = StringBuffer();
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    );

    expect(
      await runner.run(<String>['inspect', 'flutter-quality', '--json']),
      0,
    );
    final json = jsonDecode(output.toString()) as Map<String, Object?>;
    expect(json['overallStatus'], 'notApplicable');
    expect(
      await runner.run(<String>['inspect', 'flutter-quality', '--unsupported']),
      64,
    );
    expect(errors.toString(), contains('Usage: dartitect inspect'));
  });
}

Future<Directory> _root(String name) async {
  final root = await Directory.systemTemp.createTemp('$name-');
  addTearDown(() => root.delete(recursive: true));
  return root;
}
