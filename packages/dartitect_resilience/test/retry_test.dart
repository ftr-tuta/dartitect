import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:test/test.dart';

void main() {
  test('retry executor bounds expected failures and injected delays', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 28));
    final scheduler = _Scheduler(clock);
    final cancellation = CancellationSource();
    var attempts = 0;
    final result =
        await RetryExecutor(
          clock: clock,
          scheduler: scheduler,
          random: const _Random(0.5),
        ).execute<int, _Failure>(
          operation: (attempt, signal) async {
            attempts = attempt;
            return attempt < 3
                ? Err<_Failure>(const _Failure.retryable(), StackTrace.empty)
                : const Ok<int>(7);
          },
          policy: RetryPolicy<_Failure>(
            maxAttempts: 4,
            maxElapsed: const Duration(seconds: 10),
            backoff: FixedBackoff(const Duration(seconds: 2)),
            jitter: const FullJitter(),
            classify: (failure) => failure.uncertain
                ? const RetryDecision.uncertain()
                : const RetryDecision.retry(),
          ),
          cancellation: cancellation.signal,
        );

    expect(result, const Ok<int>(7));
    expect(attempts, 3);
    expect(scheduler.delays, <Duration>[
      const Duration(seconds: 1),
      const Duration(seconds: 1),
    ]);
    cancellation.dispose();
  });

  test('uncertain expected failure is never retried', () async {
    final cancellation = CancellationSource();
    var attempts = 0;
    final result = await RetryExecutor().execute<int, _Failure>(
      operation: (_, _) async {
        attempts += 1;
        return Err<_Failure>(const _Failure.uncertain(), StackTrace.empty);
      },
      policy: RetryPolicy<_Failure>(
        classify: (_) => const RetryDecision.uncertain(),
      ),
      cancellation: cancellation.signal,
    );

    expect(result, isA<Err<_Failure>>());
    expect(attempts, 1);
    cancellation.dispose();
  });

  test('unexpected crash preserves its original stack', () async {
    final cancellation = CancellationSource();
    late StackTrace original;
    final future = RetryExecutor().execute<int, _Failure>(
      operation: (_, _) async {
        try {
          throw StateError('crash');
        } catch (_, stackTrace) {
          original = stackTrace;
          rethrow;
        }
      },
      policy: RetryPolicy<_Failure>(
        classify: (_) => const RetryDecision.retry(),
      ),
      cancellation: cancellation.signal,
    );

    await expectLater(
      future,
      throwsA(
        isA<StateError>().having(
          (_) => '$original',
          'original stack retained by future',
          isNotEmpty,
        ),
      ),
    );
    cancellation.dispose();
  });

  test('elapsed budget returns the last typed failure', () async {
    final clock = _Clock(DateTime.utc(2026, 8, 28));
    final cancellation = CancellationSource();
    var attempts = 0;
    final result =
        await RetryExecutor(
          clock: clock,
          scheduler: _Scheduler(clock),
        ).execute<int, _Failure>(
          operation: (_, _) async {
            attempts += 1;
            return Err<_Failure>(const _Failure.retryable(), StackTrace.empty);
          },
          policy: RetryPolicy<_Failure>(
            maxElapsed: const Duration(seconds: 1),
            backoff: FixedBackoff(const Duration(seconds: 2)),
            classify: (_) => const RetryDecision.retry(),
          ),
          cancellation: cancellation.signal,
        );
    expect(result, isA<Err<_Failure>>());
    expect(attempts, 1);
    cancellation.dispose();
  });
}

final class _Failure {
  const _Failure.retryable() : uncertain = false;
  const _Failure.uncertain() : uncertain = true;

  final bool uncertain;
}

final class _Clock implements ResilienceClock {
  _Clock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

final class _Scheduler implements ResilienceScheduler {
  _Scheduler(this.clock);

  final _Clock clock;
  final List<Duration> delays = <Duration>[];

  @override
  Future<void> wait(Duration delay, CancellationSignal cancellation) async {
    cancellation.throwIfCancelled();
    delays.add(delay);
    clock.current = clock.current.add(delay);
  }
}

final class _Random implements ResilienceRandom {
  const _Random(this.value);

  final double value;

  @override
  double nextDouble() => value;
}
