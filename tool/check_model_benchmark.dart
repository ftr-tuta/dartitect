import 'dart:convert';
import 'dart:io';

/// Checks the same-host legacy/RC5 modeling comparison and hard resource budgets.
void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final artifactFile = File('${root.path}/tool/model_benchmark.json');
  if (!artifactFile.existsSync()) {
    stderr.writeln('Model benchmark is missing; run with --record.');
    exitCode = 1;
    return;
  }
  final artifact = _object(jsonDecode(artifactFile.readAsStringSync()));
  final budget = _object(
    jsonDecode(
      File('${root.path}/tool/model_benchmark_budget.json').readAsStringSync(),
    ),
  );
  final errors = <String>[];
  final policy = _object(artifact['policy']);
  final baseline = _object(artifact['baseline']);
  final candidate = _object(artifact['candidate']);
  if (artifact['schemaVersion'] != 2 ||
      artifact['targetVersion'] != '1.0.0-rc.5' ||
      policy['coldRuns'] != 5 ||
      policy['warmRuns'] != 20 ||
      policy['maxRegressionPercent'] != 10.0 ||
      policy['cacheAuthority'] != false ||
      policy['sameHostRequired'] != true) {
    errors.add('Model benchmark policy is not the frozen RC5 contract.');
  }
  if (baseline['implementation'] != 'legacy-core-modeling' ||
      candidate['implementation'] != 'modular-modeling' ||
      jsonEncode(baseline['host']) != jsonEncode(candidate['host'])) {
    errors.add('Baseline and candidate are not comparable on the same host.');
  }

  final baselineResults = _objects(baseline['results']);
  final results = _objects(candidate['results']);
  final budgets = _objects(budget['budgets']);
  if (baselineResults.length != 4 || results.length != 4) {
    errors.add(
      'The 100/500 sync/check matrix must contain four rows per phase.',
    );
  }
  for (final expected in budgets) {
    final result = results
        .where(
          (row) =>
              row['models'] == expected['models'] &&
              row['command'] == expected['command'],
        )
        .singleOrNull;
    if (result == null) {
      errors.add(
        'Missing result for ${expected['models']} ${expected['command']}.',
      );
      continue;
    }
    final cold = _object(result['cold']);
    final warm = _object(result['warm']);
    if (cold['runs'] != 5 ||
        _objects(cold['samples']).length != 5 ||
        warm['runs'] != 20 ||
        _objects(warm['samples']).length != 20) {
      errors.add(
        'Incomplete cold/warm samples for '
        '${expected['models']} ${expected['command']}.',
      );
    }
    if ((cold['medianMicros']! as int) >
        (expected['maxMedianMicros']! as int)) {
      errors.add(
        'Median budget exceeded for ${expected['models']} '
        '${expected['command']}.',
      );
    }
    if ((cold['peakRssBytes']! as int) >
            (expected['maxPeakRssBytes']! as int) ||
        (warm['peakRssBytes']! as int) >
            (expected['maxPeakRssBytes']! as int)) {
      errors.add(
        'RSS budget exceeded for ${expected['models']} '
        '${expected['command']}.',
      );
    }
  }
  for (final comparison in _objects(artifact['comparisons'])) {
    final baselineRow = baselineResults
        .where(
          (row) =>
              row['models'] == comparison['models'] &&
              row['command'] == comparison['command'],
        )
        .singleOrNull;
    final candidateRow = results
        .where(
          (row) =>
              row['models'] == comparison['models'] &&
              row['command'] == comparison['command'],
        )
        .singleOrNull;
    if (baselineRow == null || candidateRow == null) {
      errors.add('Comparison does not identify one measured matrix cell.');
      continue;
    }
    final baselineCold = _object(baselineRow['cold']);
    final candidateCold = _object(candidateRow['cold']);
    final baselineWarm = _object(baselineRow['warm']);
    final candidateWarm = _object(candidateRow['warm']);
    final recomputed = <String, double>{
      'coldMedianMicros': _delta(
        baselineCold['medianMicros']! as int,
        candidateCold['medianMicros']! as int,
      ),
      'coldPeakRssBytes': _delta(
        baselineCold['peakRssBytes']! as int,
        candidateCold['peakRssBytes']! as int,
      ),
      'warmP95Micros': _delta(
        baselineWarm['p95Micros']! as int,
        candidateWarm['p95Micros']! as int,
      ),
      'warmPeakRssBytes': _delta(
        baselineWarm['peakRssBytes']! as int,
        candidateWarm['peakRssBytes']! as int,
      ),
    };
    final recorded = _object(comparison['regressionPercent']);
    if (jsonEncode(recorded) != jsonEncode(recomputed)) {
      errors.add(
        'Recorded regression differs from measured bytes for '
        '${comparison['models']} ${comparison['command']}.',
      );
    }
    final passes = recomputed.values.every((value) => value <= 10.0);
    if (comparison['status'] != (passes ? 'pass' : 'review-required')) {
      errors.add('Comparison status does not match the recomputed regression.');
    }
    if (!passes) {
      errors.add(
        'Unapproved >10% regression for ${comparison['models']} '
        '${comparison['command']}: ${comparison['regressionPercent']}.',
      );
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Model benchmark passes: same-host legacy/RC5, five cold medians/RSS, '
    'twenty warm p95/RSS, hard budgets, and the 10% regression gate.',
  );
}

double _delta(int baseline, int candidate) => double.parse(
  (((candidate - baseline) / baseline) * 100).toStringAsFixed(3),
);

Map<String, Object?> _object(Object? value) =>
    (value as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value as List<Object?>).map(_object).toList();

extension<T> on Iterable<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
