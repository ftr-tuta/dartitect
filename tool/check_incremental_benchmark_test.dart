import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'check_incremental_benchmark.dart';

void main() {
  test('accepts the curated structural benchmark matrix', () async {
    final contract = await _contract();

    expect(validateIncrementalBenchmarkContract(contract), isEmpty);
  });

  test('rejects a cross-runner timing gate', () async {
    final contract = await _contract();
    contract['comparisonPolicy'] = 'absolute-p95-gate';

    expect(
      validateIncrementalBenchmarkContract(contract),
      contains('Incremental metric comparisons must remain same-runner-only.'),
    );
  });

  test('rejects a missing edge scale or runtime slice', () async {
    final contract = await _contract();
    (contract['emissionScales']! as List<Object?>).remove(0);
    (contract['slices']! as Map<String, Object?>).remove('cli');

    expect(
      validateIncrementalBenchmarkContract(contract),
      containsAll(<String>[
        'Incremental benchmark scales must be 0/1/32/1000/100000.',
        'Incremental benchmark slices are incomplete.',
      ]),
    );
  });
}

Future<Map<String, Object?>> _contract() async => jsonDecode(
  await File('tool/incremental_benchmark_contract.json').readAsString(),
) as Map<String, Object?>;
