import 'package:flutter_test/flutter_test.dart';

import '../bin/run_benchmarks.dart' as runner;

void main() {
  test('generate full same-runner benchmark artifacts', () async {
    final errors = await runner.generateBenchmarkArtifacts();
    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}
