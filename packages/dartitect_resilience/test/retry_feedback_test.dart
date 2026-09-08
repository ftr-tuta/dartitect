import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:test/test.dart';

void main() {
  test('bulkhead reserves capacity before consumer reentry', () async {
    final bulkhead = Bulkhead(maxConcurrent: 1, maxQueue: 0);
    await bulkhead.run((_) async {
      expect(
        () => bulkhead.run((_) async => 42),
        throwsA(isA<BulkheadRejectedException>()),
      );
    });
    await bulkhead.disposeAsync();
    expect(bulkhead.peakRunningCount, 1);
    expect(bulkhead.admittedCount, 1);
    expect(bulkhead.rejectedCount, 1);
    expect(bulkhead.runningCount, 0);
  });

  final receipt = DateTime.utc(1994, 11, 6, 8, 49, 30);
  final parser = RetryAfterParser(maximumDelay: const Duration(days: 1));

  test('seconds, HTTP whitespace, absence and closed numeric grammar', () {
    expect(parser.parse(null, receivedAt: receipt).kind, RetryAfterKind.absent);
    for (final field in ['0', '000', ' 0\t']) {
      expect(
        parser.parse(field, receivedAt: receipt).minimumDelay,
        Duration.zero,
      );
    }
    for (final field in [
      '',
      ' ',
      '-1',
      '+1',
      '1.0',
      '1e3',
      '1, 2',
      '١',
      '1\n',
      '\u00a01',
    ]) {
      expect(
        parser.parse(field, receivedAt: receipt).kind,
        RetryAfterKind.invalid,
        reason: field,
      );
    }
    expect(
      parser.parse('86400', receivedAt: receipt).minimumDelay,
      const Duration(days: 1),
    );
    for (final field in ['86401', '9' * 100, '0' * 129]) {
      expect(
        parser.parse(field, receivedAt: receipt).kind,
        RetryAfterKind.excessive,
      );
    }
  });

  test('all HTTP-date formats, past dates, malformed calendars and skew', () {
    for (final field in [
      'Sun, 06 Nov 1994 08:49:37 GMT',
      'Sunday, 06-Nov-94 08:49:37 GMT',
      'Sun Nov  6 08:49:37 1994',
    ]) {
      expect(
        parser.parse(field, receivedAt: receipt).minimumDelay,
        const Duration(seconds: 7),
      );
      expect(
        parser
            .parse(field, receivedAt: receipt.add(const Duration(minutes: 1)))
            .minimumDelay,
        Duration.zero,
      );
      expect(
        parser
            .parse(
              field,
              receivedAt: receipt.subtract(const Duration(seconds: 10)),
            )
            .minimumDelay,
        const Duration(seconds: 17),
      );
      expect(
        parser
            .parse(field, receivedAt: receipt.subtract(const Duration(days: 2)))
            .kind,
        RetryAfterKind.excessive,
      );
    }
    for (final field in [
      'Sun, 31 Nov 1994 08:49:37 GMT',
      'Sun, 06 Nov 1994 24:49:37 GMT',
      'Sun, 06 Nov 1994 08:60:37 GMT',
      'Sun, 06 Nov 1994 08:49:61 GMT',
      'Sun, 06 Nov 1994 08:49:37 UTC',
      'Sun, 06 Nov 1994 08:49:37 GMT, 2',
      '1994-11-06T08:49:37Z',
    ]) {
      expect(
        parser.parse(field, receivedAt: receipt).kind,
        RetryAfterKind.invalid,
        reason: field,
      );
    }
    final old = parser.parse(
      'Sunday, 06-Nov-94 08:49:37 GMT',
      receivedAt: DateTime.utc(2040),
    );
    expect(old.minimumDelay, Duration.zero);
    expect(
      () => parser.parse('0', receivedAt: DateTime(2026)),
      throwsArgumentError,
    );
  });

  test(
    'server minimum survives jitter and is never clamped into budget',
    () async {
      for (final seconds in [0, 5, 20, 30]) {
        final clock = _Clock(receipt);
        final scheduler = _Scheduler(clock);
        final source = CancellationSource();
        addTearDown(source.dispose);
        var attempts = 0;
        await RetryExecutor(
          clock: clock,
          scheduler: scheduler,
          random: const _Random(.5),
        ).execute<int, String>(
          operation: (_, _) async {
            attempts++;
            return const Err('retry', StackTrace.empty);
          },
          policy: RetryPolicy(
            maxAttempts: 2,
            maxElapsed: const Duration(seconds: 20),
            backoff: FixedBackoff(const Duration(seconds: 4)),
            jitter: const FullJitter(),
            classify: (_) => RetryDecision.retry(
              retryAfter: parser.parse('$seconds', receivedAt: receipt),
            ),
          ),
          cancellation: source.signal,
        );
        expect(attempts, seconds >= 20 ? 1 : 2);
        expect(
          scheduler.delays,
          seconds >= 20
              ? isEmpty
              : [Duration(seconds: seconds < 2 ? 2 : seconds)],
        );
      }
    },
  );

  test('invalid, excessive and uncertain feedback never retries', () async {
    for (final decision in [
      const RetryDecision.retry(retryAfter: RetryAfterHint.invalid()),
      const RetryDecision.retry(retryAfter: RetryAfterHint.excessive()),
      const RetryDecision.uncertain(),
    ]) {
      final source = CancellationSource();
      addTearDown(source.dispose);
      var attempts = 0;
      await RetryExecutor().execute<int, String>(
        operation: (_, _) async {
          attempts++;
          return const Err('failure', StackTrace.empty);
        },
        policy: RetryPolicy(classify: (_) => decision),
        cancellation: source.signal,
      );
      expect(attempts, 1);
    }
  });

  test('backoff saturates before multiplication and constant backoff is bounded work', () {
    final maximum = Duration(microseconds: 8000000000000000);
    expect(
      ExponentialBackoff(
        initial: const Duration(microseconds: 1000000000000),
        multiplier: 1000000000,
        maximum: maximum,
      ).delayAfter(2),
      maximum,
    );
    expect(
      ExponentialBackoff(multiplier: 1).delayAfter(0x7fffffff),
      const Duration(milliseconds: 200),
    );
    expect(
      () => const FullJitter().apply(
        const Duration(seconds: 1),
        const _Random(double.nan),
      ),
      throwsStateError,
    );
  });

  test(
    'operation budget exceptions never become an older typed failure',
    () async {
      final clock = _Clock(receipt);
      final source = CancellationSource();
      addTearDown(source.dispose);
      const failure = RetryBudgetExceededException(RetryBudgetStop.attempts);
      final future = RetryExecutor(clock: clock, scheduler: _Scheduler(clock))
          .execute<int, String>(
            operation: (attempt, _) async {
              if (attempt == 1)
                return const Err('old failure', StackTrace.empty);
              throw failure;
            },
            policy: RetryPolicy(classify: (_) => const RetryDecision.retry()),
            cancellation: source.signal,
          );
      await expectLater(future, throwsA(same(failure)));
    },
  );

  test('rate refill saturates before large integer multiplication', () {
    final clock = _Clock(receipt);
    final limiter = RateLimiter(
      capacity: 10,
      refillTokens: 1000000000000000,
      refillPeriod: const Duration(microseconds: 1),
      clock: clock,
    );
    expect(limiter.tryAcquire(10), isTrue);
    clock.current = receipt.add(const Duration(days: 365));
    expect(limiter.availableTokens, 10);
    expect(limiter.tryAcquire(10), isTrue);
    expect(limiter.tryAcquire(), isFalse);
  });

  test(
    'overslept waits and clock regression cannot start another attempt',
    () async {
      for (final shift in [
        const Duration(minutes: 1),
        const Duration(seconds: -10),
      ]) {
        final clock = _Clock(receipt);
        final source = CancellationSource();
        addTearDown(source.dispose);
        var attempts = 0;
        final result =
            await RetryExecutor(
              clock: clock,
              scheduler: _Scheduler(clock, shift: shift),
            ).execute<int, String>(
              operation: (_, _) async {
                attempts++;
                return const Err('failure', StackTrace.empty);
              },
              policy: RetryPolicy(classify: (_) => const RetryDecision.retry()),
              cancellation: source.signal,
            );
        expect(result, isA<Err<String>>());
        expect(attempts, 1);
      }
    },
  );

  test(
    'shared reconnect storm measures concurrency, queue, attempts and drain',
    () async {
      final clock = _Clock(receipt);
      final bulkhead = Bulkhead(maxConcurrent: 2, maxQueue: 4);
      final source = CancellationSource();
      final budget = RetryBudget(
        maxAttempts: 5,
        maxElapsed: const Duration(seconds: 30),
        bulkhead: bulkhead,
        rateLimiter: RateLimiter(
          capacity: 5,
          refillTokens: 1,
          refillPeriod: const Duration(days: 1),
          clock: clock,
        ),
        clock: clock,
      );
      final executor = RetryExecutor(
        clock: clock,
        scheduler: _Scheduler(clock),
      );
      var active = 0;
      var peakActive = 0;
      var peakQueue = 0;
      var attempts = 0;
      final failures = <Object>[];
      Future<void> run() async {
        try {
          await executor.execute<int, String>(
            operation: (_, _) async {
              attempts++;
              active++;
              if (active > peakActive) peakActive = active;
              await Future<void>.delayed(Duration.zero);
              active--;
              return const Err('reconnect', StackTrace.empty);
            },
            policy: RetryPolicy(
              maxAttempts: 3,
              backoff: FixedBackoff(Duration.zero),
              classify: (_) => const RetryDecision.retry(),
            ),
            cancellation: source.signal,
            budget: budget,
          );
        } on Object catch (error) {
          failures.add(error);
        }
      }

      final futures = <Future<void>>[];
      for (var i = 0; i < 30; i++) {
        futures.add(run());
        if (bulkhead.queuedCount > peakQueue) peakQueue = bulkhead.queuedCount;
      }
      await Future.wait(futures);
      await bulkhead.disposeAsync();
      source.dispose();
      expect(bulkhead.peakRunningCount, peakActive);
      expect(bulkhead.peakQueuedCount, peakQueue);
      expect(
        bulkhead.admittedCount + bulkhead.rejectedCount,
        greaterThanOrEqualTo(30),
      );
      expect(peakActive, 2);
      expect(peakQueue, 4);
      expect(attempts, 5);
      expect(budget.attemptsStarted, attempts);
      expect(failures, isNotEmpty);
      expect(
        failures.every(
          (e) =>
              e is BulkheadRejectedException ||
              e is RetryBudgetExceededException,
        ),
        isTrue,
      );
      expect([active, bulkhead.runningCount, bulkhead.queuedCount], [0, 0, 0]);
    },
  );

  test('queued admission rechecks deadline, cancellation and shared elapsed budget', () async {
    for (final mode in ['deadline', 'cancel', 'elapsed', 'rate']) {
      final clock = _Clock(receipt);
      final bulkhead = Bulkhead(maxConcurrent: 1, maxQueue: 1);
      final blocker = Completer<void>();
      final blocking = bulkhead.run((_) => blocker.future);
      final source = CancellationSource();
      final limiter = RateLimiter(
        capacity: 1,
        refillTokens: 1,
        refillPeriod: const Duration(days: 1),
        clock: clock,
      );
      final budget = RetryBudget(
        maxAttempts: 1,
        maxElapsed: const Duration(seconds: 5),
        bulkhead: bulkhead,
        rateLimiter: limiter,
        clock: clock,
      );
      var ran = false;
      final result = RetryExecutor(clock: clock).execute<int, String>(
        operation: (_, _) async {
          ran = true;
          return const Ok(1);
        },
        policy: RetryPolicy(classify: (_) => const RetryDecision.stop()),
        cancellation: source.signal,
        budget: budget,
        deadline: mode == 'deadline'
            ? receipt.add(const Duration(seconds: 1))
            : null,
      );
      final checked = expectLater(
        result,
        throwsA(switch (mode) {
          'cancel' => isA<CancellationException>(),
          'deadline' => isA<OperationDeadlineExceededException>(),
          _ => isA<RetryBudgetExceededException>(),
        }),
      );
      if (mode == 'cancel') {
        source.cancel();
      } else if (mode == 'rate') {
        expect(limiter.tryAcquire(), isTrue);
      } else {
        clock.current = receipt.add(const Duration(seconds: 5));
      }
      blocker.complete();
      await checked;
      await blocking;
      await bulkhead.disposeAsync();
      source.dispose();
      expect(ran, isFalse);
      expect(budget.attemptsStarted, 0);
      expect([bulkhead.runningCount, bulkhead.queuedCount], [0, 0]);
    }
  });
}

final class _Clock implements ResilienceClock {
  _Clock(this.current);
  DateTime current;
  @override
  DateTime now() => current;
}

final class _Scheduler implements ResilienceScheduler {
  _Scheduler(this.clock, {this.shift});
  final _Clock clock;
  final Duration? shift;
  final delays = <Duration>[];
  @override
  Future<void> wait(Duration delay, CancellationSignal cancellation) async {
    cancellation.throwIfCancelled();
    delays.add(delay);
    clock.current = clock.current.add(shift ?? delay);
  }
}

final class _Random implements ResilienceRandom {
  const _Random(this.value);
  final double value;
  @override
  double nextDouble() => value;
}
