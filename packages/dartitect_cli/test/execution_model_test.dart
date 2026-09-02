import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('inspector covers DT2200 through DT2211 deterministically', () async {
    final root = await Directory.systemTemp.createTemp('execution-model-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: sample\n');
    await _write(root, 'lib/hot_path.dart', r'''
final List<int> _history = <int>[];
final listeners = <void Function()>[];
final dependencies = <int>[];
final values = <int>[];

Stream<int> producer() async* {
  await Future<void>.delayed(Duration.zero);
  yield 1;
}

Future<void> work(Stream<int> stream) async {
  values.toList();
  values.removeAt(0);
  final snapshot = List<void Function()>.of(listeners);
  if (listeners.contains(snapshot.first)) {}
  values.sort();
  dependencies.any((value) => value > 0);
  await Future.wait(values.map(Future.value));
  stream.listen((value) async { await Future<void>.value(); });
  StreamController<int>(sync: true);
  node.toSource();
  other.toSource();
  for (final value in values) {
    if (values.contains(value)) break;
  }
}
''');

    final first = await ExecutionModelInspector(root).inspect();
    final second = await ExecutionModelInspector(root).inspect();

    expect(first.findings.map((finding) => finding.code).toSet(), <String>{
      for (var code = 2200; code <= 2211; code += 1) 'DT$code',
    });
    expect(
      first.findings.map((finding) => finding.toJson()).toList(),
      second.findings.map((finding) => finding.toJson()).toList(),
    );
    expect(
      first.findings.where(
        (finding) => finding.severity == FindingSeverity.warning,
      ),
      isNotEmpty,
    );
  });

  test('inspector avoids the curated negative corpus', () async {
    final root = await Directory.systemTemp.createTemp('execution-negative-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: sample\n');
    await _write(root, 'lib/safe.dart', '''
import 'dart:collection';

final queue = ListQueue<int>();
Iterable<int> values() sync* {
  yield 1;
}
''');

    final report = await ExecutionModelInspector(root).inspect();

    expect(report.findings, isEmpty);
  });

  test(
    'CLI inspector is non-blocking and findings keep exit code zero',
    () async {
      final root = await Directory.systemTemp.createTemp('execution-cli-');
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', 'name: sample\n');
      await _write(
        root,
        'lib/queue.dart',
        'void f(List<int> v) => v.removeAt(0);\n',
      );
      final output = StringBuffer();

      final exitCode = await DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: StringBuffer(),
      ).run(<String>['inspect', 'execution-model', '--json']);
      final json = jsonDecode(output.toString()) as Map<String, Object?>;

      expect(exitCode, 0);
      expect(json['command'], 'inspect execution-model');
      expect(json['exitCode'], 0);
      expect(output.toString(), contains('DT2201'));
    },
  );
}

Future<void> _write(Directory root, String path, String content) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
