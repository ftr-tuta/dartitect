import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'local assembly contains only its exact non-null capability closure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-wiring-local-',
      );
      addTearDown(() => root.delete(recursive: true));
      await _preparePackage(root);
      await _writeFeatureFactory(root, 'notes');
      final config = DartitectConfig(
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'notes': DartitectFeatureDeclaration(
              profile: FeatureProfile.local,
              scope: FeatureScope.application,
              factorySource: DartitectFactorySourceConfig(
                source: 'lib/features/notes/composition/notes_factory.dart',
                declaration: 'NotesFactory',
              ),
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.off,
            ),
          },
        ),
      );

      await DartitectWiringService(root).apply(config: config);
      final source = await File(
        '${root.path}/lib/features/notes/composition/'
        'notes.wiring.dartitect.g.dart',
      ).readAsString();
      final harness = await File(
        '${root.path}/test/support/'
        'notes_feature_harness.wiring.dartitect.g.dart',
      ).readAsString();

      expect(source, contains('final class NotesInfrastructure'));
      expect(source, contains('final class NotesRuntime'));
      expect(source, contains('final NotesRepository repository;'));
      expect(source, contains('final class NotesFeatureHost'));
      expect(source, contains('ResourceTransaction transaction'));
      expect(source, contains("label: 'feature.notes.repository'"));
      expect(source, contains('(value) => value.disposeAsync()'));
      expect(source, isNot(contains('FeatureAssembly<')));
      expect(source, isNot(contains('DartitectAssemblyBinding')));
      expect(source, isNot(contains('localAuthority')));
      expect(source, isNot(contains('outbox')));
      expect(source, isNot(contains('syncDataset')));
      expect(source, isNot(contains('headlessJob')));
      expect(source, isNot(contains('contractFixture')));
      expect(source, isNot(contains('Object?')));
      expect(source, isNot(contains('= null')));
      expect(harness, contains('final class NotesFeatureHarness'));
      expect(harness, contains('FeatureContractMatrix<T>.local'));
      expect(harness, contains('Future<List<FeatureContractResult>> run()'));
    },
  );

  test(
    'offline assembly and application graph require exact typed bindings',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-wiring-full-',
      );
      addTearDown(() => root.delete(recursive: true));
      await _preparePackage(root);
      await _writeContextFactories(root);
      await _writeSessionFactory(root);
      await _writeFeatureFactory(root, 'notes');
      await _writeFeatureFactory(root, 'tasks');
      const targets = <DartitectPlatform>[DartitectPlatform.android];
      final config = DartitectConfig(
        targets: DartitectTargetsConfig(targets),
        storageContexts: <String, DartitectStorageContextConfig>{
          'primary': DartitectStorageContextConfig(
            provider: 'drift',
            mode: DartitectStorageMode.durable,
            factorySource: DartitectFactorySourceConfig(
              source: 'lib/composition/contexts/primary_storage_factory.dart',
              declaration: 'PrimaryStorageFactory',
            ),
            targets: targets,
          ),
        },
        transports: <String, DartitectTransportConfig>{
          'api': DartitectTransportConfig(
            provider: 'dio',
            factorySource: DartitectFactorySourceConfig(
              source: 'lib/composition/contexts/api_transport_factory.dart',
              declaration: 'ApiTransportFactory',
            ),
            targets: targets,
          ),
        },
        observability: DartitectObservabilityConfig(provider: 'developer'),
        scheduler: DartitectSchedulerConfig(
          provider: 'workmanager',
          targets: targets,
        ),
        session: DartitectSessionConfig(
          factorySource: DartitectFactorySourceConfig(
            source: 'lib/composition/session_factory.dart',
            declaration: 'SessionFactory',
          ),
        ),
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'notes': DartitectFeatureDeclaration(
              profile: FeatureProfile.cache,
              scope: FeatureScope.application,
              factorySource: DartitectFactorySourceConfig(
                source: 'lib/features/notes/composition/notes_factory.dart',
                declaration: 'NotesFactory',
              ),
              localAuthority: FeatureLocalAuthorityStrategy.generatedPull,
              storageContext: 'primary',
              dataset: DartitectStorageDatasetConfig.forFeature('notes'),
              transport: 'api',
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.basic,
            ),
            'tasks': DartitectFeatureDeclaration(
              profile: FeatureProfile.offlineFull,
              scope: FeatureScope.session,
              factorySource: DartitectFactorySourceConfig(
                source: 'lib/features/tasks/composition/tasks_factory.dart',
                declaration: 'TasksFactory',
              ),
              localAuthority: FeatureLocalAuthorityStrategy.generatedPull,
              storageContext: 'primary',
              dataset: DartitectStorageDatasetConfig.forFeature('tasks'),
              transport: 'api',
              pagination: FeaturePagination.cursor,
              diagnostics: FeatureDiagnosticsLevel.full,
              headlessTargets: targets,
              capabilities: DartitectCapability.values,
            ),
          },
        ),
      );

      await DartitectWiringService(root).apply(config: config);
      final feature = await File(
        '${root.path}/lib/features/tasks/composition/'
        'tasks.wiring.dartitect.g.dart',
      ).readAsString();
      final application = await File(
        '${root.path}/lib/composition/'
        'application_module.wiring.dartitect.g.dart',
      ).readAsString();
      final storage = await File(
        '${root.path}/lib/infrastructure/storage/'
        'primary_drift.wiring.dartitect.g.dart',
      ).readAsString();

      for (final field in <String>[
        'repository',
        'localAuthority',
        'localPort',
        'remotePort',
        'mapper',
        'outboxStore',
        'idempotencyPolicy',
        'conflictPolicy',
        'dataset',
        'checkpointStore',
        'syncEngine',
        'mutationCommand',
      ]) {
        expect(feature, contains(' $field;'));
      }
      expect(feature, contains('final PrimaryStorage primary;'));
      expect(feature, contains('final ApiTransport api;'));
      expect(feature, contains('PullReactiveSource<'));
      expect(feature, contains('SyncEngine<String, int, TasksFailure>'));
      expect(feature, contains("label: 'feature.tasks.sync'"));
      expect(
        feature,
        contains('MutationCommand<TasksMutation, String, void, TasksFailure>'),
      );
      expect(feature, contains("label: 'feature.tasks.mutations'"));
      expect(feature, contains('final class TasksFeatureHost'));
      expect(feature, isNot(contains('Object?')));
      expect(feature, isNot(contains('FeatureAssembly<')));
      expect(feature, isNot(contains('required this.command')));
      expect(feature, isNot(contains('contractFixture')));
      expect(
        feature,
        isNot(contains('required FutureOr<void> Function() dispose')),
      );

      expect(
        application,
        contains(
          'SessionRuntimeController<SessionGraph, DartitectSessionDescription>',
        ),
      );
      expect(application, contains('sessions;'));
      expect(
        application,
        contains('final DartitectWorkmanagerScheduler scheduler;'),
      );
      expect(
        application,
        contains('final ObservabilityRuntime observability;'),
      );
      expect(application, isNot(contains('SessionRuntimeController<Object')));
      expect(application, contains('final PrimaryStorage primary;'));
      expect(application, contains('final ApiTransport api;'));
      expect(application, contains("label: 'application.primary'"));
      expect(application, contains("label: 'application.api'"));
      expect(application, isNot(contains('ApplicationGraph<')));
      expect(application, isNot(contains('final String scheduler')));
      expect(application, isNot(contains('final String observability')));

      expect(storage, contains('PrimaryDartitectOutboxRows'));
      expect(storage, contains('PrimaryDartitectCheckpointRows'));
      expect(storage, contains('PrimaryDartitectJournalRows'));
      expect(storage, contains('PrimaryDartitectLeaseRows'));
      expect(storage, contains('PrimaryDartitectReceiptRows'));
      expect(storage, contains('PrimaryDartitectTransferCheckpointRows'));
      expect(storage, contains("feature: 'notes'"));
      expect(storage, contains("feature: 'tasks'"));
      expect(storage, contains('context_scoped_operational_tables'));
      expect(
        Directory('${root.path}/lib/infrastructure/storage')
            .listSync()
            .whereType<File>(),
        hasLength(1),
      );
      expect(
        File(
          '${root.path}/lib/features/tasks/infrastructure/'
          'tasks_drift.wiring.dartitect.g.dart',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('ObjectBox context freezes UIDs when datasets are added', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-wiring-objectbox-',
    );
    addTearDown(() => root.delete(recursive: true));
    await _preparePackage(root);
    await _writeContextFactories(root, transport: false);
    await _writeFeatureFactory(root, 'tasks');
    await _writeFeatureFactory(root, 'notes');
    const targets = <DartitectPlatform>[DartitectPlatform.android];

    DartitectConfig config(Iterable<String> features) => DartitectConfig(
      targets: DartitectTargetsConfig(targets),
      storageContexts: <String, DartitectStorageContextConfig>{
        'primary': DartitectStorageContextConfig(
          provider: 'objectbox',
          mode: DartitectStorageMode.durable,
          factorySource: DartitectFactorySourceConfig(
            source: 'lib/composition/contexts/primary_storage_factory.dart',
            declaration: 'PrimaryStorageFactory',
          ),
          targets: targets,
        ),
      },
      features: DartitectFeaturesConfig(
        declarations: <String, DartitectFeatureDeclaration>{
          for (final feature in features)
            feature: DartitectFeatureDeclaration(
              profile: FeatureProfile.local,
              scope: FeatureScope.application,
              factorySource: DartitectFactorySourceConfig(
                source:
                    'lib/features/$feature/composition/${feature}_factory.dart',
                declaration: '${_pascal(feature)}Factory',
              ),
              localAuthority: FeatureLocalAuthorityStrategy.generatedPull,
              storageContext: 'primary',
              dataset: DartitectStorageDatasetConfig.forFeature(feature),
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.off,
            ),
        },
      ),
    );

    final service = DartitectWiringService(root);
    final file = File(
      '${root.path}/lib/infrastructure/storage/'
      'primary_objectbox.wiring.dartitect.g.dart',
    );
    await service.apply(config: config(const <String>['tasks']));
    final first = await file.readAsString();
    final firstUids = _objectBoxUids(first);

    await service.apply(config: config(const <String>['notes', 'tasks']));
    final upgraded = await file.readAsString();

    expect(_objectBoxUids(upgraded), firstUids);
    expect(upgraded, contains("feature: 'notes'"));
    expect(upgraded, contains("feature: 'tasks'"));
    expect(upgraded, contains('context_scoped_operational_entities'));
  });
}

