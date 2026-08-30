import 'dart:io';

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
      final config = DartitectConfig(
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'notes': DartitectFeatureDeclaration(
              profile: FeatureProfile.local,
              scope: FeatureScope.application,
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

      expect(
        source,
        contains(
          'final class NotesFeatureAssembly<\n'
          '  Repository extends Object,\n'
          '  ViewModel extends Object\n'
          '>',
        ),
      );
      expect(
        source,
        contains('required DartitectAssemblyBinding<Repository> repository'),
      );
      expect(source, contains('ResourceTransaction.create'));
      expect(source, contains('OwnedGraph<_NotesFeatureBindings<Repository>>'));
      expect(source, isNot(contains('DartitectAssemblyBinding<Storage>')));
      expect(source, isNot(contains('DartitectAssemblyBinding<Transport>')));
      expect(source, isNot(contains('localAuthority')));
      expect(source, isNot(contains('outbox')));
      expect(source, isNot(contains('syncDataset')));
      expect(source, isNot(contains('headlessJob')));
      expect(source, isNot(contains('contractFixture')));
      expect(source, isNot(contains('Object?')));
      expect(source, isNot(contains('= null')));
    },
  );

  test(
    'offline assembly and application graph require exact typed bindings',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-wiring-full-',
      );
      addTearDown(() => root.delete(recursive: true));
      const targets = <DartitectPlatform>[DartitectPlatform.android];
      final config = DartitectConfig(
        targets: DartitectTargetsConfig(targets),
        storageContexts: <String, DartitectStorageContextConfig>{
          'primary': DartitectStorageContextConfig(
            provider: 'drift',
            mode: DartitectStorageMode.durable,
            targets: targets,
          ),
        },
        transports: <String, DartitectTransportConfig>{
          'api': DartitectTransportConfig(provider: 'dio', targets: targets),
        },
        observability: DartitectObservabilityConfig(provider: 'developer'),
        scheduler: DartitectSchedulerConfig(
          provider: 'workmanager',
          targets: targets,
        ),
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'notes': DartitectFeatureDeclaration(
              profile: FeatureProfile.cache,
              scope: FeatureScope.application,
              storageContext: 'primary',
              dataset: DartitectStorageDatasetConfig.forFeature('notes'),
              transport: 'api',
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.basic,
            ),
            'tasks': DartitectFeatureDeclaration(
              profile: FeatureProfile.offlineFull,
              scope: FeatureScope.session,
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
        'storage',
        'transport',
        'localAuthority',
        'pagination',
        'outbox',
        'syncDataset',
        'headlessJob',
        'diagnostics',
        'attachments',
        'credentials',
        'forms',
        'queries',
      ]) {
        expect(feature, contains('> $field,'));
      }
      expect(feature, contains('ResourceTransaction.create'));
      expect(feature, contains('repository.bind(transaction)'));
      expect(feature, contains('OwnedGraph<'));
      expect(feature, isNot(contains('Object?')));
      expect(feature, isNot(contains('required this.command')));
      expect(feature, isNot(contains('contractFixture')));
      expect(
        feature,
        isNot(contains('required FutureOr<void> Function() dispose')),
      );

      expect(
        application,
        contains('SessionRuntimeController<Session, SessionFailure> sessions'),
      );
      expect(
        application,
        contains('final DartitectWorkmanagerScheduler scheduler;'),
      );
      expect(
        application,
        contains('final ObservabilityRuntime observability;'),
      );
      expect(application, isNot(contains('SessionRuntimeController<Object')));
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
    const targets = <DartitectPlatform>[DartitectPlatform.android];

    DartitectConfig config(Iterable<String> features) => DartitectConfig(
      targets: DartitectTargetsConfig(targets),
      storageContexts: <String, DartitectStorageContextConfig>{
        'primary': DartitectStorageContextConfig(
          provider: 'objectbox',
          mode: DartitectStorageMode.durable,
          targets: targets,
        ),
      },
      features: DartitectFeaturesConfig(
        declarations: <String, DartitectFeatureDeclaration>{
          for (final feature in features)
            feature: DartitectFeatureDeclaration(
              profile: FeatureProfile.local,
              scope: FeatureScope.application,
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

Map<String, int> _objectBoxUids(String source) => <String, int>{
  for (final match in RegExp(
    r"^    '([^']+)': ([0-9]+),$",
    multiLine: true,
  ).allMatches(source))
    match.group(1)!: int.parse(match.group(2)!),
};
