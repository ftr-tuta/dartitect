import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('compiles two typed extensions into owned application fields', () async {
    final root = await _extensionPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/extensions.dart')
        .writeAsString(_twoExtensions);
    final config = DartitectConfig(
      extensionSources: const <String>['lib/extensions.dart'],
    );

    final extensions = await DartitectLocalExtensionCompiler(root)
        .compile(config.extensionSources);

    expect(extensions.map((extension) => extension.fieldName), <String>[
      'analytics',
      'audit',
    ]);
    expect(extensions.map((extension) => extension.bindingType), <String>[
      'AnalyticsBinding',
      'AuditBinding',
    ]);

    final report = await DartitectWiringService(root).inspect(config: config);
    final application = report.plan.operations
        .singleWhere(
          (operation) => operation.operation.relativePath.endsWith(
            'application_module.wiring.dartitect.g.dart',
          ),
        )
        .operation
        .content;
    expect(
      application,
      contains("import 'package:extension_fixture/extensions.dart';"),
    );
    expect(application, contains('final AnalyticsBinding analytics;'));
    expect(application, contains('final AuditBinding audit;'));
    expect(application, contains('AnalyticsExtension();'));
    expect(application, contains('await analyticsDeclaration.build()'));
    expect(application, contains('analyticsDeclaration.dispose'));
    expect(application, isNot(contains('Map<String')));
    expect(application, isNot(contains('Object? analytics')));
  });

  test('rejects field collisions and homonymous annotations', () async {
    final root = await _extensionPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/extensions.dart');
    await source.writeAsString(
      _twoExtensions
          .replaceAll('AnalyticsExtension', 'FooExtension')
          .replaceAll('AuditExtension', 'FooLocalExtension'),
    );

    await expectLater(
      () =>
          DartitectLocalExtensionCompiler(root)
              .compile(const <String>['lib/extensions.dart']),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('field collision'),
        ),
      ),
    );

    await source.writeAsString('''
class DartitectProjectExtension {
  const DartitectProjectExtension();
}

@DartitectProjectExtension()
final class Pretender {}
''');
    await expectLater(
      () =>
          DartitectLocalExtensionCompiler(root)
              .compile(const <String>['lib/extensions.dart']),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('must resolve to package:dartitect'),
        ),
      ),
    );
  });

  test('accepts a workspace package only inside the real project', () async {
    final root = await _extensionPackage(localPackage: true);
    addTearDown(() => root.delete(recursive: true));
    final packageSource = File(
      '${root.path}/packages/local_extensions/lib/extensions.dart',
    );
    await packageSource.parent.create(recursive: true);
    await packageSource.writeAsString(_twoExtensions);

    final extensions = await DartitectLocalExtensionCompiler(
      root,
    ).compile(const <String>['packages/local_extensions/lib/extensions.dart']);

    expect(extensions, hasLength(2));
    expect(
      extensions.map((extension) => extension.libraryUri).toSet(),
      <String>{'package:local_extensions/extensions.dart'},
    );
  });

  test('rejects a symlink whose real path escapes the project', () async {
    if (Platform.isWindows) return;
    final root = await _extensionPackage();
    final outside = await Directory.systemTemp.createTemp(
      'dartitect-extension-outside-',
    );
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    final source = File('${outside.path}/extension.dart');
    await source.writeAsString(_twoExtensions);
    await Link('${root.path}/lib/escaped.dart').create(source.path);

    await expectLater(
      () =>
          DartitectLocalExtensionCompiler(root)
              .compile(const <String>['lib/escaped.dart']),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('outside the project boundary'),
        ),
      ),
    );
  });
}

const _twoExtensions = '''
import 'package:dartitect/dartitect.dart';

final class AnalyticsBinding {
  var disposed = false;
}

@DartitectProjectExtension()
final class AnalyticsExtension
    implements DartitectLocalExtension<AnalyticsBinding> {
  @override
  AnalyticsBinding build() => AnalyticsBinding();

  @override
  void dispose(AnalyticsBinding binding) => binding.disposed = true;
}

final class AuditBinding {
  var disposed = false;
}

@DartitectProjectExtension()
final class AuditExtension implements DartitectLocalExtension<AuditBinding> {
  @override
  AuditBinding build() => AuditBinding();

  @override
  void dispose(AuditBinding binding) => binding.disposed = true;
}
''';

Future<Directory> _extensionPackage({bool localPackage = false}) async {
  final root = await Directory.systemTemp.createTemp('dartitect-extension-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: extension_fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartitect: any
''');
  final dartitect = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  if (dartitect == null) throw StateError('dartitect package is unresolved');
  final packages = <Object?>[
    <String, Object?>{
      'name': 'extension_fixture',
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
    if (localPackage)
      <String, Object?>{
        'name': 'local_extensions',
        'rootUri': '../packages/local_extensions/',
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      },
  ];
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{'configVersion': 2, 'packages': packages}),
  );
  return root;
}