Future<void> _preparePackage(Directory root) async {
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: wiring_fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartitect: any
  dartitect_sync: any
''');
  final dartitect = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  if (dartitect == null) throw StateError('dartitect package is unresolved');
  final sync = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect_sync/dartitect_sync.dart'),
  );
  if (sync == null) throw StateError('dartitect_sync package is unresolved');
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'wiring_fixture',
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
          'name': 'dartitect_sync',
          'rootUri': sync.resolve('../').toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
}

Future<void> _writeContextFactories(
  Directory root, {
  bool transport = true,
}) async {
  final directory = Directory('${root.path}/lib/composition/contexts');
  await directory.create(recursive: true);
  await File('${directory.path}/primary_storage_factory.dart').writeAsString('''
import 'package:dartitect/dartitect.dart';

final class PrimaryStorage {}

@DartitectApplicationContextFactory('primary')
final class PrimaryStorageFactory {
  Future<PrimaryStorage> open() async => PrimaryStorage();
  Future<void> dispose(PrimaryStorage storage) async {}
}
''');
  if (!transport) return;
  await File('${directory.path}/api_transport_factory.dart').writeAsString('''
import 'package:dartitect/dartitect.dart';

final class ApiTransport {}

@DartitectTransportContextFactory('api')
final class ApiTransportFactory {
  Future<ApiTransport> open() async => ApiTransport();
  Future<void> dispose(ApiTransport transport) async {}
}
''');
}

Future<void> _writeSessionFactory(Directory root) async {
  await Directory('${root.path}/lib/composition').create(recursive: true);
  await File('${root.path}/lib/composition/session_factory.dart')
      .writeAsString('''
import 'package:dartitect/dartitect.dart';

final class AuthenticatedSession {}

@DartitectSessionFactory()
final class SessionFactory {
  AuthenticatedSession create() => AuthenticatedSession();
}
''');
}

Future<void> _writeFeatureFactory(Directory root, String feature) async {
  final type = _pascal(feature);
  final directory = Directory('${root.path}/lib/features/$feature/composition');
  await directory.create(recursive: true);
  await File('${directory.path}/${feature}_factory.dart').writeAsString('''
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

final class ${type}Repository implements AsyncDisposable {
  @override
  Future<void> disposeAsync() async {}
}
final class ${type}ViewModel {}
final class ${type}LocalPort {}
final class ${type}RemotePort {}
final class ${type}Mapper {}
final class ${type}Mutation {}
final class ${type}IdempotencyPolicy
    implements MutationIdempotencyPolicy<String, ${type}Mutation> {
  @override
  String create(String key, ${type}Mutation argument) => key;
}
final class ${type}ConflictPolicy
    implements MutationConflictPolicy<String> {
  @override
  String resolve(String local, String remote) => local;
}
final class ${type}Failure {}
final class ${type}OutboxStore
    implements MutationOutboxStore<String, ${type}Mutation, ${type}Failure> {
  @override
  Future<Result<void, ${type}Failure>> applyLocalAndEnqueue(
    OutboxOperation<String, ${type}Mutation> operation,
    CancellationSignal signal,
  ) async => const Ok<void>(null);
  @override
  Future<Result<void, ${type}Failure>> markState(
    OutboxOperation<String, ${type}Mutation> operation,
    CancellationSignal signal,
  ) async => const Ok<void>(null);
  @override
  Future<Result<List<OutboxOperation<String, ${type}Mutation>>, ${type}Failure>>
  loadRecoverable(CancellationSignal signal) async =>
      const Ok<List<OutboxOperation<String, ${type}Mutation>>>(
        <OutboxOperation<String, ${type}Mutation>>[],
      );
  @override
  Future<Result<void, ${type}Failure>> compensate(
    OutboxOperation<String, ${type}Mutation> operation,
    CancellationSignal signal,
  ) async => const Ok<void>(null);
}
final class ${type}CheckpointStore
    implements SyncCheckpointStore<String, int> {
  @override
  Future<int?> read(String key, CancellationSignal signal) async => null;
  @override
  Future<void> write(String key, int checkpoint, CancellationSignal signal,
      {int? fencingToken}) async {}
  @override
  Future<void> remove(String key, CancellationSignal signal) async {}
}

@DartitectFeatureFactory('$feature')
final class ${type}Factory {
  ${type}LocalPort createLocalPort() => ${type}LocalPort();
  ${type}RemotePort createRemotePort() => ${type}RemotePort();
  ${type}Mapper createMapper() => ${type}Mapper();
  MutationOutboxStore<String, ${type}Mutation, ${type}Failure>
  createOutboxStore() => ${type}OutboxStore();
  MutationIdempotencyPolicy<String, ${type}Mutation>
  createIdempotencyPolicy() =>
      ${type}IdempotencyPolicy();
  MutationConflictPolicy<String> createConflictPolicy() =>
      ${type}ConflictPolicy();
  Future<Result<void, ${type}Failure>> synchronizeMutation(
    ${type}RemotePort remotePort,
    OutboxOperation<String, ${type}Mutation> operation,
    CancellationSignal cancellation,
  ) async => const Ok<void>(null);
  MutationFailurePolicy classifyMutationFailure(${type}Failure failure) =>
      const MutationFailurePolicy.queued();
  SyncDataset<String, int, ${type}Failure> createDataset() => SyncDataset(
    key: '$feature',
    synchronize: (context) async => Ok(
      SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
    ),
  );
  ${type}CheckpointStore createCheckpointStore() => ${type}CheckpointStore();
  Stream<void> watch() => const Stream<void>.empty();
  Future<Result<List<String>, ${type}Failure>> read(
    CancellationSignal cancellation,
  ) async => const Ok<List<String>>(<String>[]);
  ${type}Repository createRepository() => ${type}Repository();
  ${type}ViewModel createViewModel(${type}Repository repository) =>
      ${type}ViewModel();
}
''');
}

String _pascal(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

Map<String, int> _objectBoxUids(String source) => <String, int>{
  for (final match in RegExp(
    r"^    '([^']+)': ([0-9]+),$",
    multiLine: true,
  ).allMatches(source))
    match.group(1)!: int.parse(match.group(2)!),
};
