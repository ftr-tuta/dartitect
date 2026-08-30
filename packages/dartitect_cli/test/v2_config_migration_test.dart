import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('v2 to v3 migration is deterministic and records manual factories', () {
    const source = '''{
  "configVersion": 2,
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
  "generatedSuffixes": [".g.dart", ".dartitect.g.dart"],
  "suppressions": [],
  "targets": {"platforms": ["android"]},
  "storageContexts": {
    "primary": {"provider": "drift", "mode": "durable", "targets": ["android"]}
  },
  "transports": {},
  "observability": {"provider": "none"},
  "scheduler": {"provider": "none"},
  "features": {"declarations": {
    "tasks": {
      "profile": "local",
      "scope": "application",
      "storageContext": "primary",
      "dataset": {"dataset": "tasks", "partition": "default_partition", "codec": "tasks_v1", "retention": "indefinite", "transactionBoundary": "tasks_transaction"},
      "pagination": "none",
      "diagnostics": "off",
      "headlessTargets": [],
      "capabilities": []
    }
  }},
  "extensionSources": []
}''';

    final first = migrateDartitectV2Config(source);
    final second = migrateDartitectV2Config(source);

    expect(first.migrationId, dartitectV2ToV3MigrationId);
    expect(first.changed, isTrue);
    expect(first.config.configVersion, 3);
    expect(first.config.encode(), second.config.encode());
    expect(
      first.config.storageContexts['primary']!.scope,
      FeatureScope.application,
    );
    expect(
      first.config.features.declarations['tasks']!.localAuthority,
      FeatureLocalAuthorityStrategy.generatedPull,
    );
    expect(first.manualActions, <String>[
      'lib/composition/contexts/primary_storage_factory.dart',
      'lib/features/tasks/composition/tasks_factory.dart',
    ]);

    final noOp = migrateDartitectV2Config(first.config.encode());
    expect(noOp.changed, isFalse);
    expect(noOp.manualActions, isEmpty);
  });
}
