import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('compiles annotated concrete factories without loading them', () async {
    final root = await _factoryPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/factories.dart').writeAsString(_factories);

    final factories = await DartitectSemanticFactoryCompiler(root)
        .compile(_config());

    expect(factories, hasLength(2));
    final storage = factories.singleWhere(
      (factory) => factory.role == DartitectSemanticFactoryRole.storage,
    );
    expect(storage.bindingName, 'primary');
    expect(storage.declarationType, 'PrimaryStorageFactory');
    expect(storage.methods['open']!.valueType, 'PrimaryStorage');
    expect(
      storage.methods['dispose']!.parameters.single.type,
      'PrimaryStorage',
    );

    final feature = factories.singleWhere(
      (factory) => factory.role == DartitectSemanticFactoryRole.feature,
    );
    expect(feature.libraryUri, 'package:factory_fixture/factories.dart');
    expect(feature.methods.keys, <String>[
      'createRepository',
      'createViewModel',
    ]);
    expect(
      feature.methods['createViewModel']!.parameters.single.name,
      'repository',
    );
    expect(
      feature.methods['createViewModel']!.parameters.single.type,
      'TasksRepository',
    );
    expect(
      feature.methods['createRepository']!.disposalKind,
      DartitectFactoryDisposalKind.asynchronous,
    );
  });

  test('rejects annotation mismatches and erased factory types', () async {
    final root = await _factoryPackage();
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/lib/factories.dart');

    await source.writeAsString(
      _factories.replaceFirst(
        "@DartitectFeatureFactory('tasks')",
        "@DartitectFeatureFactory('other')",
      ),
    );
    await expectLater(
      DartitectSemanticFactoryCompiler(root).compile(_config()),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('must name "tasks"'),
        ),
      ),
    );

    await source.writeAsString(
      _factories.replaceFirst(
        'TasksRepository createRepository()',
        'Object createRepository()',
      ),
    );
    await expectLater(
      DartitectSemanticFactoryCompiler(root).compile(_config()),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('must be concrete and non-nullable'),
        ),
      ),
    );
  });

  test('requires synchronous ViewModel construction', () async {
    final root = await _factoryPackage();
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/lib/factories.dart').writeAsString(
      _factories.replaceFirst(
        'TasksViewModel createViewModel(TasksRepository repository) =>',
        'Future<TasksViewModel> createViewModel(TasksRepository repository) async =>',
      ),
    );

    await expectLater(
      DartitectSemanticFactoryCompiler(root).compile(_config()),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.message,
          'message',
          contains('synchronously'),
        ),
      ),
    );
  });
}

DartitectConfig _config() => DartitectConfig(
  storageContexts: <String, DartitectStorageContextConfig>{
    'primary': DartitectStorageContextConfig(
      provider: 'drift',
      mode: DartitectStorageMode.durable,
      factorySource: DartitectFactorySourceConfig(
        source: 'lib/factories.dart',
        declaration: 'PrimaryStorageFactory',
      ),
      targets: const <DartitectPlatform>[DartitectPlatform.android],
    ),
  },
  features: DartitectFeaturesConfig(
    declarations: <String, DartitectFeatureDeclaration>{
      'tasks': DartitectFeatureDeclaration(
        profile: FeatureProfile.local,
        scope: FeatureScope.application,
        factorySource: DartitectFactorySourceConfig(
          source: 'lib/factories.dart',
          declaration: 'TasksFactory',
        ),
        pagination: FeaturePagination.none,
        diagnostics: FeatureDiagnosticsLevel.off,
      ),
    },
  ),
);

const _factories = '''
import 'package:dartitect/dartitect.dart';

final class PrimaryStorage {}
final class TasksRepository implements AsyncDisposable {
  @override
  Future<void> disposeAsync() async {}
}
final class TasksViewModel {}

@DartitectApplicationContextFactory('primary')
final class PrimaryStorageFactory {
  Future<PrimaryStorage> open() async => PrimaryStorage();
  Future<void> dispose(PrimaryStorage storage) async {}
}

@DartitectFeatureFactory('tasks')
final class TasksFactory {
  TasksRepository createRepository() => TasksRepository();
  TasksViewModel createViewModel(TasksRepository repository) => TasksViewModel();
}
''';

Future<Directory> _factoryPackage() async {
  final root = await Directory.systemTemp.createTemp('dartitect-factory-');
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: factory_fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartitect: any
''');
  final dartitect = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  if (dartitect == null) throw StateError('dartitect package is unresolved');
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'factory_fixture',
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
      ],
    }),
  );
  return root;
}
