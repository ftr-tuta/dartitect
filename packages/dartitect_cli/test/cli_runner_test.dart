import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:dartitect_cli/src/codex/skill_catalog.dart';
import 'package:test/test.dart';

void main() {
  test('inspect JSON uses schema v1 and relative project paths', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-cli-json-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    final output = StringBuffer();
    final errors = StringBuffer();

    final exitCode = await DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    ).run(<String>['inspect', '--json']);
    final json = jsonDecode(output.toString()) as Map<String, Object?>;

    expect(exitCode, 0);
    expect(json['schemaVersion'], 1);
    expect(json['command'], 'inspect');
    expect((json['project'] as Map<String, Object?>)['root'], '.');
    expect(output.toString(), isNot(contains(root.path)));
    expect(errors.toString(), isEmpty);
  });

  test('scan SARIF is stable, relative, and omits source evidence', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-cli-sarif-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    final source = File('${root.path}/lib/domain/account.dart');
    await source.parent.create(recursive: true);
    await source.writeAsString('''
// customer-secret-value
import 'package:flutter/widgets.dart';
''');
    final output = StringBuffer();
    final errors = StringBuffer();

    final exitCode = await DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    ).run(<String>['scan', '--sarif']);
    final report = jsonDecode(output.toString()) as Map<String, Object?>;
    final runs = report['runs']! as List<Object?>;
    final run = runs.single! as Map<String, Object?>;
    final results = run['results']! as List<Object?>;
    final result = results.cast<Map<String, Object?>>().firstWhere(
      (entry) => entry['ruleId'] == 'DT1001',
    );
    final locations = result['locations']! as List<Object?>;
    final location = locations.single! as Map<String, Object?>;
    final physical = location['physicalLocation']! as Map<String, Object?>;
    final artifact = physical['artifactLocation']! as Map<String, Object?>;

    expect(exitCode, 1);
    expect(report[r'$schema'], contains('sarif-2.1.0'));
    expect(report['version'], '2.1.0');
    expect(run['automationDetails'], containsPair('id', 'dartitect/scan'));
    expect(artifact['uri'], 'lib/domain/account.dart');
    expect(output.toString(), isNot(contains(root.path)));
    expect(output.toString(), isNot(contains('customer-secret-value')));
    expect(output.toString(), isNot(contains('evidence')));
    expect(errors.toString(), isEmpty);
  });

  test('scan rejects simultaneous JSON and SARIF output', () async {
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      stdoutSink: StringBuffer(),
      stderrSink: errors,
    );

    expect(await runner.run(<String>['scan', '--json', '--sarif']), 2);
    expect(errors.toString(), contains('mutually exclusive'));
  });

  test('init dry-run previews and init never overwrites', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-cli-init-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    );

    expect(await runner.run(<String>['init', '--dry-run']), 0);
    expect(await File('${root.path}/dartitect.json').exists(), isFalse);
    expect(await runner.run(<String>['init']), 0);
    final original = await File('${root.path}/dartitect.json').readAsString();
    expect(await runner.run(<String>['init']), 0);
    expect(await File('${root.path}/dartitect.json').readAsString(), original);
  });

  test('unknown command and flag return stable usage code', () async {
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      stdoutSink: StringBuffer(),
      stderrSink: errors,
    );

    expect(await runner.run(<String>['unknown']), 2);
    expect(await runner.run(<String>['scan', '--wat']), 2);
    expect(errors.toString(), contains('Unknown'));
  });

  test('doctor validates Android and iOS launch resources read-only', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-splash-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    await Directory('${root.path}/android').create();
    await Directory('${root.path}/ios').create();
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    );

    expect(await runner.run(<String>['doctor', '--json']), 1);
    expect(output.toString(), contains('DT1024'));
    expect(output.toString(), contains('DT1025'));
    expect(
      await File(
        '${root.path}/android/app/src/main/res/drawable/launch_background.xml',
      ).exists(),
      isFalse,
    );
  });

  test('release doctor rejects an explicit memory storage context', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-release-memory-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    await File('${root.path}/dartitect.json').writeAsString(
      DartitectConfig(
        suppressions: <DartitectSuppression>[
          DartitectSuppression(
            code: 'DT1001',
            path: 'lib/domain/**',
            reason: 'Temporary fixture exception',
            owner: 'fixture',
            expiresAt: DateTime.utc(2099, 12, 31),
          ),
        ],
        targets: DartitectTargetsConfig(const <DartitectPlatform>[
          DartitectPlatform.android,
        ]),
        storageContexts: <String, DartitectStorageContextConfig>{
          'preview': DartitectStorageContextConfig(
            provider: 'memory',
            mode: DartitectStorageMode.memory,
            targets: const <DartitectPlatform>[DartitectPlatform.android],
          ),
        },
        features: DartitectFeaturesConfig(
          declarations: <String, DartitectFeatureDeclaration>{
            'notes': DartitectFeatureDeclaration(
              profile: FeatureProfile.local,
              scope: FeatureScope.application,
              storageContext: 'preview',
              dataset: DartitectStorageDatasetConfig.forFeature('notes'),
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.off,
            ),
          },
        ),
      ).encode(),
    );
    final output = StringBuffer();

    expect(
      await DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: StringBuffer(),
      ).run(<String>['doctor', '--release', '--json']),
      1,
    );
    expect(output.toString(), contains('DT2103'));
    expect(output.toString(), contains('DT2104'));
    expect(output.toString(), contains('/storageContexts/preview/mode'));
  });

  test('release doctor rejects inline suppressions without config', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-release-suppression-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    final source = File('${root.path}/lib/domain/value.dart');
    await source.parent.create(recursive: true);
    await source.writeAsString('''
// dartitect-ignore: DT1001 -- temporary release fixture
import 'package:flutter/widgets.dart';
''');
    final output = StringBuffer();

    expect(
      await DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: StringBuffer(),
      ).run(<String>['doctor', '--release', '--json']),
      1,
    );
    expect(output.toString(), contains('DT2104'));
  });

  test('scan is always strict and baseline commands are rejected', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-baseline-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
    await Directory('${root.path}/lib/domain').create(recursive: true);
    await File('${root.path}/lib/domain/a.dart')
        .writeAsString("import 'package:flutter/widgets.dart';\n");
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    );

    expect(await runner.run(<String>['scan']), 1);
    expect(await runner.run(<String>['baseline', 'create']), 2);
    expect(await runner.run(<String>['scan', '--no-baseline']), 2);
  });

  test('codex sync is idempotent and preserves existing AGENTS.md', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-codex-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/AGENTS.md').writeAsString('consumer owned\n');
    final output = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    );

    expect(await runner.run(<String>['codex', 'sync']), 0);
    expect(await runner.run(<String>['codex', 'sync']), 0);
    expect(
      await File('${root.path}/AGENTS.md').readAsString(),
      'consumer owned\n',
    );
    expect(
      output.toString(),
      contains('NO-OP .agents/skills/dartitect-runtime'),
    );
    expect(
      RegExp(
        r'^NO-OP \.agents/skills/dartitect-',
        multiLine: true,
      ).allMatches(output.toString()),
      hasLength(dartitectSkillCatalog.length),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'codex Flutter setup requires one mode and remains catalog-only',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dartitect-codex-setup-',
      );
      addTearDown(() => root.delete(recursive: true));
      final editor = File('${root.path}/.vscode/mcp.json');
      await editor.parent.create(recursive: true);
      await editor.writeAsString('{"external":true}\n');
      final output = StringBuffer();
      final errors = StringBuffer();
      final runner = DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: errors,
      );

      expect(await runner.run(<String>['codex', 'setup', '--flutter']), 2);
      expect(
        await runner.run(<String>[
          'codex',
          'setup',
          '--flutter',
          '--dry-run',
          '--apply',
        ]),
        2,
      );
      expect(
        await runner.run(<String>['codex', 'setup', '--flutter', '--apply']),
        0,
      );
      output.clear();
      expect(
        await runner.run(<String>['codex', 'setup', '--flutter', '--dry-run']),
        0,
      );

      expect(
        RegExp(
          r'^NO-OP \.agents/skills/dartitect-',
          multiLine: true,
        ).allMatches(output.toString()),
        hasLength(16),
      );
      expect(output.toString(), contains('codex plugin add dart-flutter'));
      expect(await File('${root.path}/AGENTS.md').exists(), isFalse);
      expect(await editor.readAsString(), '{"external":true}\n');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('create app requires targets and rejects productive defaults', () async {
    final root = await Directory.systemTemp.createTemp('dartitect-app-');
    addTearDown(() => root.delete(recursive: true));
    final output = StringBuffer();
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    );

    expect(
      await runner.run(<String>['create', 'app', 'sample', '--dry-run']),
      2,
    );
    expect(errors.toString(), contains('--targets is required'));
    errors.clear();

    expect(
      await runner.run(<String>[
        'create',
        'app',
        'sample',
        '--targets=android,web',
        '--transport=dio',
        '--dry-run',
      ]),
      2,
    );
    expect(errors.toString(), contains('valid only for create feature'));
    errors.clear();

    expect(
      await runner.run(<String>[
        'create',
        'app',
        'sample',
        '--targets=android,web',
        '--dry-run',
      ]),
      0,
    );
    expect(output.toString(), contains('TARGETS android,web'));
    expect(output.toString(), isNot(contains('EXAMPLE')));
    expect(errors.toString(), isEmpty);
  });

  test(
    'create feature accepts paved-road profile and provider options',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-profile-');
      addTearDown(() => root.delete(recursive: true));
      await _prepareSemanticPackage(root);
      await _writeCliContextFactories(root);
      await File('${root.path}/dartitect.json').writeAsString(
        DartitectConfig(
          storageContexts: <String, DartitectStorageContextConfig>{
            'primary': DartitectStorageContextConfig(
              provider: 'drift',
              mode: DartitectStorageMode.durable,
              targets: const <DartitectPlatform>[DartitectPlatform.android],
            ),
          },
          transports: <String, DartitectTransportConfig>{
            'api': DartitectTransportConfig(
              provider: 'dio',
              targets: const <DartitectPlatform>[DartitectPlatform.android],
            ),
          },
          scheduler: DartitectSchedulerConfig(provider: 'workmanager'),
        ).encode(),
      );
      final output = StringBuffer();
      final errors = StringBuffer();
      final runner = DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: output,
        stderrSink: errors,
      );

      final exitCode = await runner.run(<String>[
        'create',
        'feature',
        'orders',
        '--profile=offline-full',
        '--storage-context=primary',
        '--transport=api',
        '--pagination=cursor',
        '--headless-targets=android',
        '--diagnostics=full',
        '--dry-run',
      ]);

      expect(exitCode, 0, reason: errors.toString());
      expect(output.toString(), contains('orders.wiring.dartitect.g.dart'));
      expect(output.toString(), contains('orders_cursor_page.dart'));
      expect(output.toString(), contains('orders_headless_sync.dart'));
      expect(errors.toString(), isEmpty);
      expect(
        Directory('${root.path}/lib/features/orders').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'create feature rejects incompatible profile provider options',
    () async {
      final root = await Directory.systemTemp.createTemp('dartitect-profile-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/pubspec.yaml').writeAsString('name: sample\n');
      final errors = StringBuffer();
      final runner = DartitectCliRunner(
        currentDirectory: root,
        stdoutSink: StringBuffer(),
        stderrSink: errors,
      );

      expect(
        await runner.run(<String>[
          'create',
          'feature',
          'orders',
          '--profile=online',
          '--storage-context=primary',
          '--transport=api',
          '--dry-run',
        ]),
        2,
      );
      expect(errors.toString(), contains('online profiles require'));
    },
  );

  test('contracts check and sync use stable preview/apply semantics', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-contract-cli-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/api.json').writeAsString(jsonEncode(_cliContract));
    final output = StringBuffer();
    final errors = StringBuffer();
    final runner = DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: errors,
    );

    expect(
      await runner.run(<String>['contracts', 'sync', 'api.json', '--json']),
      1,
    );
    expect(jsonDecode(output.toString()), containsPair('applied', false));
    output.clear();

    expect(
      await runner.run(<String>[
        'contracts',
        'sync',
        'api.json',
        '--apply',
        '--json',
      ]),
      0,
    );
    expect(jsonDecode(output.toString()), containsPair('applied', true));
    output.clear();

    expect(
      await runner.run(<String>['contracts', 'check', 'api.json', '--json']),
      0,
    );
    expect(jsonDecode(output.toString()), containsPair('fresh', true));
    expect(errors.toString(), isEmpty);
  });
}

