import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('verify is strictly read-only and reports installed overlap', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-verify-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('''name: fixture
dependencies:
  provider: any
''');
    final source = File('${root.path}/lib/main.dart');
    await source.parent.create(recursive: true);
    await source.writeAsString('void main() {}\n');
    final before = await _snapshot(root);

    final report = await DartitectVerificationService(root).verify();

    expect(report.command, 'verify');
    expect(report.exitCode, 1);
    expect(report.findings.map((finding) => finding.code), contains('DT1019'));
    expect(
      report.project['providerStatus'],
      containsPair('status', 'overlap_warning'),
    );
    expect(await _snapshot(root), before);
  });

  test('verify CLI emits command-specific SARIF without writes', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-verify-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('''name: fixture
dependencies:
  provider: any
''');
    final before = await _snapshot(root);
    final output = StringBuffer();

    final exitCode = await DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    ).run(<String>['verify', '--sarif']);
    final sarif = jsonDecode(output.toString()) as Map<String, Object?>;
    final run =
        (sarif['runs']! as List<Object?>).single! as Map<String, Object?>;

    expect(exitCode, 1);
    expect(run['automationDetails'], containsPair('id', 'dartitect/verify'));
    expect(await _snapshot(root), before);
  });

  test(
    'verify reports stale opt-in models without creating ownership state',
    () async {
      final root = await _modelProject();
      addTearDown(() => root.delete(recursive: true));
      final before = await _snapshot(root);

      final report = await DartitectVerificationService(root).verify();

      expect(
        report.findings.map((finding) => finding.code),
        contains('DT1020'),
      );
      expect(report.project['modelStatus'], containsPair('status', 'findings'));
      expect(await _snapshot(root), before);
      expect(Directory('${root.path}/.dartitect').existsSync(), isFalse);
    },
  );
}

Future<Map<String, List<int>>> _snapshot(Directory root) async {
  final output = <String, List<int>>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(root.path.length + 1)
        .replaceAll('\\', '/');
    output[relative] = await entity.readAsBytes();
  }
  return output;
}

Future<Directory> _modelProject() async {
  final root = await Directory.systemTemp.createTemp('dartitect-verify-model-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''name: fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartitect_modeling: any
''');
  await File('${root.path}/lib/user.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'user.dartitect.g.dart';

@DartitectValue()
final class const User({required final String id})
    extends ValueEquality with _\$UserDartitect;
''');
  final dartitect = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  final modeling = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect_modeling/dartitect_modeling.dart'),
  );
  if (dartitect == null || modeling == null) {
    throw StateError('Modeling package graph is unresolved.');
  }
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'fixture',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect',
          'rootUri': dartitect.resolve('../').toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect_modeling',
          'rootUri': modeling.resolve('../').toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
  return root;
}
