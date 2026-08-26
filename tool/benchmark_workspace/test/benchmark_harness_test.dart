import 'package:dartitect_benchmark_workspace/benchmark_harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reduced matrix preserves equivalent work and releases resources',
    () async {
      final result = await runBenchmarkSuite(warmupSamples: 1, repetitions: 3);

      expect(result['fanout'], hasLength(36));
      expect(result['collections'], hasLength(3));
      expect((result['raceFuzz']! as Map<String, Object?>)['steps'], 1000);
      expect(
        (result['resourceCensus']! as Map<String, int>).values,
        everyElement(0),
      );
    },
  );
}
