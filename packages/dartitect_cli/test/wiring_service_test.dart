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
            'tasks': DartitectFeatureDeclaration(
              profile: FeatureProfile.offlineFull,
              scope: FeatureScope.session,
              storageContext: 'primary',
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
    },
  );
}
