import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  const allTargets = <DartitectPlatform>[
    DartitectPlatform.android,
    DartitectPlatform.ios,
    DartitectPlatform.macos,
    DartitectPlatform.windows,
    DartitectPlatform.linux,
    DartitectPlatform.web,
  ];

  test('stable v2 round-trips closed target-aware blocks', () {
    final config = DartitectConfig(
      targets: DartitectTargetsConfig(const <DartitectPlatform>[
        DartitectPlatform.android,
        DartitectPlatform.web,
      ]),
      modeling: const DartitectModelingConfig(
        preset: DartitectModelingPreset.recommended,
      ),
      extensionSources: const <String>['lib/extensions.dart'],
    );
    final parsed = DartitectConfig.parse(config.encode());

    expect(parsed.configVersion, 2);
    expect(parsed.profile, nativeStrictProfile);
    expect(parsed.targets.platforms, <DartitectPlatform>[
      DartitectPlatform.android,
      DartitectPlatform.web,
    ]);
    expect(parsed.scheduler.provider, 'none');
    expect(parsed.observability.provider, 'none');
    expect(parsed.extensionSources, <String>['lib/extensions.dart']);
    expect(DartitectConfig.parse(parsed.encode()).toJson(), parsed.toJson());
  });

  test('unknown and v1 fields fail closed with exact pointers', () {
    final decoded = DartitectConfig().toJson()
      ..['future/field'] = <String, Object?>{'enabled': true};
    expect(
      () => DartitectConfig.fromJson(decoded),
      throwsA(
        isA<DartitectConfigException>()
            .having((error) => error.pointer, 'pointer', '/future~1field')
            .having((error) => error.message, 'message', contains('closed')),
      ),
    );
    final v1 = DartitectConfig().toJson()
      ..['configVersion'] = 1
      ..['platforms'] = <String>['android'];
    expect(
      () => DartitectConfig.fromJson(v1),
      throwsA(isA<DartitectConfigException>()),
    );
  });

  test('local, online, and durable profiles use named capability blocks', () {
    final config = DartitectConfig(
      targets: DartitectTargetsConfig(allTargets),
      storageContexts: <String, DartitectStorageContextConfig>{
        'primary': DartitectStorageContextConfig(
          provider: 'drift',
          mode: DartitectStorageMode.durable,
          targets: allTargets,
        ),
      },
      transports: <String, DartitectTransportConfig>{
        'api': DartitectTransportConfig(provider: 'dio', targets: allTargets),
      },
      scheduler: DartitectSchedulerConfig(
        provider: 'workmanager',
        targets: const <DartitectPlatform>[
          DartitectPlatform.android,
          DartitectPlatform.ios,
          DartitectPlatform.macos,
          DartitectPlatform.linux,
          DartitectPlatform.web,
        ],
      ),
      features: DartitectFeaturesConfig(
        declarations: <String, DartitectFeatureDeclaration>{
          'settings': DartitectFeatureDeclaration(
            profile: FeatureProfile.local,
            scope: FeatureScope.application,
            storageContext: 'primary',
            dataset: DartitectStorageDatasetConfig.forFeature('settings'),
            targets: const <DartitectPlatform>[DartitectPlatform.android],
            pagination: FeaturePagination.none,
            diagnostics: FeatureDiagnosticsLevel.basic,
          ),
          'catalog': DartitectFeatureDeclaration(
            profile: FeatureProfile.online,
            scope: FeatureScope.application,
            transport: 'api',
            pagination: FeaturePagination.none,
            diagnostics: FeatureDiagnosticsLevel.basic,
          ),
          'orders': DartitectFeatureDeclaration(
            profile: FeatureProfile.offlineFull,
            scope: FeatureScope.session,
            storageContext: 'primary',
            dataset: DartitectStorageDatasetConfig.forFeature('orders'),
            transport: 'api',
            pagination: FeaturePagination.cursor,
            diagnostics: FeatureDiagnosticsLevel.full,
            headlessTargets: const <DartitectPlatform>[
              DartitectPlatform.android,
            ],
            capabilities: DartitectCapability.values,
          ),
        },
      ),
    );

    final roundTrip = DartitectConfig.parse(config.encode());
    expect(
      roundTrip.features.declarations['settings']!.profile,
      FeatureProfile.local,
    );
    expect(
      roundTrip.features.declarations['orders']!.storageContext,
      'primary',
    );
    expect(roundTrip.storageContexts['primary']!.provider, 'drift');
    expect(roundTrip.transports['api']!.provider, 'dio');
    expect(roundTrip.toJson(), config.toJson());
  });

  test('profiles reject implicit providers and invalid target closure', () {
    expect(
      () => DartitectFeatureDeclaration(
        profile: FeatureProfile.online,
        scope: FeatureScope.application,
        pagination: FeaturePagination.none,
        diagnostics: FeatureDiagnosticsLevel.basic,
      ),
      throwsA(isA<DartitectConfigException>()),
    );
    expect(
      () => DartitectFeatureDeclaration(
        profile: FeatureProfile.local,
        scope: FeatureScope.application,
        transport: 'api',
        pagination: FeaturePagination.none,
        diagnostics: FeatureDiagnosticsLevel.basic,
      ),
      throwsA(isA<DartitectConfigException>()),
    );
    expect(
      () => DartitectConfig(
        targets: DartitectTargetsConfig(const <DartitectPlatform>[
          DartitectPlatform.android,
        ]),
        transports: <String, DartitectTransportConfig>{
          'api': DartitectTransportConfig(
            provider: 'dio',
            targets: const <DartitectPlatform>[DartitectPlatform.web],
          ),
        },
      ),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/transports/api/targets',
        ),
      ),
    );
  });

  test('memory is explicit and release-ineligible by construction', () {
    final memory = DartitectStorageContextConfig(
      provider: 'memory',
      mode: DartitectStorageMode.memory,
      targets: const <DartitectPlatform>[DartitectPlatform.android],
    );
    expect(memory.mode, DartitectStorageMode.memory);
    expect(
      () => DartitectStorageContextConfig(
        provider: 'memory',
        mode: DartitectStorageMode.durable,
        targets: const <DartitectPlatform>[DartitectPlatform.android],
      ),
      throwsA(isA<DartitectConfigException>()),
    );
  });

  test('durable profiles and dataset registrations fail closed', () {
    const target = <DartitectPlatform>[DartitectPlatform.android];
    expect(
      () => DartitectConfig(
        targets: DartitectTargetsConfig(target),
        storageContexts: <String, DartitectStorageContextConfig>{
          'preview': DartitectStorageContextConfig(
            provider: 'memory',
            mode: DartitectStorageMode.memory,
            targets: target,
          ),
        },
        transports: <String, DartitectTransportConfig>{
          'api': DartitectTransportConfig(provider: 'dio', targets: target),
        },
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'tasks': DartitectFeatureDeclaration(
              profile: FeatureProfile.cache,
              scope: FeatureScope.application,
              storageContext: 'preview',
              dataset: DartitectStorageDatasetConfig.forFeature('tasks'),
              transport: 'api',
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.basic,
            ),
          },
        ),
      ),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/features/declarations/tasks/storageContext',
        ),
      ),
    );

    expect(
      () => DartitectFeatureDeclaration(
        profile: FeatureProfile.local,
        scope: FeatureScope.application,
        storageContext: 'preview',
        pagination: FeaturePagination.none,
        diagnostics: FeatureDiagnosticsLevel.off,
      ),
      throwsA(isA<DartitectConfigException>()),
    );
  });

  test('normalizes globs and confined extension sources', () {
    final decoded = DartitectConfig().toJson();
    decoded['compositionRoots'] = <String>['lib\\composition\\**'];
    decoded['extensionSources'] = <String>['lib\\extensions.dart'];
    final config = DartitectConfig.fromJson(decoded);
    expect(config.compositionRoots.single, 'lib/composition/**');
    expect(config.extensionSources.single, 'lib/extensions.dart');

    expect(
      () => DartitectConfig(extensionSources: const <String>['../escape.dart']),
      throwsA(isA<DartitectConfigException>()),
    );
  });

  test('suppressions are narrow, owned, and always expiring', () {
    final withoutExpiry = DartitectConfig().toJson();
    withoutExpiry['suppressions'] = <Object?>[
      <String, Object?>{
        'code': 'DT1001',
        'path': 'lib/domain/temporary.dart',
        'reason': 'Temporary compatibility investigation',
        'owner': 'architecture',
        'permanentJustification': 'Never accepted in config v2',
      },
    ];

    expect(
      () => DartitectConfig.fromJson(withoutExpiry),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/suppressions/0/permanentJustification',
        ),
      ),
    );
  });
}
