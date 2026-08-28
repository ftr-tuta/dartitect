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
      expect(
        output,
        contains('// Dartitect model renderer 1, semantic schema 4.'),
      );
      expect(output, isNot(contains(DartitectGenerationVersions.release)));
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

  test('uses granular rules for mutable and malformed contracts', () async {
    final root = await _modelPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/bad.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'bad.dartitect.g.dart';

@DartitectValue()
final class Bad<T>({
  required final ImmutableValueList<List<T>> values,
}) extends ValueEquality with _\$BadDartitect;
''');

    final report = await DartitectModelGenerator(root).inspect();
    expect(report.plan, isNull);
    expect(report.diagnostics, isNotEmpty);
    expect(
      report.diagnostics.map((finding) => finding.code),
      everyElement(startsWith('DT10')),
    );
    expect(
      report.diagnostics.map((finding) => finding.message).join('\n'),
      contains('Mutable collection'),
    );
    expect(
      report.diagnostics.map((finding) => finding.code),
      contains('DT1037'),
    );
  });

  test(
    'generics records defaults parts and multiple models share one output',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/lib/models.dart').writeAsString('''
library;

import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'more_models.dart';
part 'models.dartitect.g.dart';

@DartitectValue()
@DartitectProjection(name: 'value_only', fields: <String>['value'])
final class const Box<T extends Object>({
  required final T value,
  final (int, {String label}) metadata = (0, label: ''),
}) extends ValueEquality with _\$BoxDartitect<T>;
''');
      await File('${root.path}/lib/more_models.dart').writeAsString('''
part of 'models.dart';

@DartitectValue()
final class const Pair({
  required final String left,
  final String right = 'default',
}) extends ValueEquality with _\$PairDartitect;
''');

      final generator = DartitectModelGenerator(root);
      final preview = await generator.inspect();
      expect(
        preview.diagnostics,
        isEmpty,
        reason:
            '${preview.diagnostics.map((value) => value.toJson()).toList()}',
      );
      expect(
        preview.operations.map((operation) => operation.relativePath),
        <String>['lib/models.dartitect.g.dart'],
      );
      final output = preview.operations.single.content;
      expect(output, contains('mixin _\$BoxDartitect<T extends Object>'));
      expect(output, contains('(int, {String label}) get metadata'));
      expect(output, contains('mixin _\$PairDartitect'));
      expect(
        output,
        contains('typedef BoxValueOnlyDartitectProjection<T extends Object>'),
      );

      await generator.apply();
      final analyzed = await Process.run(Platform.resolvedExecutable, <String>[
        'analyze',
      ], workingDirectory: root.path);
      expect(
        analyzed.exitCode,
        0,
        reason: '${analyzed.stdout}\n${analyzed.stderr}',
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

  test('generated JSON codec round-trips and rejects unknown keys', () async {
    final root = await _modelPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/user.dart').writeAsString(
      _userSource.replaceFirst(
        '@DartitectValue()',
        '@DartitectValue()\n@DartitectJson()',
      ),
    );
    final generator = DartitectModelGenerator(root);

    await generator.apply();
    final output = await File('${root.path}/lib/user.dartitect.g.dart')
        .readAsString();

    expect(output, contains('final class UserDartitectJsonCodec'));
    expect(output, contains('const userDartitectJsonCodec'));
    expect(output, contains('rejectUnknownKeys: true'));
    await _runGeneratedJsonContract(root);
  });

  test(
    'generated JSON composes generics collections hooks and defaults',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/lib/payload.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'payload.dartitect.g.dart';

@DartitectJson(trusted: true)
final class const Payload<T>({
  required final T value,
  required final ImmutableValueList<int> numbers,
  @DartitectField(
    jsonName: 'created_at',
    decodeWith: 'PayloadHooks.decodeDate',
    encodeWith: 'PayloadHooks.encodeDate',
  )
  required final DateTime createdAt,
  final String label = 'default',
});

abstract final class PayloadHooks {
  static Result<DateTime, DartitectJsonFailure> decodeDate(
    Object? input,
    DartitectJsonPath path,
  ) {
    final parsed = input is String ? DateTime.tryParse(input) : null;
    return parsed == null
        ? DartitectJsonFailure.result<DateTime>(
            DartitectJsonFailureKind.customCodec,
            path,
          )
        : Ok<DateTime>(parsed);
  }

  static Result<Object?, DartitectJsonFailure> encodeDate(
    DateTime value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value.toIso8601String());
}
''');
      final generator = DartitectModelGenerator(root);

      await generator.apply();
      final output = await File('${root.path}/lib/payload.dartitect.g.dart')
          .readAsString();

      expect(output, contains('required this.codecT'));
      expect(output, contains('DartitectJsonLimits.trusted'));
      expect(output, contains('DartitectJsonCodecs.immutableList'));
      expect(output, contains('PayloadHooks.decodeDate'));
      expect(output, isNot(contains('payloadDartitectJsonCodec =')));
      await _runGeneratedGenericJsonContract(root);
    },
  );

  test(
    'generated projections lenses and mappers execute typed contracts',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/lib/profile.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'profile.dartitect.g.dart';

final class ProfileDto {
  const ProfileDto({
    required this.id,
    required this.displayName,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String createdAt;
}

final class AuditDto {
  const AuditDto({required this.id, this.note = 'default'});

  final String id;
  final String note;
}

@DartitectMapper(AuditDto)
final class const Audit({required final String id});

@DartitectValue()
@DartitectProjection(name: 'summary', fields: <String>['id', 'label'])
@DartitectMapper(ProfileDto, bidirectional: true)
final class const Profile({
  required final String id,
  @DartitectField(targetName: 'displayName') required final String label,
  @DartitectField(
    mapToWith: 'ProfileHooks.dateToString',
    mapFromWith: 'ProfileHooks.stringToDate',
  )
  required final DateTime createdAt,
}) extends ValueEquality with _$ProfileDartitect;

abstract final class ProfileHooks {
  static Result<String, DartitectMappingFailure> dateToString(
    DateTime value,
    DartitectMappingPath path,
  ) => Ok<String>(value.toIso8601String());

  static Result<DateTime, DartitectMappingFailure> stringToDate(
    String value,
    DartitectMappingPath path,
  ) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? DartitectMappingFailure.result<DateTime>(
            DartitectMappingFailureKind.converterRejected,
            path,
          )
        : Ok<DateTime>(parsed);
  }
}
''');
      final generator = DartitectModelGenerator(root);

      await generator.apply();
      final output = await File('${root.path}/lib/profile.dartitect.g.dart')
          .readAsString();

      expect(output, contains('final class ProfileDartitectFields'));
      expect(output, contains('typedef ProfileSummaryDartitectProjection'));
      expect(
        output,
        contains('final class ProfileToProfileDtoDartitectMapper'),
      );
      expect(output, contains('final class AuditToAuditDtoDartitectMapper'));
      expect(output, contains('ProfileHooks.dateToString'));
      await _runGeneratedProjectionMappingContract(root);
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

Future<void> _runGeneratedJsonContract(Directory root) async {
  await Directory('${root.path}/bin').create();
  await File('${root.path}/bin/json_contract.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:model_fixture/user.dart';

void expectContract(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final decoded = userDartitectJsonCodec.decode(<String, Object?>{
    'id': 'one',
    'email': null,
  });
  switch (decoded) {
    case Ok<dynamic>(:final value):
      expectContract(value == const User(id: 'one', email: null), 'decode');
    case Err<Object>(:final failure):
      throw StateError('unexpected decode failure: $failure');
  }
  final encoded = userDartitectJsonCodec.encode(
    const User(id: 'two', email: 'two@example.test'),
  );
  switch (encoded) {
    case Ok<dynamic>(:final value):
      expectContract(
        ValueEquality.equals(value, <String, Object?>{
          'id': 'two',
          'email': 'two@example.test',
        }),
        'encode',
      );
    case Err<Object>(:final failure):
      throw StateError('unexpected encode failure: $failure');
  }
  final unknown = userDartitectJsonCodec.decode(<String, Object?>{
    'id': 'one',
    'email': null,
    'extra': true,
  });
  switch (unknown) {
    case Ok<dynamic>():
      throw StateError('unknown key was accepted');
    case Err<Object>(:final failure):
      expectContract(
        (failure as DartitectJsonFailure).kind ==
            DartitectJsonFailureKind.unknownKey,
        'unknown-key kind',
      );
  }
}

''');
  for (final arguments in <List<String>>[
    <String>['analyze'],
    <String>['run', 'bin/json_contract.dart'],
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

Future<void> _runGeneratedGenericJsonContract(Directory root) async {
  await Directory('${root.path}/bin').create();
  await File('${root.path}/bin/generic_json_contract.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:model_fixture/payload.dart';

void expectContract(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  const codec = PayloadDartitectJsonCodec<String>(
    codecT: DartitectStringJsonCodec(),
  );
  expectContract(codec.defaultLimits.trusted, 'trusted default');
  final decoded = codec.decode(<String, Object?>{
    'value': 'generic',
    'numbers': List<Object?>.filled(10001, 1),
    'created_at': '2026-08-27T00:00:00.000Z',
  });
  switch (decoded) {
    case Ok<dynamic>(:final value):
      final payload = value as Payload<String>;
      expectContract(payload.value == 'generic', 'generic codec');
      expectContract(payload.numbers.length == 10001, 'trusted collection');
      expectContract(payload.label == 'default', 'omitted default');
    case Err<Object>(:final failure):
      throw StateError('unexpected failure: $failure');
  }
  final unknown = codec.decode(<String, Object?>{
    'value': 'generic',
    'numbers': <Object?>[],
    'created_at': '2026-08-27T00:00:00.000Z',
    'extra': true,
  });
  expectContract(unknown is Err<DartitectJsonFailure>, 'unknown key');
}
''');
  for (final arguments in <List<String>>[
    <String>['analyze'],
    <String>['run', 'bin/generic_json_contract.dart'],
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

Future<void> _runGeneratedProjectionMappingContract(Directory root) async {
  await Directory('${root.path}/bin').create();
  await File('${root.path}/bin/projection_mapping_contract.dart')
      .writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:model_fixture/profile.dart';

void expectContract(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final instant = DateTime.utc(2026, 8, 27);
  final profile = Profile(id: 'one', label: 'Ada', createdAt: instant);
  final summary = selectProfileSummary(profile);
  expectContract(summary.id == 'one' && summary.label == 'Ada', 'projection');

  final updated = profileDartitectFields.label.write(profile, 'Grace');
  expectContract(updated.label == 'Grace', 'lens writes replacement');
  expectContract(profile.label == 'Ada', 'lens preserves source');
  expectContract(
    profileDartitectFields.id.descriptor.name == 'id',
    'descriptor name',
  );

  final mapped = profileToProfileDtoDartitectMapper.toTarget(profile);
  switch (mapped) {
    case Ok<dynamic>(:final value):
      final target = value as ProfileDto;
      expectContract(target.id == 'one', 'automatic mapping');
      expectContract(target.displayName == 'Ada', 'explicit rename');
      expectContract(target.createdAt == instant.toIso8601String(), 'hook');
    case Err<Object>(:final failure):
      throw StateError('unexpected forward failure: $failure');
  }

  final oneWay = auditToAuditDtoDartitectMapper.toTarget(
    const Audit(id: 'audit'),
  );
  switch (oneWay) {
    case Ok<dynamic>(:final value):
      final audit = value as AuditDto;
      expectContract(audit.id == 'audit', 'one-way mapping');
      expectContract(audit.note == 'default', 'target optional default');
    case Err<Object>(:final failure):
      throw StateError('unexpected one-way failure: $failure');
  }

  final reversed = profileToProfileDtoDartitectMapper.fromTarget(
    const ProfileDto(id: 'two', displayName: 'Lin', createdAt: 'invalid'),
  );
  switch (reversed) {
    case Ok<dynamic>():
      throw StateError('invalid converter input was accepted');
    case Err<Object>(:final failure):
      final mappingFailure = failure as DartitectMappingFailure;
      expectContract(
        mappingFailure.kind == DartitectMappingFailureKind.converterRejected,
        'failure kind',
      );
      expectContract(
        mappingFailure.path.sourceField == 'createdAt' &&
            mappingFailure.path.targetField == 'createdAt',
        'failure path',
      );
  }
}
''');
  for (final arguments in <List<String>>[
    <String>['analyze'],
    <String>['run', 'bin/projection_mapping_contract.dart'],
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
