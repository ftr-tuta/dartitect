import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:test/test.dart';

void main() {
  test(
    'single-flight detaches one waiter without cancelling shared work',
    () async {
      final flights = SingleFlight<String, int>();
      final operation = Completer<int>();
      var sharedCancelled = false;
      final firstCancellation = CancellationSource();
      var starts = 0;
      Future<int> run(CancellationSignal signal) {
        starts += 1;
        signal.register((_) => sharedCancelled = true);
        return operation.future;
      }

      final first = flights.run(
        'key',
        run,
        cancellation: firstCancellation.signal,
      );
      final second = flights.run('key', run);
      firstCancellation.cancel('detached');
      await expectLater(first, throwsA(isA<CancellationException>()));
      expect(sharedCancelled, isFalse);
      operation.complete(9);
      expect(await second, 9);
      expect(starts, 1);
      await flights.disposeAsync();
    },
  );

  test(
    'single-flight cancels shared work after every waiter detaches',
    () async {
      final flights = SingleFlight<String, void>();
      final waiter = CancellationSource();
      final drained = Completer<void>();
      final future = flights.run('key', (signal) async {
        await signal.whenCancelled;
        drained.complete();
      }, cancellation: waiter.signal);

      waiter.cancel('leave');
      await expectLater(future, throwsA(isA<CancellationException>()));
      await drained.future;
      await flights.disposeAsync();
      expect(flights.inFlightCount, 0);
    },
  );

  test(
    'circuit breaker opens and admits one half-open recovery probe',
    () async {
      final clock = _Clock(DateTime.utc(2026, 8, 28));
      final breaker = CircuitBreaker(
        failureThreshold: 2,
        resetAfter: const Duration(seconds: 5),
        clock: clock,
      );
      Future<Result<int, StateError>> fail() async =>
          Err<StateError>(StateError('expected'), StackTrace.empty);

      await breaker.execute(operation: fail, countsAsFailure: (_) => true);
      await breaker.execute(operation: fail, countsAsFailure: (_) => true);
      expect(breaker.state, CircuitBreakerState.open);
      await expectLater(
        breaker.execute(operation: fail, countsAsFailure: (_) => true),
        throwsA(isA<CircuitBreakerOpenException>()),
      );

      clock.current = clock.current.add(const Duration(seconds: 5));
      expect(breaker.state, CircuitBreakerState.halfOpen);
      expect(
        await breaker.execute<int, StateError>(
          operation: () async => const Ok<int>(1),
          countsAsFailure: (_) => true,
        ),
        const Ok<int>(1),
      );
      expect(breaker.state, CircuitBreakerState.closed);
    },
  );

  test(
    'bulkhead bounds running and queued operations and drains disposal',
    () async {
      final bulkhead = Bulkhead(maxConcurrent: 1, maxQueue: 1);
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final first = bulkhead.run<int>((signal) async {
        await firstGate.future;
        return 1;
      });
      final second = bulkhead.run<int>((signal) async {
        await secondGate.future;
        return 2;
      });
      expect(bulkhead.runningCount, 1);
      expect(bulkhead.queuedCount, 1);
      expect(
        () => bulkhead.run<int>((_) async => 3),
        throwsA(isA<BulkheadRejectedException>()),
      );
      firstGate.complete();
      expect(await first, 1);
      await Future<void>.delayed(Duration.zero);
      expect(bulkhead.runningCount, 1);
      secondGate.complete();
      expect(await second, 2);
      await bulkhead.disposeAsync();
      expect(bulkhead.runningCount, 0);
    },
  );

  test('rate limiter refills only from the injected clock', () {
    final clock = _Clock(DateTime.utc(2026, 8, 28));
    final limiter = RateLimiter(
      capacity: 2,
      refillTokens: 1,
      refillPeriod: const Duration(seconds: 10),
      clock: clock,
    );
    expect(limiter.tryAcquire(2), isTrue);
    expect(limiter.tryAcquire(), isFalse);
    clock.current = clock.current.add(const Duration(seconds: 10));
    expect(limiter.tryAcquire(), isTrue);
    expect(limiter.availableTokens, 0);
  });
}

final class _Clock implements ResilienceClock {
  _Clock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}
