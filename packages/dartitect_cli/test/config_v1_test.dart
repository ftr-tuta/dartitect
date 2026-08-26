import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
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
