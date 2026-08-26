import 'dart:convert';
import 'dart:io';

/// Checks recorded 100/500 cold sync/check results against reviewed budgets.
void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final artifactFile = File('${root.path}/tool/model_benchmark.json');
  if (!artifactFile.existsSync()) {
    stderr.writeln('Model benchmark is missing; run with --record.');
    exitCode = 1;
    return;
  }
  final artifact =
      jsonDecode(artifactFile.readAsStringSync()) as Map<String, Object?>;
  final budget = jsonDecode(
    File('${root.path}/tool/model_benchmark_budget.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final results = (artifact['results']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final budgets = (budget['budgets']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final errors = <String>[];
  for (final expected in budgets) {
    final result = results
        .where(
          (row) =>
              row['models'] == expected['models'] &&
              row['command'] == expected['command'],
        )
        .singleOrNull;
    if (result == null || result['runs'] != budget['runs']) {
      errors.add(
        'Missing five-run result for ${expected['models']} ${expected['command']}.',
      );
      continue;
    }
    if ((result['medianMicros']! as int) >
        (expected['maxMedianMicros']! as int)) {
      errors.add(
        'Median budget exceeded for ${expected['models']} ${expected['command']}.',
      );
    }
    if ((result['peakRssBytes']! as int) >
        (expected['maxPeakRssBytes']! as int)) {
      errors.add(
        'RSS budget exceeded for ${expected['models']} ${expected['command']}.',
      );
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Model benchmark covers cold sync/check at 100/500 models within budget.',
  );
}

extension<T> on Iterable<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
