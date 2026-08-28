import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart';
import 'package:test/test.dart';

void main() {
  test(
    'compiler retains semantic types capabilities defaults and parts',
    () async {
      final root = await _modelPackage();
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/lib/models.dart').writeAsString(r'''
library;

import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'detail.dart';
part 'models.dartitect.g.dart';

@DartitectValue()
@DartitectJson()
@DartitectProjection(name: 'summary')
final class const Envelope<T extends Object>({
  @DartitectField(jsonName: 'record_id') required final T id,
  @DartitectField(
    decodeWith: 'decodeMetadata',
    encodeWith: 'encodeMetadata',
  )
  final (int, {String label}) metadata = (0, label: ''),
}) extends ValueEquality with _$EnvelopeDartitect<T>;

Result<(int, {String label}), DartitectJsonFailure> decodeMetadata(
  Object? input,
  DartitectJsonPath path,
) => const Ok<(int, {String label})>((0, label: ''));

Result<Object?, DartitectJsonFailure> encodeMetadata(
  (int, {String label}) value,
  DartitectJsonPath path,
) => Ok<Object?>(<String, Object?>{
  'index': value.$1,
  'label': value.label,
});
''');
      await File('${root.path}/lib/detail.dart').writeAsString(r'''
part of 'models.dart';

@DartitectValue()
final class const Detail({
  required final String value,
}) extends ValueEquality with _$DetailDartitect;
''');

      final result = await ModelingCompiler(root).compile();

      expect(
        result.diagnostics,
        isEmpty,
        reason: '${result.diagnostics.map((value) => value.toJson()).toList()}',
      );
      final library = result.workspace.libraries.single;
      expect(library.path, 'lib/models.dart');
      expect(library.outputPath, 'lib/models.dartitect.g.dart');
      expect(library.models.map((model) => model.name), <String>[
        'Detail',
        'Envelope',
      ]);
      final envelope = library.models.singleWhere(
        (model) => model.name == 'Envelope',
      );
      expect(envelope.typeParameters.single.name, 'T');
      expect(envelope.typeParameters.single.bound?.libraryUri, 'dart:core');
      expect(envelope.capabilities, <ModelingCapability>{
        ModelingCapability.value,
        ModelingCapability.json,
        ModelingCapability.projection,
      });
      expect(envelope.json?.rejectUnknownKeys, isTrue);
      expect(envelope.projections.single.name, 'summary');
      expect(envelope.fields.first.jsonName, 'record_id');
      expect(envelope.fields.last.type.isRecord, isTrue);
      expect(envelope.fields.last.hasDefault, isTrue);
      expect(envelope.fields.last.defaultCode, "(0, label: '')");
    },
  );

  test('missing primary exposes the shared semantic fix id', () async {
    final root = await _modelPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/legacy.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'legacy.dartitect.g.dart';

@DartitectValue()
final class Legacy extends ValueEquality with _$LegacyDartitect {
  const Legacy({required this.id});
  final String id;
}
''');

    final result = await ModelingCompiler(root).compile();
    final missing = result.diagnostics.singleWhere(
      (diagnostic) => diagnostic.rule == 'DT1030',
    );
    expect(missing.fixId, 'model.migrate.primary');
    expect(missing.path, 'lib/legacy.dart');
    expect(missing.line, isNotNull);
  });

  test('JSON types require automatic support or exact static hooks', () async {
    final root = await _modelPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/good.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'good.dartitect.g.dart';

@DartitectJson()
final class const Good({
  @DartitectField(
    decodeWith: 'GoodHooks.decodeDate',
    encodeWith: 'GoodHooks.encodeDate',
  )
  required final DateTime createdAt,
});

abstract final class GoodHooks {
  static Result<DateTime, DartitectJsonFailure> decodeDate(
    Object? input,
    DartitectJsonPath path,
  ) => input is String
      ? Ok<DateTime>(DateTime.parse(input))
      : DartitectJsonFailure.result<DateTime>(
          DartitectJsonFailureKind.customCodec,
          path,
        );

  static Result<Object?, DartitectJsonFailure> encodeDate(
    DateTime value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value.toIso8601String());
}
''');
    await File('${root.path}/lib/bad.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'bad.dartitect.g.dart';

@DartitectJson()
final class const Bad({
  required final DateTime createdAt,
});
''');
    await File('${root.path}/lib/bad_id.dart').writeAsString(r'''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'bad_id.dartitect.g.dart';

extension type const UserId(String value) {}

@DartitectJson()
final class const BadId({
  required final UserId id,
});
''');

    final result = await ModelingCompiler(root).compile();

    expect(
      result.diagnostics.where(
        (diagnostic) => diagnostic.path == 'lib/good.dart',
      ),
      isEmpty,
    );
    expect(
      result.diagnostics
          .where((diagnostic) => diagnostic.path == 'lib/bad.dart')
          .map((diagnostic) => diagnostic.rule),
      contains('DT1043'),
    );
    expect(
      result.diagnostics
          .where((diagnostic) => diagnostic.path == 'lib/bad_id.dart')
          .map((diagnostic) => diagnostic.rule),
      contains('DT1043'),
    );
    expect(
      result.workspace.libraries.map((library) => library.path),
      contains('lib/good.dart'),
    );
  });
}

Future<Directory> _modelPackage() async {
  final root = await Directory.systemTemp.createTemp('modeling-compiler-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: compiler_fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartitect_modeling: any
''');
  final core = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  final modeling = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect_modeling/dartitect_modeling.dart'),
  );
  if (core == null || modeling == null) {
    throw StateError('modeling packages are unresolved');
  }
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'compiler_fixture',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect',
          'rootUri': core.resolve('../').toString(),
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
