import 'dart:async';

import 'package:dartitect/dartitect_incremental.dart';
import 'package:test/test.dart';

void main() {
  test('sync producer is cold and honors consumer backpressure', () async {
    var factories = 0;
    final pulled = <int>[];
    final release = Completer<void>();
    final operation = IncrementalOperation<int, _Failure>.sync(() sync* {
      factories += 1;
      for (var value = 1; value <= 3; value += 1) {
        pulled.add(value);
        yield Ok<int>(value);
      }
    });

    final first = operation.consume(
      onValue: (value, context) async {
        expect(context.sequence, value);
        if (value == 1) await release.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(pulled, <int>[1]);
    release.complete();

    final firstResult = await first;
    final secondResult = await operation.consume(onValue: (_, _) {});
    expect(factories, 2);
    expect(firstResult.outcome, isA<Ok<void>>());
    expect(firstResult.report.emissionCount, 3);
    expect(secondResult.report.executionId, 2);
  });

  test('async producer awaits values and rejects broadcast streams', () async {
    final delivered = <int>[];
    var active = 0;
    var maximumActive = 0;
    final operation = IncrementalOperation<int, _Failure>.async(() async* {
      for (var value = 1; value <= 3; value += 1) {
        yield Ok<int>(value);
      }
    });
    await operation.consume(
      onValue: (value, _) async {
        active += 1;
        if (active > maximumActive) maximumActive = active;
        await Future<void>.delayed(Duration.zero);
        delivered.add(value);
        active -= 1;
      },
    );
    expect(delivered, <int>[1, 2, 3]);
    expect(maximumActive, 1);

    final controller = StreamController<Result<int, _Failure>>.broadcast();
    final broadcast = IncrementalOperation<int, _Failure>.async(
      () => controller.stream,
    );
    await expectLater(
      broadcast.consume(onValue: (_, _) {}),
      throwsA(isA<IncrementalBroadcastStreamException>()),
    );
    await controller.close();
  });

  test('first Err stops delivery and retains its exact stack', () async {
    final expectedFailure = _Failure('expected');
    final expectedStack = StackTrace.current;
    final delivered = <int>[];
    final operation = IncrementalOperation<int, _Failure>.sync(
      () => <Result<int, _Failure>>[
        const Ok<int>(1),
        Err<_Failure>(expectedFailure, expectedStack),
        const Ok<int>(2),
      ],
    );

    final result = await operation.consume(
      onValue: (value, _) => delivered.add(value),
    );
    expect(delivered, <int>[1]);
    expect(result.report.terminalKind, IncrementalTerminalKind.failed);
    switch (result.outcome) {
      case Err<Object>(:final failure, :final stackTrace):
        expect(failure, same(expectedFailure));
        expect(stackTrace, same(expectedStack));
      case Ok<void>():
        fail('Expected the producer failure.');
    }
  });

  test('limits reject overflowing item before consumer delivery', () async {
    final delivered = <int>[];
    final countLimited = IncrementalOperation<int, _Failure>.sync(
      () => const <Result<int, _Failure>>[Ok<int>(1), Ok<int>(2), Ok<int>(3)],
      limits: const IncrementalLimits(maxEmissions: 2),
    );
    await expectLater(
      countLimited.consume(onValue: (value, _) => delivered.add(value)),
      throwsA(
        isA<IncrementalEmissionLimitExceededException>()
            .having((error) => error.report.emissionCount, 'count', 2)
            .having((error) => error.attemptedSequence, 'sequence', 3),
      ),
    );
    expect(delivered, <int>[1, 2]);

    final weightLimited = IncrementalOperation<int, _Failure>.sync(
      () => const <Result<int, _Failure>>[Ok<int>(2), Ok<int>(4)],
      limits: const IncrementalLimits(maxWeight: 5),
      weightOf: (value) => value,
    );
    await expectLater(
      weightLimited.consume(onValue: (_, _) {}),
      throwsA(
        isA<IncrementalWeightLimitExceededException>()
            .having((error) => error.report.totalWeight, 'weight', 2)
            .having((error) => error.attemptedWeight, 'attempted', 6),
      ),
    );
  });

  test('invalid limits are validated without relying on asserts', () {
    final invalid = IncrementalLimits(maxEmissions: int.parse('0'));
    expect(
      () => IncrementalOperation<int, _Failure>.sync(
        () => const <Result<int, _Failure>>[],
        limits: invalid,
      ),
      throwsArgumentError,
    );
  });

  test('fold and bounded collection return explicit state', () async {
    final operation = IncrementalOperation<int, _Failure>.sync(
      () => <Result<int, _Failure>>[
        for (var value = 1; value <= 5; value += 1) Ok<int>(value),
      ],
    );
    final folded = await operation.fold<int>(
      initial: 0,
      reducer: (total, item, context) {
        expect(context.cumulativeWeight, context.sequence);
        return total + item;
      },
    );
    final collected = await operation.collectBounded(capacity: 3);
    expect(folded.aggregate, 15);
    expect(folded.report.emissionCount, 5);
    expect(collected.items, <int>[3, 4, 5]);
    expect(collected.droppedItemCount, 2);
  });

  test('ring retains order within a fixed capacity', () {
    final ring = BoundedRingBuffer<int>(3)
      ..add(1)
      ..add(2)
      ..add(3)
      ..add(4);
    expect(ring.values, <int>[2, 3, 4]);
    expect(ring.droppedCount, 1);
    ring.clear();
    expect(ring.values, isEmpty);
    expect(ring.droppedCount, 0);
    expect(() => BoundedRingBuffer<int>(0), throwsArgumentError);
  });

  test(
    'closeable sync source cleans exactly once on limit and crash',
    () async {
      var limitCloses = 0;
      final limited = IncrementalOperation<int, _Failure>.syncCloseable(
        () => _CloseableSource(const <Result<int, _Failure>>[
          Ok<int>(1),
          Ok<int>(2),
        ], () => limitCloses += 1),
        limits: const IncrementalLimits(maxEmissions: 1),
      );
      await expectLater(
        limited.consume(onValue: (_, _) {}),
        throwsA(isA<IncrementalEmissionLimitExceededException>()),
      );
      expect(limitCloses, 1);

      var crashCloses = 0;
      final error = StateError('consumer crashed');
      final stack = StackTrace.current;
      final crashing = IncrementalOperation<int, _Failure>.syncCloseable(
        () => _CloseableSource(const <Result<int, _Failure>>[
          Ok<int>(1),
        ], () => crashCloses += 1),
      );
      await _expectExactCrash(
        crashing.consume(
          onValue: (_, _) => Error.throwWithStackTrace(error, stack),
        ),
        error,
        stack,
      );
      expect(crashCloses, 1);

      var cancellationCloses = 0;
      final cancellation = CancellationSource();
      final cancelling = IncrementalOperation<int, _Failure>.syncCloseable(
        () => _CloseableSource(const <Result<int, _Failure>>[
          Ok<int>(1),
          Ok<int>(2),
        ], () => cancellationCloses += 1),
      );
      await expectLater(
        cancelling.consume(
          cancellation: cancellation.signal,
          onValue: (_, _) => cancellation.cancel('stop closeable'),
        ),
        throwsA(isA<CancellationException>()),
      );
      expect(cancellationCloses, 1);
    },
  );

  test('injected clock supplies UTC item and report instants', () async {
    final instants = <DateTime>[
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 1, 1, 0, 0, 1),
      DateTime.utc(2026, 1, 1, 0, 0, 2),
    ].iterator;
    DateTime now() {
      instants.moveNext();
      return instants.current;
    }

    DateTime? itemTime;
    final operation = IncrementalOperation<int, _Failure>.sync(
      () => const <Result<int, _Failure>>[Ok<int>(1)],
      now: now,
    );
    final result = await operation.consume(
      onValue: (_, context) => itemTime = context.timestamp,
    );
    expect(itemTime, DateTime.utc(2026, 1, 1, 0, 0, 1));
    expect(result.report.startedAt, DateTime.utc(2026, 1, 1));
    expect(result.report.finishedAt, DateTime.utc(2026, 1, 1, 0, 0, 2));

    final localClock = IncrementalOperation<int, _Failure>.sync(
      () => const <Result<int, _Failure>>[],
      now: () => DateTime(2026),
    );
    await expectLater(localClock.consume(onValue: (_, _) {}), throwsStateError);
  });

  test('async cancellation awaits finally and fences late values', () async {
    final source = CancellationSource();
    final delivered = <int>[];
    var cleanupComplete = false;
    Stream<Result<int, _Failure>> producer() async* {
      try {
        yield const Ok<int>(1);
        await Future<void>.delayed(const Duration(seconds: 10));
        yield const Ok<int>(2);
      } finally {
        await Future<void>.delayed(Duration.zero);
        cleanupComplete = true;
      }
    }

    final operation = IncrementalOperation<int, _Failure>.async(producer);
    await expectLater(
      operation.consume(
        cancellation: source.signal,
        onValue: (value, _) {
          delivered.add(value);
          source.cancel('stop');
        },
      ),
      throwsA(
        isA<CancellationException>().having(
          (error) => error.reason,
          'reason',
          'stop',
        ),
      ),
    );
    expect(cleanupComplete, isTrue);
    expect(delivered, <int>[1]);
  });

  test('deadline cancels source before publishing terminal', () async {
    var cleanupComplete = false;
    final delivered = <int>[];
    Stream<Result<int, _Failure>> producer() async* {
      try {
        yield const Ok<int>(1);
        await Future<void>.delayed(const Duration(seconds: 10));
        yield const Ok<int>(2);
      } finally {
        cleanupComplete = true;
      }
    }

    final operation = IncrementalOperation<int, _Failure>.async(producer);
    final future = operation.consume(
      deadline: DateTime.now().toUtc().add(const Duration(milliseconds: 20)),
      onValue: (value, _) async {
        delivered.add(value);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );
    await expectLater(
      future,
      throwsA(isA<OperationDeadlineExceededException>()),
    );
    expect(cleanupComplete, isTrue);
    expect(delivered, <int>[1]);
  });

  test('stream and reducer crashes retain original stacks', () async {
    final streamError = StateError('stream crashed');
    final streamStack = StackTrace.current;
    final streaming = IncrementalOperation<int, _Failure>.async(
      () => Stream<Result<int, _Failure>>.error(streamError, streamStack),
    );
    await _expectExactCrash(
      streaming.consume(onValue: (_, _) {}),
      streamError,
      streamStack,
    );

    final reducerError = StateError('reducer crashed');
    final reducerStack = StackTrace.current;
    final reducing = IncrementalOperation<int, _Failure>.sync(
      () => const <Result<int, _Failure>>[Ok<int>(1)],
    );
    await _expectExactCrash(
      reducing.fold<int>(
        initial: 0,
        reducer: (_, _, _) =>
            Error.throwWithStackTrace(reducerError, reducerStack),
      ),
      reducerError,
      reducerStack,
    );
  });

  test('cleanup failure retains cleanup and primary stacks', () async {
    final primary = StateError('consumer');
    final primaryStack = StackTrace.current;
    final cleanup = StateError('cleanup');
    final cleanupStack = StackTrace.current;
    final operation = IncrementalOperation<int, _Failure>.syncCloseable(
      () => _CloseableSource(const <Result<int, _Failure>>[
        Ok<int>(1),
      ], () => Error.throwWithStackTrace(cleanup, cleanupStack)),
    );
    try {
      await operation.consume(
        onValue: (_, _) => Error.throwWithStackTrace(primary, primaryStack),
      );
      fail('Expected cleanup failure.');
    } on IncrementalCleanupException catch (error) {
      expect(error.error, same(cleanup));
      expect(error.stackTrace, same(cleanupStack));
      expect(error.primaryError, same(primary));
      expect(error.primaryStackTrace, same(primaryStack));
    }
  });
}

Future<void> _expectExactCrash(
  Future<Object?> future,
  Object expectedError,
  StackTrace expectedStack,
) async {
  try {
    await future;
    fail('Expected an unexpected crash.');
  } catch (error, stackTrace) {
    expect(error, same(expectedError));
    expect(stackTrace, same(expectedStack));
  }
}

final class _Failure {
  const _Failure(this.message);

  final String message;
}

final class _CloseableSource
    implements CloseableSyncIncrementalSource<int, _Failure> {
  _CloseableSource(this.values, this.onClose);

  final Iterable<Result<int, _Failure>> values;
  final void Function() onClose;

  @override
  Iterator<Result<int, _Failure>> get iterator => values.iterator;

  @override
  void close() => onClose();
}
