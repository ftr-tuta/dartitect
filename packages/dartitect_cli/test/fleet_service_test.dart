import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('fleet versions is sorted, relative, and source sanitized', () async {
    final fleet = await _fleet();
    final beta = await _project(fleet, 'beta', '^1.0.0-rc.4');
    final alpha = await _project(fleet, 'alpha', '1.0.0-rc.4');
    await File('${beta.path}/pubspec.lock').writeAsString('''packages:
  dartitect:
    dependency: direct main
    source: hosted
    version: "1.0.0-rc.4"
''');

    final report = await DartitectFleetService(fleet)
        .versions(<String>['beta', 'alpha']);
    final encoded = jsonEncode(report.toJson());

    expect(report.projects.map((project) => project['root']), <String>[
      'alpha',
      'beta',
    ]);
    expect(encoded, isNot(contains(fleet.path)));
    expect(encoded, isNot(contains(alpha.absolute.path)));
    expect(encoded, contains('lockedVersion'));
    expect(report.projects.first['modelStatus'], isA<Map<String, Object?>>());
    expect(
      report.projects.first['providerStatus'],
      isA<Map<String, Object?>>(),
    );
  });

  test('fleet reports modeling and bounded provider adoption status', () async {
    final fleet = await _fleet();
    final app = await _project(fleet, 'app', '^1.0.0-rc.4');
    await File('${app.path}/pubspec.yaml').writeAsString('''name: app
dependencies:
  dartitect: ^1.0.0-rc.4
  dartitect_modeling: ^1.0.0-rc.4
  provider: any
''');
    final report = await DartitectFleetService(fleet).versions(<String>['app']);
    final project = report.projects.single;
    expect(project['modelStatus'], containsPair('status', 'dependency_only'));
    expect(project['providerStatus'], containsPair('status', 'none'));
  });

  test(
    'fleet report aggregates profiles, providers, and matrix coverage',
    () async {
      final fleet = await _fleet();
      final app = await _project(fleet, 'app', '^1.0.0-rc.4');
      await File('${app.path}/dartitect.json').writeAsString(
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
          features: DartitectFeaturesConfig(
            declarations: <String, DartitectFeatureDeclaration>{
              'orders': DartitectFeatureDeclaration(
                profile: FeatureProfile.offlineFull,
                scope: FeatureScope.application,
                storageContext: 'primary',
                transport: 'api',
                pagination: FeaturePagination.cursor,
                diagnostics: FeatureDiagnosticsLevel.full,
                headlessTargets: const <DartitectPlatform>[
                  DartitectPlatform.android,
                ],
              ),
            },
          ),
        ).encode(),
      );
      final tests = Directory('${app.path}/test')..createSync();
      await File('${tests.path}/contracts_test.dart').writeAsString('''
void registerMatrix() {
  FeatureContractMatrix.offlineFull(fixtures: fixtures);
}
''');

      final report = await DartitectFleetService(fleet).report(<String>['app']);
      final project = report.projects.single;
      expect(report.command, 'fleet report');
      expect(project['profiles'], <String>['offline-full']);
      expect(project['providers'], <String, Object?>{
        'persistence': <String>['drift'],
        'transport': <String>['dio'],
      });
      expect(project['contractMatrices'], containsPair('status', 'covered'));
    },
  );

  test(
    'fleet roots reject traversal, duplicates, and symlink escape',
    () async {
      final fleet = await _fleet();
      await _project(fleet, 'app', '^1.0.0-rc.4');
      final service = DartitectFleetService(fleet);

      await expectLater(
        service.versions(<String>['../app']),
        throwsFormatException,
      );
      await expectLater(
        service.versions(<String>['app', './app']),
        throwsFormatException,
      );
      final outside = await Directory.systemTemp.createTemp('fleet-outside-');
      addTearDown(() async {
        if (await outside.exists()) await outside.delete(recursive: true);
      });
      await File('${outside.path}/pubspec.yaml')
          .writeAsString('name: outside\n');
      await Link('${fleet.path}/escape').create(outside.path);
      await expectLater(
        service.versions(<String>['escape']),
        throwsFormatException,
      );
    },
  );

  test('fleet policy requires both bundle and policy digests', () async {
    final fleet = await _fleet();
    await _project(fleet, 'app', '^1.0.0-rc.4');
    final policy = File('${fleet.path}/policy.json');
    await policy.writeAsString('''{
  "schemaVersion": 3,
  "profile": "native_strict",
  "documentation": "policy.md",
  "decisions": {},
  "workspaceReviewedPackages": [],
  "exceptions": []
}
''');
    final policyDigest = sha256.convert(await policy.readAsBytes()).toString();
    final bundle = File('${fleet.path}/bundle.json');
    await bundle.writeAsString(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'bundleVersion': 'test.1', 'policyPath': 'policy.json', 'policySha256': policyDigest, 'blockUnreviewed': false})}\n',
    );
    final bundleDigest = sha256.convert(await bundle.readAsBytes()).toString();
    final service = DartitectFleetService(fleet);

    final report = await service.policy(
      <String>['app'],
      bundlePath: 'bundle.json',
      expectedSha256: bundleDigest,
    );

    expect(report.exitCode, 0);
    expect(report.policyBundle?['sha256'], bundleDigest);
    await expectLater(
      service.policy(
        <String>['app'],
        bundlePath: 'bundle.json',
        expectedSha256: '0' * 64,
      ),
      throwsFormatException,
    );
  });

  test(
    'fleet CLI previews RC6 upgrade and writes nothing by default',
    () async {
      final fleet = await _fleet();
      final app = await _project(fleet, 'app', '^1.0.0-rc.5');
      final before = await File('${app.path}/pubspec.yaml').readAsString();
      final output = StringBuffer();
      final errors = StringBuffer();
      final runner = DartitectCliRunner(
        currentDirectory: fleet,
        stdoutSink: output,
        stderrSink: errors,
      );

      expect(
        await runner.run(<String>[
          'fleet',
          'upgrade',
          'app',
          '--dry-run',
          '--to=1.0.0-rc.6',
          '--json',
        ]),
        0,
      );
      final decoded = jsonDecode(output.toString()) as Map<String, Object?>;
      final projects = decoded['projects']! as List<Object?>;
      final plan =
          (projects.single! as Map<String, Object?>)['plan']!
              as Map<String, Object?>;
      expect(plan['stateToken'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await File('${app.path}/pubspec.yaml').readAsString(), before);
      expect(errors.toString(), isEmpty);

      output.clear();
      expect(
        await runner.run(<String>[
          'fleet',
          'upgrade',
          'app',
          '--to=1.0.0-rc.6',
        ]),
        0,
      );
      expect(await File('${app.path}/pubspec.yaml').readAsString(), before);
    },
  );

  test('fleet apply commits only after allowlisted gates pass', () async {
    final fleet = await _fleet();
    final app = await _project(fleet, 'app', '^1.0.0-rc.5');
    final commands = <String>[];
    final service = DartitectFleetService(
      fleet,
      commandRunner: (root, executable, arguments) async {
        commands.add('$executable ${arguments.join(' ')}');
        return const DartitectFleetCommandResult(exitCode: 0);
      },
    );

    final report = await service.applyUpgrade(<String>[
      'app',
    ], targetCohort: '1.0.0-rc.6');

    expect(report.exitCode, 0);
    expect(
      await File('${app.path}/pubspec.yaml').readAsString(),
      contains('^1.0.0-rc.6'),
    );
    expect(commands, <String>['dart pub get', 'dart analyze', 'dart test']);
    expect(
      File('${app.path}/.dartitect/fleet-upgrade-receipt.json').existsSync(),
      isTrue,
    );
  });

  test('fleet failure restores every project and validates digests', () async {
    final fleet = await _fleet();
    final alpha = await _project(fleet, 'alpha', '^1.0.0-rc.5');
    final beta = await _project(fleet, 'beta', '^1.0.0-rc.5');
    final beforeAlpha = await File('${alpha.path}/pubspec.yaml').readAsBytes();
    final beforeBeta = await File('${beta.path}/pubspec.yaml').readAsBytes();
    final service = DartitectFleetService(
      fleet,
      commandRunner: (root, executable, arguments) async =>
          DartitectFleetCommandResult(
            exitCode: root.path.endsWith('beta') && arguments.first == 'analyze'
                ? 1
                : 0,
          ),
    );

    await expectLater(
      service.applyUpgrade(<String>[
        'beta',
        'alpha',
      ], targetCohort: '1.0.0-rc.6'),
      throwsFormatException,
    );
    expect(await File('${alpha.path}/pubspec.yaml').readAsBytes(), beforeAlpha);
    expect(await File('${beta.path}/pubspec.yaml').readAsBytes(), beforeBeta);
    expect(
      File('${fleet.path}/.dartitect/fleet-upgrade.transaction.json')
          .existsSync(),
      isFalse,
    );
  });
}

Future<Directory> _fleet() async {
  final root = await Directory.systemTemp.createTemp('dartitect-fleet-test-');
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  return root;
}

Future<Directory> _project(
  Directory fleet,
  String name,
  String constraint,
) async {
  final root = Directory('${fleet.path}/$name');
  await root.create();
  await File('${root.path}/pubspec.yaml').writeAsString('''name: $name
dependencies:
  dartitect: $constraint
''');
  return root;
}
