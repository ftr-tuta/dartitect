import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('exact RC5 aliases and coexistence config become strict RC6', () {
    final result = migrateExactRc5Config('''{
  "configVersion": 1,
  "profile": "native_strict",
  "layers": {
    "domain": ["**/domain/**"],
    "application": ["**/application/**"],
    "data": ["**/data/**"],
    "infrastructure": ["**/infrastructure/**"],
    "presentation": ["**/presentation/**"]
  },
  "compositionRoots": ["lib/main.dart", "test/**"],
  "generatedInfrastructure": ["**/infrastructure/**/*.g.dart"],
  "suppressions": [],
  "scaffolds": {
    "layout": "feature_first",
    "blueprints": ["simple", "remote-read", "local-first", "offline-mutation", "sync-dataset"]
  },
  "ecosystem": {"adoption": "incremental", "installedOverlap": "warning"},
  "features": {"declarations": {"orders": {
    "profile": "offline-full",
    "persistence": "objectbox",
    "transport": "dio",
    "cursorPagination": true,
    "headlessSync": true,
    "diagnostics": "full"
  }}}
}''');

    expect(result.changed, isTrue);
    expect(result.config.profile, nativeStrictProfile);
    expect(result.config.scheduler, 'workmanager');
    final orders = result.config.features.declarations['orders']!;
    expect(orders.scope, FeatureScope.application);
    expect(orders.persistence.native, 'objectbox');
    expect(orders.persistence.web, 'memory');
    expect(orders.pagination, FeaturePagination.cursor);
    expect(orders.headless[DartitectPlatform.windows], isFalse);
    expect(result.config.encode(), isNot(contains('scaffolds')));
    expect(result.config.encode(), isNot(contains('ecosystem')));
  });

  test('non-RC5 aliases and feature extensions are rejected with pointers', () {
    expect(
      () => migrateExactRc5Config('''{
        "configVersion": 1,
        "profile": "native_strict",
        "scaffolds": {"layout": "feature_first", "blueprints": ["other"]}
      }'''),
      throwsA(
        isA<DartitectConfigException>().having(
          (error) => error.pointer,
          'pointer',
          '/scaffolds/blueprints',
        ),
      ),
    );
  });
}
