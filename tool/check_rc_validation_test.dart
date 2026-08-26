import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('accepts explicit fail-closed pre-validation records', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final result = await fixture.check(contractOnly: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('NOT_READY_FOR_1_0'));
  });

  test('rejects a nonzero residual target', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final contract = fixture.read('rc_validation_contract.json');
    contract['requiredResidualCensus'] = 1;
    await fixture.write('rc_validation_contract.json', contract);

    final result = await fixture.check(contractOnly: true);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('validation contract is incomplete'));
  });

  test(
    'formal gate rejects absent materialization and source identity',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.write('rc_readiness_decision.json', <String, Object?>{
        'sourceSha': null,
      });

      final result = await fixture.check();

      expect(result.exitCode, 1);
      expect(result.stderr, contains('materialized RC artifact gate failed'));
      expect(result.stderr, contains('RC source SHA is absent'));
    },
  );
}

final class _Fixture {
  const _Fixture(this.root);

  final Directory root;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-rc-validation-',
    );
    await Directory('${root.path}/tool').create(recursive: true);
    final fixture = _Fixture(root);
    for (final name in const <String>[
      'rc_validation_contract.json',
      'stable_readiness_decision.json',
    ]) {
      await File('${root.path}/tool/$name').writeAsString(
        File('${Directory.current.path}/tool/$name').readAsStringSync(),
      );
    }
    await fixture.write('goal_gates.json', <String, Object?>{
      'releaseStatus': 'NOT_READY_FOR_1_0_RC',
      'statusPolicy': <String, Object?>{
        'reviewAuthority': <String, Object?>{
          'kind': 'MAINTAINER_DELEGATED_AUTOMATION',
          'name': 'Codex',
        },
      },
    });
    await fixture.write('package_release_contract.json', <String, Object?>{
      'cohortVersion': '1.0.0-rc.1',
    });
    await fixture.write('rc_bundle_contract.json', <String, Object?>{
      'outputDirectory': 'build/rc-bundles',
    });
    return fixture;
  }

  Map<String, Object?> read(String name) =>
      jsonDecode(File('${root.path}/tool/$name').readAsStringSync())
          as Map<String, Object?>;

  Future<void> write(String name, Map<String, Object?> value) =>
      File('${root.path}/tool/$name').writeAsString(jsonEncode(value));

  Future<ProcessResult> check({bool contractOnly = false}) {
    final checker = '${Directory.current.path}/tool/check_rc_validation.dart';
    return Process.run(Platform.resolvedExecutable, <String>[
      checker,
      '--root',
      root.path,
      if (contractOnly) '--contract-only',
    ]);
  }

  Future<void> dispose() => root.delete(recursive: true);
}
