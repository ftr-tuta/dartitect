import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('modeling presets preserve explicit capability opt-in', () {
    expect(DartitectModelingPreset.minimal.suggestedCapabilities, <String>[
      'value',
    ]);
    expect(DartitectModelingPreset.recommended.suggestedCapabilities, <String>[
      'value',
      'json',
      'projection',
      'mapper',
    ]);
    expect(
      DartitectModelingPreset.interop.allowsExistingModelGenerators,
      isTrue,
    );
    expect(
      DartitectModelingPreset.recommended.allowsExistingModelGenerators,
      isFalse,
    );
  });

  test('stable v1 round-trips strict boundaries and unknown keys', () {
    final source = DartitectConfig(
      unknown: const <String, Object?>{
        'futureStableField': <String, Object?>{'enabled': true},
      },
    ).encode();
    final config = DartitectConfig.parse(source);

    expect(config.configVersion, 1);
    expect(config.profile, nativeStrictProfile);
    expect(
      config.layers.keys,
      containsAll(<String>[
        'presentation',
        'application',
        'domain',
        'data',
        'infrastructure',
      ]),
    );
    expect(config.generatedInfrastructure, isNotEmpty);
    expect(config.compositionRoots, contains('test/**'));
    expect(config.scaffolds['blueprints'], hasLength(5));
    expect(config.unknown, contains('futureStableField'));
    expect(DartitectConfig.parse(config.encode()).toJson(), config.toJson());
  });

  test('modeling and ecosystem extend v1 without changing legacy defaults', () {
    final legacy = DartitectConfig();
    expect(legacy.toJson(), isNot(contains('modeling')));
    expect(legacy.toJson(), isNot(contains('ecosystem')));

    final configured = DartitectConfig(
      modeling: const DartitectModelingConfig(
        preset: DartitectModelingPreset.interop,
      ),
      ecosystem: const DartitectEcosystemConfig(),
    );
    final roundTrip = DartitectConfig.parse(configured.encode());

    expect(roundTrip.modeling?.preset, DartitectModelingPreset.interop);
    expect(roundTrip.modeling?.maxDepth, 64);
    expect(roundTrip.modeling?.maxCollectionItems, 10000);
    expect(roundTrip.modeling?.maxNodes, 100000);
    expect(roundTrip.ecosystem?.installedOverlap, 'warning');
  });

  test('feature declarations round-trip profiles and unknown keys', () {
    final config = DartitectConfig(
      features: DartitectFeaturesConfig(
        declarations: <String, DartitectFeatureDeclaration>{
          'orders': DartitectFeatureDeclaration(
            profile: FeatureProfile.offlineFull,
            persistence: 'drift',
            transport: 'dio',
            cursorPagination: true,
            headlessSync: true,
            diagnostics: FeatureDiagnosticsLevel.full,
            unknown: const <String, Object?>{'futurePolicy': true},
          ),
        },
        unknown: const <String, Object?>{'futureRegistry': 2},
      ),
    );

    final roundTrip = DartitectConfig.parse(config.encode());
    final orders = roundTrip.features!.declarations['orders']!;
    expect(orders.profile, FeatureProfile.offlineFull);
    expect(orders.persistence, 'drift');
    expect(orders.transport, 'dio');
    expect(orders.cursorPagination, isTrue);
    expect(orders.headlessSync, isTrue);
    expect(orders.diagnostics, FeatureDiagnosticsLevel.full);
    expect(orders.unknown, containsPair('futurePolicy', true));
    expect(roundTrip.features!.unknown, containsPair('futureRegistry', 2));
    expect(roundTrip.toJson(), config.toJson());
  });

  test('feature declarations reject incompatible profile capabilities', () {
    expect(
      () => DartitectFeatureDeclaration(
        profile: FeatureProfile.online,
        persistence: 'drift',
        transport: 'dio',
      ),
      throwsA(isA<DartitectConfigException>()),
    );
    expect(
      () => DartitectFeatureDeclaration(
        profile: FeatureProfile.cache,
        persistence: 'drift',
        transport: 'dio',
        headlessSync: true,
      ),
      throwsA(isA<DartitectConfigException>()),
    );
  });

  test('missing version and future version fail closed with pointers', () {
    expect(
      () => DartitectConfig.parse('{}'),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/configVersion',
        ),
      ),
    );
    expect(
      () => DartitectConfig.parse('{"configVersion":2}'),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/configVersion',
        ),
      ),
    );
  });

  test('experimental v1 is rejected instead of migrated', () {
    expect(
      () => DartitectConfig.parse('''
{
  "configVersion": 1,
  "architectureProfile": "native_mvvm",
  "featureLayout": "feature_first"
}
'''),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/profile',
        ),
      ),
    );
  });

  test('normalizes globs and validates permanent suppressions', () {
    final decoded = DartitectConfig().toJson();
    decoded['compositionRoots'] = <String>['lib\\composition\\**'];
    decoded['suppressions'] = <Object?>[
      <String, Object?>{
        'code': 'DT1005',
        'path': 'lib\\legacy\\**',
        'reason': 'Boundary extraction is tracked',
        'owner': 'architecture',
        'expiresAt': '2026-12-31',
      },
    ];
    final config = DartitectConfig.fromJson(decoded);

    expect(config.compositionRoots.single, 'lib/composition/**');
    expect(config.suppressions.single.path, 'lib/legacy/**');
    expect(
      () => DartitectConfig.fromJson(<String, Object?>{
        ...DartitectConfig().toJson(),
        'suppressions': <Object?>[
          <String, Object?>{
            'code': 'DT1005',
            'path': 'lib/**',
            'reason': 'legacy',
            'owner': 'team',
          },
        ],
      }),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/suppressions/0/permanentJustification',
        ),
      ),
    );
  });

  test('rejects unsafe globs and unknown blueprints', () {
    final unsafe = DartitectConfig().toJson()
      ..['compositionRoots'] = <String>['../outside/**'];
    expect(
      () => DartitectConfig.fromJson(unsafe),
      throwsA(isA<DartitectConfigException>()),
    );

    final unsupported = DartitectConfig().toJson()
      ..['scaffolds'] = <String, Object?>{
        'layout': 'feature_first',
        'blueprints': <String>['magic'],
      };
    expect(
      () => DartitectConfig.fromJson(unsupported),
      throwsA(isA<DartitectConfigException>()),
    );
  });
}
