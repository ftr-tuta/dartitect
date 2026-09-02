import 'dart:convert';
import 'dart:io';

const _expectedScales = <int>[0, 1, 32, 1000, 100000];
const _expectedShapes = <String>{
  'eager',
  'sync-generator',
  'async-generator',
  'batches',
};
const _expectedBlockingGates = <String>{
  'bounded-admission',
  'consumer-backpressure',
  'cleanup-before-terminal',
  'stable-public-order',
  'single-flight-borrowed-ports',
  'one-classification-per-node',
  'zero-residual-work',
  'deterministic-scan-events',
};
const _expectedInformativeMetrics = <String>{
  'firstItemMicros',
  'totalMicros',
  'rssBytes',
  'p50Micros',
  'p95Micros',
};
const _expectedSlices = <String, String>{
  'core':
      'packages/dartitect/benchmark/incremental_operation_benchmark_test.dart',
  'flutter': 'packages/dartitect_flutter/benchmark/incremental_command_benchmark_test.dart',
  'sync':
      'packages/dartitect_sync/benchmark/incremental_sync_benchmark_test.dart',
  'isolates':
      'packages/dartitect_isolates/benchmark/worker_pool_benchmark_test.dart',
  'observability': 'packages/dartitect_observability/benchmark/privacy_fanout_benchmark_test.dart',
  'cli':
      'packages/dartitect_cli/benchmark/progressive_scan_benchmark_test.dart',
};

Future<void> main(List<String> arguments) async {
  final root = _root(arguments);
  final contractFile = File(
    '${root.path}/tool/incremental_benchmark_contract.json',
  );
  if (!await contractFile.exists()) {
    stderr.writeln('Incremental benchmark contract is missing.');
    exitCode = 1;
    return;
  }
  final decoded = jsonDecode(await contractFile.readAsString());
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('Incremental benchmark contract must be an object.');
    exitCode = 1;
    return;
  }
  final errors = validateIncrementalBenchmarkContract(decoded);
  final slices = decoded['slices'];
  if (slices is Map<String, Object?>) {
    for (final expected in _expectedSlices.entries) {
      final slice = slices[expected.key];
      if (slice is! Map<String, Object?>) continue;
      final path = slice['path'];
      final evidence = slice['evidence'];
      if (path is! String || evidence is! List<Object?>) continue;
      final sourceFile = File('${root.path}/$path');
      if (!await sourceFile.exists()) {
        errors.add('Missing ${expected.key} benchmark source: $path.');
        continue;
      }
      final source = await sourceFile.readAsString();
      for (final token in evidence.whereType<String>()) {
        if (!source.contains(token)) {
          errors.add('${expected.key} benchmark lacks evidence: $token.');
        }
      }
    }
  }

  final verify = await File('${root.path}/tool/verify.dart').readAsString();
  for (final path in _expectedSlices.values) {
    if (!verify.contains(path)) {
      errors.add('Full verification does not execute $path.');
    }
  }
  if (!verify.contains('tool/check_incremental_benchmark.dart')) {
    errors.add('Full verification omits the incremental benchmark checker.');
  }
  final releaseAudit = await File('${root.path}/tool/release_audit.dart')
      .readAsString();
  if (!releaseAudit.contains('tool/check_incremental_benchmark.dart')) {
    errors.add('Release audit omits the incremental benchmark checker.');
  }

  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Incremental benchmark contract passed: 5 scales, 4 input shapes, '
    '6 runtime slices, structural gates, and same-runner metric policy.',
  );
}

/// Validates the portable matrix and metric policy without running benchmarks.
List<String> validateIncrementalBenchmarkContract(
  Map<String, Object?> contract,
) {
  final errors = <String>[];
  if (contract['schemaVersion'] != 1 ||
      contract['matrixKind'] != 'curated-not-cartesian') {
    errors.add('Incremental benchmark schema or matrix kind changed.');
  }
  if (!_sameList(contract['emissionScales'], _expectedScales)) {
    errors.add('Incremental benchmark scales must be 0/1/32/1000/100000.');
  }
  if (!_sameStringSet(contract['inputShapes'], _expectedShapes)) {
    errors.add('Incremental benchmark input shapes are incomplete.');
  }
  if (!_sameStringSet(contract['blockingGates'], _expectedBlockingGates)) {
    errors.add('Incremental structural blocking gates changed.');
  }
  if (!_sameStringSet(
    contract['informativeMetrics'],
    _expectedInformativeMetrics,
  )) {
    errors.add('Incremental informative metrics changed.');
  }
  if (contract['comparisonPolicy'] != 'same-runner-only') {
    errors.add('Incremental metric comparisons must remain same-runner-only.');
  }
  final slices = contract['slices'];
  if (slices is! Map<String, Object?> ||
      !_sameStrings(slices.keys.toSet(), _expectedSlices.keys.toSet())) {
    errors.add('Incremental benchmark slices are incomplete.');
    return errors;
  }
  for (final expected in _expectedSlices.entries) {
    final slice = slices[expected.key];
    if (slice is! Map<String, Object?> ||
        slice['path'] != expected.value ||
        slice['evidence'] is! List<Object?> ||
        (slice['evidence']! as List<Object?>).isEmpty ||
        (slice['evidence']! as List<Object?>).any(
          (value) => value is! String,
        )) {
      errors.add('Invalid ${expected.key} incremental benchmark slice.');
    }
  }
  return errors;
}

bool _sameList(Object? actual, List<int> expected) =>
    actual is List<Object?> &&
    actual.length == expected.length &&
    Iterable<int>.generate(expected.length)
        .every((index) => actual[index] == expected[index]);

bool _sameStringSet(Object? actual, Set<String> expected) =>
    actual is List<Object?> &&
    actual.every((value) => value is String) &&
    _sameStrings(actual.whereType<String>().toSet(), expected);

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

Directory _root(List<String> arguments) {
  if (arguments.isEmpty) {
    return File.fromUri(Platform.script).parent.parent.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments.last).absolute;
  }
  throw const FormatException(
    'Usage: dart run tool/check_incremental_benchmark.dart [--root PATH]',
  );
}
