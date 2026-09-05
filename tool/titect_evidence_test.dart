import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/titect_evidence_fixture.dart';
import 'titect_evidence.dart';

void main() {
  late Directory root;
  const sha = '1111111111111111111111111111111111111111';
  const tree = '2222222222222222222222222222222222222222';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('titect-evidence-test-');
    await createTitectEvidenceFixture(
      root: root,
      artifactRoot: root,
      sha: sha,
      tree: tree,
    );
  });
  tearDown(() => root.delete(recursive: true));
  void validate() => validateTitectEvidence(
    root: root,
    evidence: Directory('${root.path}/titect'),
    sourceSha: sha,
    sourceTree: tree,
    runId: 123,
    runAttempt: 1,
  );
  void change(String path, void Function(Map<String, Object?>) mutate) {
    final file = File('${root.path}/$path');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    mutate(data);
    file.writeAsStringSync(jsonEncode(data));
  }

  test(
    'accepts exact complete synthetic evidence',
    () => expect(validate, returnsNormally),
  );
  test('rejects a missing report', () {
    File('${root.path}/titect/recovery.json').deleteSync();
    expect(validate, throwsStateError);
  });
  test('rejects altered outcome bytes', () {
    File('${root.path}/titect/vm.json').writeAsStringSync('[]');
    expect(validate, throwsStateError);
  });
  test('deliberate wire vector drift invalidates the evidence', () {
    File('${root.path}/tool/titect_fixture/vectors.json')
        .writeAsStringSync('[{}]');
    expect(validate, throwsStateError);
  });
  for (final entry in {
    'preliminary': true,
    'trackedTreeDirty': true,
    'dartitectSha': '0' * 40,
    'sourceTree': '0' * 40,
    'pythonSha': '0' * 40,
    'dartitectVersion': '0.0.0',
    'pytitectVersion': '0.0.0',
    'runId': 456,
    'runAttempt': 2,
    'status': 'divergent',
    'unresolvedContracts': ['undefined'],
  }.entries) {
    test('rejects conformance ${entry.key} mismatch', () {
      change(
        'titect/conformance.json',
        (value) => value[entry.key] = entry.value,
      );
      expect(validate, throwsStateError);
    });
  }
  test('rejects a preliminary Python pin even with passing reports', () {
    change(
      'tool/titect_fixture/pin.json',
      (value) => value['integrated'] = false,
    );
    expect(validate, throwsStateError);
  });
  test('rejects missing or repeated recovery scenarios', () {
    change(
      'titect/recovery.json',
      (value) => value['scenarios'] = [
        for (final _ in titectRecoveryScenarios)
          {'name': 'paired-storm', 'passed': true},
      ],
    );
    expect(validate, throwsStateError);
  });
  test('rejects residual resources', () {
    change(
      'titect/recovery.json',
      (value) =>
          (value['residualResources']!
                  as Map<String, Object?>)['activeAuthorities'] =
              1,
    );
    expect(validate, throwsStateError);
  });
}
