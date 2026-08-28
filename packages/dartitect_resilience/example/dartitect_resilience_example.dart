import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';

Future<void> main() async {
  final cancellation = CancellationSource();
  final executor = RetryExecutor();
  await executor.execute<int, StateError>(
    operation: (_, _) async => const Ok<int>(1),
    policy: RetryPolicy<StateError>(
      classify: (_) => const RetryDecision.stop(),
    ),
    cancellation: cancellation.signal,
  );
  cancellation.dispose();
}
