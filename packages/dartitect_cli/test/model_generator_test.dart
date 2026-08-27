import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bootstrap, typed copyWith, equality, update and orphan convergence',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/lib/user.dart');
      await source.writeAsString(_userSource);
      final generator = DartitectModelGenerator(root);

      final preview = await generator.inspect();
      expect(
        preview.findings.map((finding) => finding.code),
        contains('DT1020'),
        reason: preview.diagnostics
            .map(
              (finding) => '${finding.path}:${finding.line} ${finding.message}',
            )
            .join('\n'),
      );
      expect(
        await File('${root.path}/lib/user.dartitect.g.dart').exists(),
        isFalse,
      );

      final applied = await generator.apply();
      expect(applied.createdPaths, <String>['lib/user.dartitect.g.dart']);
      final output = await File('${root.path}/lib/user.dartitect.g.dart')
          .readAsString();
      expect(output, contains('String? email,'));
      expect(output, contains('bool clearEmail = false'));
      expect(output, isNot(contains('operator ==')));
      expect(output, isNot(contains('hashCode')));
      expect((await generator.inspect()).isFresh, isTrue);
      await _runGeneratedConsumerContract(root);

      await source.writeAsString(
        _userSource.replaceFirst(
          'required final String? email,',
          'required final int? email,',
        ),
      );
      final updated = await generator.apply();
      expect(updated.updatedPaths, <String>['lib/user.dartitect.g.dart']);
      expect(
        await File('${root.path}/lib/user.dartitect.g.dart').readAsString(),
        contains('int? get email'),
      );

      await source.writeAsString('// no model remains\n');
      final deleted = await generator.apply();
      expect(deleted.deletedPaths, <String>['lib/user.dartitect.g.dart']);
    },
  );

  test(
    'rejects generic, mutable collections, and malformed contracts',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/lib/bad.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'bad.dartitect.g.dart';

@DartitectValue()
final class Bad<T>({
  required final List<T> values,
}) extends ValueEquality with _\$BadDartitect;
''');

      final report = await DartitectModelGenerator(root).inspect();
      expect(report.plan, isNull);
      expect(report.diagnostics, isNotEmpty);
      expect(
        report.diagnostics.map((finding) => finding.code),
        everyElement('DT1021'),
      );
      expect(
        report.diagnostics.map((finding) => finding.message).join('\n'),
        contains('Generic'),
      );
      expect(
        report.diagnostics.map((finding) => finding.message).join('\n'),
        contains('Mutable collection'),
      );
    },
  );

  test(
    'rejects abstract final models and mutable collection aliases',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/lib/bad.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'bad.dartitect.g.dart';

typedef MutableValues = List<int>;

@DartitectValue()
abstract final class Bad({
  required final MutableValues values,
}) extends ValueEquality with _\$BadDartitect;
''');

      final report = await DartitectModelGenerator(root).inspect();
      expect(report.plan, isNull);
      final messages = report.diagnostics
          .map((finding) => finding.message)
          .join('\n');
      expect(messages, contains('concrete'));
      expect(messages, contains('Mutable collection'));
    },
  );

  test('resolves annotation identity through prefix and reexport', () async {
    final root = await _modelPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/annotations.dart').writeAsString('''
export 'package:dartitect_modeling/dartitect_modeling.dart'
    show DartitectValue, ValueEquality;
''');
    await File('${root.path}/lib/prefixed.dart').writeAsString(
      _userSource
          .replaceAll(
            "import 'package:dartitect_modeling/dartitect_modeling.dart';",
            "import 'package:dartitect_modeling/dartitect_modeling.dart' as d;",
          )
          .replaceAll('@DartitectValue()', '@d.DartitectValue()')
          .replaceAll('extends ValueEquality', 'extends d.ValueEquality')
          .replaceAll('user.dartitect.g.dart', 'prefixed.dartitect.g.dart')
          .replaceAll('class const User', 'class const Prefixed')
          .replaceAll('_\$UserDartitect', '_\$PrefixedDartitect')
          .replaceAll('const User', 'const Prefixed'),
    );
    await File('${root.path}/lib/reexported.dart').writeAsString(
      _userSource
          .replaceAll(
            "import 'package:dartitect_modeling/dartitect_modeling.dart';",
            "import 'package:model_fixture/annotations.dart';",
          )
          .replaceAll('user.dartitect.g.dart', 'reexported.dartitect.g.dart')
          .replaceAll('class const User', 'class const Reexported')
          .replaceAll('_\$UserDartitect', '_\$ReexportedDartitect')
          .replaceAll('const User', 'const Reexported'),
    );

    final report = await DartitectModelGenerator(root).inspect();
    expect(report.diagnostics, isEmpty, reason: '${report.diagnostics}');
    expect(
      report.operations.map((operation) => operation.relativePath),
      <String>[
        'lib/prefixed.dartitect.g.dart',
        'lib/reexported.dartitect.g.dart',
      ],
    );
  });

  test('rejects a homonymous annotation from a different element', () async {
    final root = await _modelPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/fake.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart' show ValueEquality;
part 'fake.dartitect.g.dart';

final class DartitectValue {
  const DartitectValue();
}

@DartitectValue()
final class const Fake({
  required final String id,
}) extends ValueEquality with _\$FakeDartitect;
''');

    final report = await DartitectModelGenerator(root).inspect();
    expect(report.plan, isNull);
    expect(report.operations, isEmpty);
    expect(
      report.diagnostics.single.message,
      contains('package:dartitect_modeling'),
    );
  });

  test(
    'generates a library with unrelated parts without scanning parts twice',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/lib/library_model.dart').writeAsString('''
library;

import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'support.dart';
part 'library_model.dartitect.g.dart';

@DartitectValue()
final class const LibraryModel({
  required final String id,
}) extends ValueEquality with _\$LibraryModelDartitect;
''');
      await File('${root.path}/lib/support.dart').writeAsString('''
part of 'library_model.dart';

const supportValue = 1;
''');

      final generator = DartitectModelGenerator(root);
      final report = await generator.inspect();
      expect(report.diagnostics, isEmpty, reason: '${report.diagnostics}');
      expect(
        report.operations.map((operation) => operation.relativePath),
        <String>['lib/library_model.dartitect.g.dart'],
      );
      await generator.apply();
      expect((await generator.inspect()).isFresh, isTrue);
    },
  );

  test(
    'annotated parts and malformed libraries fail closed without writes',
    () async {
      final partRoot = await _modelPackage();
      addTearDown(() => partRoot.delete(recursive: true));
      await File('${partRoot.path}/lib/container.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'part_model.dart';
''');
      await File('${partRoot.path}/lib/part_model.dart').writeAsString('''
part of 'container.dart';

@DartitectValue()
final class const PartModel({
  required final String id,
}) extends ValueEquality with _\$PartModelDartitect;
''');
      final partReport = await DartitectModelGenerator(partRoot).inspect();
      expect(partReport.plan, isNull);
      expect(
        partReport.diagnostics
            .map((diagnostic) => diagnostic.message)
            .join('\n'),
        contains('must declare exactly'),
      );
      expect(
        await File('${partRoot.path}/lib/part_model.dartitect.g.dart').exists(),
        isFalse,
      );

      final malformedRoot = await _modelPackage();
      addTearDown(() => malformedRoot.delete(recursive: true));
      await File('${malformedRoot.path}/lib/malformed.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'malformed.dartitect.g.dart';

@DartitectValue()
final class Malformed extends ValueEquality with _\$MalformedDartitect {
  const Malformed({required this.id})
  final String id;
}
''');
      final malformed = DartitectModelGenerator(malformedRoot);
      final malformedReport = await malformed.inspect();
      expect(malformedReport.plan, isNull);
      expect(malformedReport.diagnostics, isNotEmpty);
      await expectLater(
        malformed.apply(),
        throwsA(isA<ModelGenerationException>()),
      );
      expect(
        await File('${malformedRoot.path}/lib/malformed.dartitect.g.dart')
            .exists(),
        isFalse,
      );
    },
  );

  test('CLI sync previews by default and check remains read-only', () async {
    final root = await _modelPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/user.dart').writeAsString(_userSource);
    final output = StringBuffer();
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    );

    expect(await runner.run(<String>['model', 'sync']), 1);
    expect(
      await File('${root.path}/lib/user.dartitect.g.dart').exists(),
      isFalse,
    );
    expect(await runner.run(<String>['model', 'sync', '--apply']), 0);
    expect(await runner.run(<String>['model', 'check', '--json']), 0);
    expect(
      await runner.run(<String>['model', 'sync', '--dry-run', '--apply']),
      2,
    );
    expect(errors.toString(), contains('mutually exclusive'));
  });
}

const _userSource = '''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'user.dartitect.g.dart';

@DartitectValue()
final class const User({
  required final String id,
  required final String? email,
}) extends ValueEquality with _\$UserDartitect;
''';

Future<Directory> _modelPackage() async {
  final root = await Directory.systemTemp.createTemp('dartitect-model-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: model_fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartitect_modeling: any
''');
  final dartitect = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  if (dartitect == null) throw StateError('dartitect package is unresolved');
  final dartitectRoot = dartitect.resolve('../');
  final modeling = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect_modeling/dartitect_modeling.dart'),
  );
  if (modeling == null) {
    throw StateError('dartitect_modeling package is unresolved');
  }
  final modelingRoot = modeling.resolve('../');
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'model_fixture',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect',
          'rootUri': dartitectRoot.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect_modeling',
          'rootUri': modelingRoot.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
  return root;
}

