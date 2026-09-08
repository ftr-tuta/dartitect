import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';

Future<void> main() async {
  final cancellation = CancellationSource();
  final bulkhead = Bulkhead(maxConcurrent: 2, maxQueue: 4);
  final budget = RetryBudget(
    maxAttempts: 8,
    maxElapsed: const Duration(seconds: 30),
    bulkhead: bulkhead,
    rateLimiter: RateLimiter(
      capacity: 4,
      refillTokens: 1,
      refillPeriod: const Duration(seconds: 1),
    ),
  );
  final hint = RetryAfterParser(maximumDelay: const Duration(seconds: 20))
      .parse('5', receivedAt: DateTime.now().toUtc());
  final executor = RetryExecutor();
  await executor.execute<int, StateError>(
    operation: (_, _) async => const Ok<int>(1),
    policy: RetryPolicy<StateError>(
      classify: (_) => RetryDecision.retry(retryAfter: hint),
    ),
    cancellation: cancellation.signal,
    budget: budget,
  );
  await bulkhead.disposeAsync();
  cancellation.dispose();
}