Future<void> _prepareSemanticPackage(Directory root) async {
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: sample
environment:
  sdk: ^3.13.0
''');
  var packageRoot = Directory.current.absolute;
  while (!File('${packageRoot.path}/.dart_tool/package_config.json')
      .existsSync()) {
    if (packageRoot.parent.path == packageRoot.path) {
      throw StateError('Workspace package_config.json was not found.');
    }
    packageRoot = packageRoot.parent;
  }
  final source = File('${packageRoot.path}/.dart_tool/package_config.json');
  final config =
      jsonDecode(await source.readAsString()) as Map<String, Object?>;
  final sourcePackages = config['packages']! as List<Object?>;
  final packages = <Object?>[
    <String, Object?>{
      'name': 'sample',
      'rootUri': '../',
      'packageUri': 'lib/',
      'languageVersion': '3.13',
    },
    for (final value in sourcePackages)
      if ((value! as Map<String, Object?>)['name'] != 'sample')
        <String, Object?>{
          ...(value as Map<String, Object?>),
          'rootUri': source.uri.resolve(value['rootUri']! as String).toString(),
        },
  ];
  final target = File('${root.path}/.dart_tool/package_config.json');
  await target.parent.create(recursive: true);
  await target.writeAsString(
    jsonEncode(<String, Object?>{...config, 'packages': packages}),
  );
}

Future<void> _writeCliContextFactories(Directory root) async {
  final directory = Directory('${root.path}/lib/composition');
  await directory.create(recursive: true);
  await File('${directory.path}/storage_context_factory.dart').writeAsString('''
import 'package:dartitect/dartitect.dart';

final class StorageContext {}

@DartitectApplicationContextFactory('primary')
final class StorageContextFactory {
  Future<StorageContext> open() async => StorageContext();
  Future<void> dispose(StorageContext context) async {}
}
''');
  await File('${directory.path}/transport_context_factory.dart')
      .writeAsString('''
import 'package:dartitect/dartitect.dart';

final class TransportContext {}

@DartitectTransportContextFactory('api')
final class TransportContextFactory {
  Future<TransportContext> open() async => TransportContext();
  Future<void> dispose(TransportContext context) async {}
}
''');
}

const _cliContract = <String, Object?>{
  'openapi': '3.1.0',
  'info': <String, Object?>{'title': 'CLI contract', 'version': '1'},
  'paths': <String, Object?>{},
  'components': <String, Object?>{
    'schemas': <String, Object?>{
      'Message': <String, Object?>{
        'type': 'object',
        'required': <Object?>['value'],
        'properties': <String, Object?>{
          'value': <String, Object?>{'type': 'string'},
        },
      },
    },
  },
};
