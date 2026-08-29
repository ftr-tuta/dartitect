import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/src/scan/baseline.dart';
import 'package:test/test.dart';

void main() {
  test(
    'scanner is deterministic and detects architecture violations',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect scan espaço ',
      );
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', '''name: sample
environment:
  sdk: ^3.13.0
dependencies:
  flutter_riverpod: any
  dio: any
''');
      await _write(
        root,
        'lib/features/orders/domain/order.dart',
        "import 'package:flutter/widgets.dart';\n",
      );
      await _write(
        root,
        'lib/features/orders/presentation/orders_view_model.dart',
        "import 'package:dio/dio.dart';\nvoid use(BuildContext context) {}\n",
      );
      await _write(
        root,
        'lib/generated.g.dart',
        "import 'package:provider/provider.dart';\n",
      );

      final before = await _snapshot(root);
      final first = await ProjectScanner(root).scan();
      final second = await ProjectScanner(root).scan();
      final after = await _snapshot(root);

      expect(first.packageName, 'sample');
      expect(first.features, <String>['orders']);
      expect(first.dartFileCount, 3);
      expect(
        first.violations.map((finding) => finding.code),
        containsAll(<String>['DT1001', 'DT1004', 'DT1005', 'DT1006']),
      );
      expect(
        first.violations.map((finding) => finding.toJson()).toList(),
        second.violations.map((finding) => finding.toJson()).toList(),
      );
      expect(after, before, reason: 'The Stage 1 scanner must never write.');
    },
  );

  test('scanner reports a missing pubspec instead of crashing', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-scan-empty-');
    addTearDown(() => root.delete(recursive: true));

    final scan = await ProjectScanner(root).scan();

    expect(scan.findings.single.code, 'DT0001');
  });

  test('borrowing hosts reject only known inline disposable values', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-host-value-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: sample\n');
    await _write(root, 'dartitect.json', DartitectConfig().encode());
    await _write(
      root,
      'lib/features/orders/presentation/host.dart',
      '''import 'package:dartitect_flutter/dartitect_flutter.dart';

Object unsafeApplication() => ApplicationHost<Object>.value(
  value: BootstrapCoordinator<Object>(),
);
Object unsafeSession() => SessionHost<Object, Object>.value(
  value: SessionRuntimeController<Object, Object>(),
);
Object unsafeViewModel() => ViewModelHost<Object>.value(
  value: ReactiveOwner(),
);

Object safe(BootstrapCoordinator<Object> coordinator) =>
    ApplicationHost<Object>.value(value: coordinator);
''',
    );

    final scan = await ProjectScanner(root).scan();
    final violations = scan.violations.where(
      (finding) =>
          finding.code == DartitectRuleCodes.temporaryDisposableHostValue,
    );
    expect(violations, hasLength(3));
    expect(
      violations.every((finding) => finding.evidence!.endsWith('.value')),
      isTrue,
    );
  });

  test(
    'Drift stays in infrastructure without neutral type false positives',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-drift-');
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', '''name: drift_sample
dependencies:
  drift: any
  dartitect_drift: any
''');
      await _write(
        root,
        'lib/features/orders/application/orders_service.dart',
        "import 'package:drift/drift.dart';\nGeneratedDatabase? database;\n",
      );
      await _write(
        root,
        'lib/features/orders/presentation/orders_view_model.dart',
        "import 'package:dartitect_drift/dartitect_drift.dart';\n",
      );
      await _write(
        root,
        'lib/features/orders/infrastructure/orders_database.dart',
        "import 'package:drift/drift.dart';\nclass Orders extends Table {}\n",
      );
      await _write(
        root,
        'lib/features/orders/domain/table.dart',
        'class Table {}\nclass Dao {}\n',
      );

      final scan = await ProjectScanner(root).scan();

      expect(scan.capabilities, contains('drift'));
      expect(
        scan.violations.map((finding) => finding.path),
        containsAll(<String>[
          'lib/features/orders/application/orders_service.dart',
          'lib/features/orders/presentation/orders_view_model.dart',
        ]),
      );
      expect(
        scan.violations.where(
          (finding) => finding.path?.endsWith('/domain/table.dart') ?? false,
        ),
        isEmpty,
      );
      expect(
        scan.violations.where(
          (finding) => finding.path?.contains('/infrastructure/') ?? false,
        ),
        isEmpty,
      );
    },
  );

  test(
    'provider adapter package is itself an infrastructure boundary',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-provider-package-',
      );
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', '''name: dartitect_drift
dependencies:
  drift: any
''');
      await _write(
        root,
        'lib/src/owner.dart',
        "import 'package:drift/drift.dart';\nGeneratedDatabase? database;\n",
      );

      final scan = await ProjectScanner(root).scan();

      expect(scan.violations, isEmpty);
    },
  );

  test('audits transitive lockfile packages and generated imports', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-lock-audit-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: lock_sample\n');
    await _write(root, 'pubspec.lock', '''packages:
  riverpod:
    dependency: transitive
    description:
      name: riverpod
  test:
    dependency: direct dev
sdks:
  dart: ">=3.13.0 <4.0.0"
''');
    await _write(
      root,
      'lib/generated.freezed.dart',
      "export 'package:flutter_bloc/flutter_bloc.dart';\n",
    );

    final scan = await ProjectScanner(root).scan();

    expect(scan.dartFileCount, 1);
    expect(
      scan.violations.where(
        (finding) => finding.code == DartitectRuleCodes.forbiddenArchitecture,
      ),
      hasLength(1),
    );
    expect(
      scan.violations.map((finding) => finding.path),
      contains('lib/generated.freezed.dart'),
    );
    expect(
      scan.violations,
      contains(
        isA<DartitectFinding>()
            .having((finding) => finding.code, 'code', 'DT1017')
            .having((finding) => finding.path, 'path', 'pubspec.lock')
            .having(
              (finding) => finding.severity,
              'severity',
              FindingSeverity.error,
            ),
      ),
    );
  });

  test(
    'generated infrastructure audits imports without semantic false positives',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-generated-infrastructure-',
      );
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', 'name: generated_sample\n');
      await _write(root, 'dartitect.json', '''
{
  "configVersion": 2,
  "profile": "native_strict",
  "layers": {
    "domain": ["lib/domain/**"],
    "application": ["lib/application/**"],
    "data": ["lib/data/**"],
    "infrastructure": ["lib/infrastructure/**"],
    "presentation": ["lib/presentation/**"]
  },
  "compositionRoots": ["lib/main.dart"],
  "generatedInfrastructure": ["lib/objectbox.g.dart"],
  "generatedSuffixes": [".g.dart", ".dartitect.g.dart"],
  "suppressions": [],
  "features": {"declarations": {}},
  "targets": {"platforms": ["android", "ios", "macos", "windows", "linux", "web"]},
  "storageContexts": {},
  "transports": {},
  "observability": {"provider": "none"},
  "scheduler": {"provider": "none"},
  "extensionSources": []
}
''');
      await _write(
        root,
        'lib/objectbox.g.dart',
        "import 'package:objectbox/src/native/bindings/data.dart';\n"
            "import 'package:provider/provider.dart';\n"
            'Store open() => Store();\n',
      );

      final scan = await ProjectScanner(root).scan();

      expect(scan.dartFileCount, 1);
      expect(scan.violations.map((finding) => finding.code).toSet(), <String>{
        DartitectRuleCodes.forbiddenArchitecture,
      });
      expect(
        scan.violations.map((finding) => finding.path),
        everyElement('lib/objectbox.g.dart'),
      );
    },
  );

  test('Native Strict confines DartitectScope to composition roots', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-scope-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: scope_sample\n');
    await _write(root, 'dartitect.json', '''
{
  "configVersion": 2,
  "profile": "native_strict",
  "layers": {
    "domain": ["lib/domain/**"],
    "application": ["lib/application/**"],
    "data": ["lib/data/**"],
    "infrastructure": ["lib/infrastructure/**"],
    "presentation": ["lib/presentation/**"]
  },
  "compositionRoots": ["lib/composition/**"],
  "generatedInfrastructure": ["lib/infrastructure/**/*.g.dart"],
  "generatedSuffixes": [".g.dart", ".dartitect.g.dart"],
  "suppressions": [],
  "features": {"declarations": {}},
  "targets": {"platforms": ["android", "ios", "macos", "windows", "linux", "web"]},
  "storageContexts": {},
  "transports": {},
  "observability": {"provider": "none"},
  "scheduler": {"provider": "none"},
  "extensionSources": []
}
''');
    await _write(
      root,
      'lib/presentation/page.dart',
      '''void read(BuildContext context) {
  DartitectScope.read<AppRoot>(context);
}
''',
    );
    await _write(
      root,
      'lib/composition/route.dart',
      '''void compose(BuildContext context) {
  DartitectScope.read<AppRoot>(context);
}
''',
    );

    final scan = await ProjectScanner(root).scan();

    expect(
      scan.violations.where(
        (finding) => finding.code == DartitectRuleCodes.scopeBoundary,
      ),
      hasLength(1),
    );
    expect(
      scan.violations
          .singleWhere(
            (finding) => finding.code == DartitectRuleCodes.scopeBoundary,
          )
          .path,
      'lib/presentation/page.dart',
    );
  });

  test(
    'semantic scan ignores comments and strings and handles multiline imports',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-semantic-');
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', 'name: semantic_sample\n');
      await _write(
        root,
        'lib/features/map/presentation/map_view_model.dart',
        '''/// BuildContext is intentionally only documentation.
const description = 'BuildContext and import package:dio/dio.dart';
final Size Function() readSize = () => const Size();
''',
      );
      await _write(
        root,
        'lib/features/orders/presentation/orders_view_model.dart',
        '''import
  'package:dio/dio.dart';
''',
      );

      final scan = await ProjectScanner(root).scan();

      expect(scan.violations.map((finding) => finding.code), <String>[
        DartitectRuleCodes.presentationInfrastructure,
      ]);
      expect(scan.violations.single.line, 2);
    },
  );

  test('stable config v2 classifies custom layers and suppressions', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-config-v2-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: configured_sample\n');
    await _write(root, 'dartitect.json', '''
{
  "configVersion": 2,
  "profile": "native_strict",
  "layers": {
    "domain": ["lib/model/**"],
    "application": ["lib/application/**"],
    "data": ["lib/storage/**"],
    "infrastructure": ["lib/infrastructure/**"],
    "presentation": ["lib/ui/**"]
  },
  "compositionRoots": ["lib/ui/composition.dart"],
  "generatedInfrastructure": ["lib/infrastructure/**/*.g.dart"],
  "generatedSuffixes": [".g.dart", ".dartitect.g.dart"],
  "suppressions": [
    {
      "code": "DT1001",
      "path": "lib/model/legacy.dart",
      "reason": "Reviewed compatibility shim",
      "owner": "architecture",
      "expiresAt": "2099-12-31"
    }
  ],
  "features": {"declarations": {}},
  "targets": {"platforms": ["android", "ios", "macos", "windows", "linux", "web"]},
  "storageContexts": {},
  "transports": {},
  "observability": {"provider": "none"},
  "scheduler": {"provider": "none"},
  "extensionSources": []
}
''');
    await _write(
      root,
      'lib/model/legacy.dart',
      "import 'package:flutter/widgets.dart';\n",
    );
    await _write(
      root,
      'lib/model/current.dart',
      "import 'package:flutter/widgets.dart';\n",
    );
    await _write(
      root,
      'lib/ui/composition.dart',
      "import 'package:dio/dio.dart';\n",
    );

    final scan = await ProjectScanner(root).scan();

    expect(scan.violations, hasLength(1));
    expect(scan.violations.single.path, 'lib/model/current.dart');
    expect(scan.capabilities, contains('explicit_composition'));
  });

  test('uses path segments and ignores nested tool caches', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-segments-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: sample\n');
    await _write(
      root,
      'lib/features/orders/presentation/order_widget.dart',
      'void build(BuildContext context) {}\n',
    );
    await _write(
      root,
      'tool/nested/.dart_tool/generated/bad.dart',
      "import 'package:provider/provider.dart';\n",
    );
    await _write(root, 'tool/vendor/pubspec.yaml', 'name: vendor\n');
    await _write(
      root,
      'tool/vendor/lib/bad.dart',
      "import 'package:provider/provider.dart';\n",
    );

    final scan = await ProjectScanner(root).scan();

    expect(scan.dartFileCount, 1);
    expect(scan.violations, isEmpty);
  });

  test(
    'conditional imports are checked and suppressions need a reason',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-conditional-',
      );
      addTearDown(() => root.delete(recursive: true));
      await _write(root, 'pubspec.yaml', 'name: sample\n');
      await _write(
        root,
        'lib/domain/conditional.dart',
        "import 'stub.dart' if (dart.library.ui) 'package:flutter/widgets.dart';\n",
      );
      await _write(
        root,
        'lib/domain/suppressed.dart',
        '// dartitect-ignore: DT1001 -- legacy boundary under review\n'
            "import 'package:flutter/widgets.dart';\n",
      );
      await _write(
        root,
        'lib/domain/unjustified.dart',
        '// dartitect-'
            'ignore: DT1001\n'
            "import 'package:flutter/widgets.dart';\n",
      );

      final scan = await ProjectScanner(root).scan();

      expect(
        scan.violations.where((finding) => finding.code == 'DT1001'),
        hasLength(2),
      );
      expect(scan.findings.map((finding) => finding.code), contains('DT0004'));
    },
  );

  test('baseline fingerprint is stable when only the line changes', () {
    const first = DartitectFinding(
      code: 'DT1001',
      severity: FindingSeverity.error,
      message: 'boundary',
      path: 'lib/a.dart',
      line: 1,
      evidence: 'package:flutter/widgets.dart',
    );
    const moved = DartitectFinding(
      code: 'DT1001',
      severity: FindingSeverity.error,
      message: 'boundary',
      path: 'lib/a.dart',
      line: 99,
      evidence: 'package:flutter/widgets.dart',
    );

    expect(fingerprintFinding(first), fingerprintFinding(moved));
  });

  test('workspace roots support Unicode and never follow symlinks', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-workspace-');
    final outside = await Directory.systemTemp.createTemp(
      'dartitect-workspace-outside-',
    );
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await _write(root, 'pubspec.yaml', '''name: sample_workspace
workspace:
  - packages/*
''');
    await _write(root, 'packages/café/pubspec.yaml', 'name: cafe\n');
    await _write(
      root,
      'packages/café/lib/features/orders/presentation/widget.dart',
      'void build(BuildContext context) {}\n',
    );
    await _write(root, 'packages/alpha/pubspec.yaml', 'name: alpha\n');
    await _write(
      root,
      'packages/alpha/lib/domain/violation.dart',
      "import 'package:flutter/widgets.dart';\n",
    );
    final outsideFile = File('${outside.path}/not_scanned.dart');
    await outsideFile.writeAsString("import 'package:flutter/widgets.dart';\n");
    if (!Platform.isWindows) {
      final link = Link('${root.path}/tool/outside.dart');
      await link.parent.create(recursive: true);
      await link.create(outsideFile.path);
    }

    final scan = await ProjectScanner(root).scan();

    expect(scan.dartFileCount, 2);
    expect(scan.violations, hasLength(1));
    expect(scan.violations.single.path, contains('packages/alpha/lib/domain'));
  });

  test('workspace packages use their own name and nearest config', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-monorepo-config-',
    );
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', '''name: sample_workspace
workspace:
  - packages/*
''');
    await _write(root, 'packages/app/pubspec.yaml', 'name: app\n');
    await _write(root, 'packages/app/dartitect.json', '''
{
  "configVersion": 2,
  "profile": "native_strict",
  "layers": {
    "domain": ["lib/domain/**"],
    "application": ["lib/application/**"],
    "data": ["lib/data/**"],
    "infrastructure": ["lib/infrastructure/**"],
    "presentation": ["lib/ui/**"]
  },
  "compositionRoots": ["lib/runtime/**"],
  "generatedInfrastructure": ["lib/infrastructure/**/*.g.dart"],
  "generatedSuffixes": [".g.dart", ".dartitect.g.dart"],
  "suppressions": [],
  "features": {"declarations": {}},
  "targets": {"platforms": ["android", "ios", "macos", "windows", "linux", "web"]},
  "storageContexts": {},
  "transports": {},
  "observability": {"provider": "none"},
  "scheduler": {"provider": "none"},
  "extensionSources": []
}
''');
    await _write(
      root,
      'packages/app/lib/ui/page.dart',
      'Widget buildPage() => throw UnimplementedError();\n',
    );
    await _write(
      root,
      'packages/app/lib/src/service.dart',
      'class Service {}\n',
    );
    await _write(
      root,
      'packages/app/lib/runtime/app_runtime.dart',
      "import 'package:app/src/service.dart';\nService create() => Service();\n",
    );

    final scan = await ProjectScanner(root).scan();

    expect(scan.dartFileCount, 3);
    expect(scan.findings, isEmpty);
    expect(scan.violations, isEmpty);
  });

  test('large declared root is scanned deterministically', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-large-');
    addTearDown(() => root.delete(recursive: true));
    await _write(root, 'pubspec.yaml', 'name: large_sample\n');
    for (var index = 0; index < 400; index += 1) {
      await _write(
        root,
        'lib/features/feature_$index/domain/value_$index.dart',
        'final value$index = $index;\n',
      );
    }

    final first = await ProjectScanner(root).scan();
    final second = await ProjectScanner(root).scan();

    expect(first.dartFileCount, 400);
    expect(first.violations, isEmpty);
    expect(second.dartFileCount, first.dartFileCount);
    expect(second.features, first.features);
    expect(second.findings, first.findings);
    expect(second.violations, first.violations);
  });

  test('unreadable roots produce a permission finding', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('dartitect-permission-');
    final restricted = Directory('${root.path}/lib/restricted');
    addTearDown(() async {
      await Process.run('chmod', <String>['700', restricted.path]);
      await root.delete(recursive: true);
    });
    await _write(root, 'pubspec.yaml', 'name: permission_sample\n');
    await _write(root, 'lib/restricted/value.dart', 'final value = 1;\n');
    final chmod = await Process.run('chmod', <String>['000', restricted.path]);
    expect(chmod.exitCode, 0);

    final scan = await ProjectScanner(root).scan();

    expect(scan.findings.map((finding) => finding.code), contains('DT0002'));
  });
}

Future<void> _write(Directory root, String relative, String content) async {
  final file = File(
    '${root.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}',
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<List<String>> _snapshot(Directory root) async {
  final entries = await root.list(recursive: true, followLinks: false).toList();
  return entries.map((entry) => entry.path).toList()..sort();
}