Future<void> _runGeneratedConsumerContract(Directory root) async {
  await Directory('${root.path}/bin').create();
  await File('${root.path}/bin/model_contract.dart').writeAsString('''
import 'package:model_fixture/user.dart';

void expectContract(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  const original = User(id: 'one', email: 'old@example.test');
  final omitted = original.copyWith();
  final explicitNull = original.copyWith(email: null);
  final replaced = original.copyWith(id: 'two', email: 'new@example.test');
  final cleared = original.copyWith(clearEmail: true);

  expectContract(omitted == original, 'omission must preserve fields');
  expectContract(explicitNull == original, 'null must preserve nullable field');
  expectContract(replaced.id == 'two', 'non-null id must replace');
  expectContract(
    replaced.email == 'new@example.test',
    'non-null email must replace',
  );
  expectContract(cleared.email == null, 'clear flag must clear nullable field');
  expectContract(
    omitted.hashCode == original.hashCode,
    'equal values must have equal hashes',
  );

  var rejectedConflict = false;
  try {
    original.copyWith(email: 'new@example.test', clearEmail: true);
  } on ArgumentError {
    rejectedConflict = true;
  }
  expectContract(rejectedConflict, 'value plus clear must be rejected');
}
''');

  for (final arguments in <List<String>>[
    <String>['analyze'],
    <String>['run', 'bin/model_contract.dart'],
  ]) {
    final result = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: root.path,
    );
    expect(
      result.exitCode,
      0,
      reason:
          'dart ${arguments.join(' ')} failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  }
}
