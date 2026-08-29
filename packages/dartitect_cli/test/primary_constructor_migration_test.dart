import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/src/model/primary_constructor_migration.dart';
import 'package:test/test.dart';

void main() {
  test('preview is read-only and apply migrates eligible values', () async {
    final root = await _migrationPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/user.dart');
    await source.writeAsString(_traditionalSource);
    final migration = PrimaryConstructorMigration(root);

    final preview = await migration.inspect();
    expect(preview.modelCount, 1);
    expect(preview.diagnostics, isEmpty);
    expect(await source.readAsString(), _traditionalSource);

    final applied = await migration.apply();
    expect(applied.applied, isTrue);
    expect(applied.modelCount, 1);
    final migrated = await source.readAsString();
    expect(migrated, contains('final class const User({'));
    expect(migrated, contains('required final String id,'));
    expect(migrated, contains('final String? email,'));
    expect(migrated, isNot(contains('const User({required this.id')));
    expect((await migration.inspect()).operations, isEmpty);

    final generator = DartitectModelGenerator(root);
    expect((await generator.inspect()).diagnostics, isEmpty);
    await generator.apply();
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'analyze',
    ], workingDirectory: root.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('public CLI rejects the removed conversion codemod', () async {
    final root = await _migrationPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/user.dart');
    await source.writeAsString(_traditionalSource);
    final output = StringBuffer();
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    );

    expect(
      await runner.run(<String>['model', 'migrate', 'primary', '--json']),
      DartitectExitCode.usage.code,
    );
    expect(await source.readAsString(), _traditionalSource);
    expect(output, isEmpty);
    expect(errors.toString(), contains('model <check|sync>'));
  });

  test('unsupported constructors fail closed without partial edits', () async {
    final root = await _migrationPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/user.dart');
    final unsupported = _traditionalSource.replaceFirst(
      'const User({required this.id, this.email});',
      '/// Consumer-owned constructor contract.\n'
          '  const User({required this.id, this.email});',
    );
    await source.writeAsString(unsupported);

    final report = await PrimaryConstructorMigration(root).inspect();
    expect(report.operations, isEmpty);
    expect(report.diagnostics.single.rule, 'DT1031');
    expect(report.diagnostics.single.fixId, isNull);
    expect(await source.readAsString(), unsupported);
  });

  test('fault after replacement rolls every source back', () async {
    final root = await _migrationPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/user.dart');
    await source.writeAsString(_traditionalSource);
    var injected = false;
    final migration = PrimaryConstructorMigration(
      root,
      faultInjector: (event) {
        if (!injected &&
            event.point ==
                PrimaryConstructorMigrationFaultPoint.afterReplacement) {
          injected = true;
          throw StateError('fault');
        }
      },
    );

    await expectLater(migration.apply(), throwsA(isA<StateError>()));
    expect(injected, isTrue);
    expect(await source.readAsString(), _traditionalSource);
    expect(
      await File(
        '${root.path}/.dartitect/generation/model-primary-migration/source-journal.json',
      ).exists(),
      isFalse,
    );
    expect(
      await Directory(
        '${root.path}/.dartitect/generation/model-primary-migration/transaction',
      ).exists(),
      isFalse,
    );
  });

  test('source journal v2 records namespace and protocol', () async {
    final root = await _migrationPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/user.dart');
    await source.writeAsString(_traditionalSource);
    Map<String, Object?>? captured;
    final migration = PrimaryConstructorMigration(
      root,
      faultInjector: (event) async {
        if (event.point == PrimaryConstructorMigrationFaultPoint.afterJournal) {
          captured = jsonDecode(
            await File(
              '${root.path}/.dartitect/generation/model-primary-migration/source-journal.json',
            ).readAsString(),
          ) as Map<String, Object?>;
          throw StateError('capture journal');
        }
      },
    );

    await expectLater(migration.apply(), throwsA(isA<StateError>()));

    expect(
      captured?['schemaVersion'],
      DartitectGenerationVersions.sourceJournal,
    );
    expect(captured?['namespace'], 'model-primary-migration');
    expect(captured?['protocolVersion'], DartitectGenerationVersions.protocol);
    expect(await source.readAsString(), _traditionalSource);
    expect(
      await File(
        '${root.path}/.dartitect/generation/model-primary-migration/source-journal.json',
      ).exists(),
      isFalse,
    );
  });

  test('legacy source journal rolls back before a new atomic apply', () async {
    final root = await _migrationPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/user.dart');
    const interrupted = 'interrupted replacement\n';
    await source.writeAsString(interrupted);
    final transaction = Directory(
      '${root.path}/.dartitect/model-primary-migration-transaction',
    );
    await File('${transaction.path}/backup/lib/user.dart')
        .create(recursive: true)
        .then((file) => file.writeAsString(_traditionalSource));
    final journal = File(
      '${root.path}/.dartitect/model-primary-migration-journal.json',
    );
    await journal.create(recursive: true);
    await journal.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'command': 'model migrate primary',
        'phase': 'committing',
        'entries': <Object?>[
          <String, Object?>{
            'path': 'lib/user.dart',
            'beforeDigest': _sourceDigest(_traditionalSource),
            'afterDigest': _sourceDigest(interrupted),
          },
        ],
      }),
    );

    final result = await PrimaryConstructorMigration(root).apply();

    expect(result.applied, isTrue);
    expect(await source.readAsString(), contains('final class const User({'));
    expect(await journal.exists(), isFalse);
    expect(await transaction.exists(), isFalse);
  });
}

String _sourceDigest(String content) =>
    sha256.convert(utf8.encode(content)).toString();

const _traditionalSource = '''
import 'package:dartitect_modeling/dartitect_modeling.dart';

part 'user.dartitect.g.dart';

@DartitectValue()
final class User extends ValueEquality with _\$UserDartitect {
  const User({required this.id, this.email});

  /// Stable identifier.
  final String id;

  /// Optional address.
  final String? email;
}
''';

Future<Directory> _migrationPackage() async {
  final root = await Directory.systemTemp.createTemp('dartitect-primary-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: primary_fixture
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
          'name': 'primary_fixture',
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
