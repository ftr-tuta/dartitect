import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('fleet versions is sorted, relative, and source sanitized', () async {
    final fleet = await _fleet();
    final beta = await _project(fleet, 'beta', '^1.0.0-rc.3');
    final alpha = await _project(fleet, 'alpha', '1.0.0-rc.3');
    await File('${beta.path}/pubspec.lock').writeAsString('''packages:
  dartitect:
    dependency: direct main
    source: hosted
    version: "1.0.0-rc.3"
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
  });

  test(
    'fleet roots reject traversal, duplicates, and symlink escape',
    () async {
      final fleet = await _fleet();
      await _project(fleet, 'app', '^1.0.0-rc.3');
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
    await _project(fleet, 'app', '^1.0.0-rc.3');
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

  test('fleet CLI permits upgrade preview only and writes nothing', () async {
    final fleet = await _fleet();
    final app = await _project(fleet, 'app', '^1.0.0-rc.2');
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
        '--to=1.0.0-rc.3',
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

    expect(
      await runner.run(<String>['fleet', 'upgrade', 'app', '--to=1.0.0-rc.3']),
      2,
    );
    expect(await File('${app.path}/pubspec.yaml').readAsString(), before);
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
