import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'stable v1 round-trips only native_strict and namespaced extensions',
    () {
      final source = DartitectConfig(
        modeling: const DartitectModelingConfig(
          preset: DartitectModelingPreset.recommended,
        ),
        extensions: const <String, Object?>{
          'dev.example': <String, Object?>{'enabled': true},
        },
      ).encode();
      final config = DartitectConfig.parse(source);

      expect(config.configVersion, 1);
      expect(config.profile, nativeStrictProfile);
      expect(config.platforms, DartitectPlatform.values);
      expect(config.scheduler, 'none');
      expect(config.extensions['dev.example'], <String, Object?>{
        'enabled': true,
      });
      expect(DartitectConfig.parse(config.encode()).toJson(), config.toJson());
    },
  );

  test('unknown fields fail closed with escaped JSON Pointers', () {
    final decoded = DartitectConfig().toJson()
      ..['future/field'] = <String, Object?>{'enabled': true};

    expect(
      () => DartitectConfig.fromJson(decoded),
      throwsA(
        isA<DartitectConfigException>()
            .having((error) => error.pointer, 'pointer', '/future~1field')
            .having(
              (error) => error.message,
              'message',
              contains('/extensions'),
            ),
      ),
    );
  });

  test(
    'all closed platforms, scopes, providers, and capabilities round-trip',
    () {
      final headless = <DartitectPlatform, bool>{
        for (final platform in DartitectPlatform.values)
          platform: platform != DartitectPlatform.windows,
      };
      final config = DartitectConfig(
        scheduler: 'workmanager',
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'orders': DartitectFeatureDeclaration(
              profile: FeatureProfile.offlineFull,
              scope: FeatureScope.session,
              persistence: FeaturePersistenceMatrix(
                native: 'objectbox',
                web: 'drift',
              ),
              transport: 'dio',
              pagination: FeaturePagination.cursor,
              diagnostics: FeatureDiagnosticsLevel.full,
              headless: headless,
              capabilities: DartitectCapability.values,
            ),
            'catalog': DartitectFeatureDeclaration(
              profile: FeatureProfile.online,
              scope: FeatureScope.application,
              persistence: FeaturePersistenceMatrix(
                native: 'none',
                web: 'none',
              ),
              transport: 'custom:catalog-api',
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.basic,
              headless: <DartitectPlatform, bool>{
                for (final platform in DartitectPlatform.values)
                  platform: false,
              },
            ),
          },
        ),
      );

      final roundTrip = DartitectConfig.parse(config.encode());
      final orders = roundTrip.features.declarations['orders']!;
      expect(orders.profile, FeatureProfile.offlineFull);
      expect(orders.scope, FeatureScope.session);
      expect(orders.persistence.native, 'objectbox');
      expect(orders.persistence.web, 'drift');
      expect(orders.transport, 'dio');
      expect(orders.pagination, FeaturePagination.cursor);
      expect(orders.capabilities.toSet(), DartitectCapability.values.toSet());
      expect(roundTrip.toJson(), config.toJson());
    },
  );

  test('providers reject invalid identifiers and ObjectBox on web', () {
    expect(
      () => FeaturePersistenceMatrix(native: 'sqlite', web: 'memory'),
      throwsA(isA<DartitectConfigException>()),
    );
    expect(
      () => FeaturePersistenceMatrix(native: 'drift', web: 'objectbox'),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/features/declarations/persistence/web',
        ),
      ),
    );
    expect(
      () => FeaturePersistenceMatrix(
        native: 'custom:encrypted-store',
        web: 'custom:indexed-store',
      ),
      returnsNormally,
    );
  });

  test('required persistence and unimplemented combinations fail', () {
    final noHeadless = <DartitectPlatform, bool>{
      for (final platform in DartitectPlatform.values) platform: false,
    };
    expect(
      () => DartitectFeatureDeclaration(
        profile: FeatureProfile.cache,
        scope: FeatureScope.application,
        persistence: FeaturePersistenceMatrix(native: 'none', web: 'memory'),
        transport: 'dio',
        pagination: FeaturePagination.none,
        diagnostics: FeatureDiagnosticsLevel.basic,
        headless: noHeadless,
      ),
      throwsA(isA<DartitectConfigException>()),
    );

    final windowsHeadless = <DartitectPlatform, bool>{
      for (final platform in DartitectPlatform.values)
        platform: platform == DartitectPlatform.windows,
    };
    expect(
      () => DartitectConfig(
        scheduler: 'workmanager',
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'orders': DartitectFeatureDeclaration(
              profile: FeatureProfile.replica,
              scope: FeatureScope.session,
              persistence: FeaturePersistenceMatrix(
                native: 'drift',
                web: 'drift',
              ),
              transport: 'dio',
              pagination: FeaturePagination.cursor,
              diagnostics: FeatureDiagnosticsLevel.basic,
              headless: windowsHeadless,
            ),
          },
        ),
      ),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/features/declarations/orders/headless/windows',
        ),
      ),
    );
  });

  test('missing and unsupported architectural profiles fail with pointers', () {
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
    final decoded = DartitectConfig().toJson()..['profile'] = 'interop';
    expect(
      () => DartitectConfig.fromJson(decoded),
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
  });
}
