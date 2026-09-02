import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('all concurrency bounds are validated by lane consumers at runtime', () {
    final zero = int.parse('0');
    expect(
      () => CommandLane<int, String>(
        action: (_) async => const Ok<int>(1),
        concurrency: CommandConcurrency.sequential(maxQueue: zero),
      ),
      throwsArgumentError,
    );
    expect(
      () => CommandLane<int, String>(
        action: (_) async => const Ok<int>(1),
        concurrency: CommandConcurrency.concurrent(maxConcurrent: zero),
      ),
      throwsArgumentError,
    );
    expect(
      () => KeyedCommandLane<String, int, int, String>(
        action: (_, _, _) async => const Ok<int>(1),
        concurrency: CommandConcurrency.keyed(maxConcurrent: zero),
      ),
      throwsArgumentError,
    );
    expect(
      () => KeyedCommandLane<String, int, int, String>(
        action: (_, _, _) async => const Ok<int>(1),
        concurrency: CommandConcurrency.keyed(
          perKey: CommandConcurrency.sequential(maxQueue: zero),
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'cancellation is exact-once and listener failures are isolated',
    () async {
      final source = CancellationSource();
      final calls = <String>[];
      source.signal.register((reason) {
        calls.add('first:$reason');
        throw StateError('listener failed');
      });
      final registration = source.signal.register(
        (reason) => calls.add('second:$reason'),
      );

      source.cancel('stop');
      source.cancel('ignored');

      expect(await source.signal.whenCancelled, 'stop');
      expect(source.signal.reason, 'stop');
      expect(calls, <String>['first:stop', 'second:stop']);
      expect(
        () => source.signal.throwIfCancelled(),
        throwsA(isA<CancellationException>()),
      );
      registration.dispose();
      registration.dispose();
      expect(registration.isDisposed, isTrue);
      source.signal.register((reason) => calls.add('late:$reason'));
      expect(calls.last, 'late:stop');
    },
  );

  test('reject is default and preserves the last domain outcome', () async {
    final pending = Completer<Result<int, String>>();
    final lane = CommandLane<int, String>(action: (_) => pending.future);

    final first = lane.execute();
    final rejected = await lane.execute();
    expect(
      rejected,
      isA<CommandRejected<int, String>>().having(
        (outcome) => outcome.reason,
        'reason',
        CommandLaneRejectionReason.busy,
      ),
    );
    expect(lane.lastOutcome, isNull);
    pending.complete(const Ok<int>(7));
    expect(
      await first,
      isA<CommandSucceeded<int, String>>().having(
        (outcome) => outcome.value,
        'value',
        7,
      ),
    );
    expect(lane.lastOutcome, isA<CommandSucceeded<int, String>>());
    await lane.dispose();
  });

  test('join returns the identical running future', () async {
    final pending = Completer<Result<int, String>>();
    final lane = CommandLane<int, String>(
      concurrency: const CommandConcurrency.join(),
      action: (_) => pending.future,
    );

    final first = lane.execute();
    final joined = lane.execute();
    expect(identical(first, joined), isTrue);
    pending.complete(const Ok<int>(1));
    expect(await joined, isA<CommandSucceeded<int, String>>());
    await lane.dispose();
  });

  test('drop does not replace the last result', () async {
    final pending = <Completer<Result<int, String>>>[];
    final lane = CommandLane<int, String>(
      concurrency: const CommandConcurrency.drop(),
      action: (_) {
        final completer = Completer<Result<int, String>>();
        pending.add(completer);
        return completer.future;
      },
    );
    final first = lane.execute();
    pending.single.complete(const Ok<int>(1));
    await first;
    final previous = lane.lastOutcome;

    final second = lane.execute();
    final dropped = await lane.execute();
    expect(dropped, isA<CommandDropped<int, String>>());
    expect(lane.lastOutcome, same(previous));
    pending.last.complete(Err<String>('expected', StackTrace.current));
    expect(await second, isA<CommandFailed<int, String>>());
    await lane.dispose();
  });

  test('sequential is FIFO and rejects explicit overflow', () async {
    final started = <int>[];
    final pending = <Completer<Result<int, String>>>[];
    final lane = CommandLane<int, String>(
      concurrency: const CommandConcurrency.sequential(maxQueue: 2),
      action: (_) {
        started.add(started.length);
        final completer = Completer<Result<int, String>>();
        pending.add(completer);
        return completer.future;
      },
    );

    final first = lane.execute();
    final second = lane.execute();
    final third = lane.execute();
    final overflow = await lane.execute();
    expect(lane.runningCount, 1);
    expect(lane.queuedCount, 2);
    expect(
      overflow,
      isA<CommandRejected<int, String>>().having(
        (outcome) => outcome.reason,
        'reason',
        CommandLaneRejectionReason.queueFull,
      ),
    );

    pending[0].complete(const Ok<int>(0));
    await first;
    await _tick();
    pending[1].complete(const Ok<int>(1));
    await second;
    await _tick();
    pending[2].complete(const Ok<int>(2));
    await third;
    expect(started, <int>[0, 1, 2]);
    expect(lane.runningCount, 0);
    expect(lane.queuedCount, 0);
    await lane.dispose();
  });

  test('restartLatest cancels and discards stale completion', () async {
    final signals = <CancellationSignal>[];
    final pending = <Completer<Result<int, String>>>[];
    final lane = CommandLane<int, String>(
      concurrency: const CommandConcurrency.restartLatest(),
      action: (signal) {
        signals.add(signal);
        final completer = Completer<Result<int, String>>();
        pending.add(completer);
        return completer.future;
      },
    );

    final first = lane.execute();
    final second = lane.execute();
    expect(signals.first.isCancelled, isTrue);
    expect(await first, isA<CommandCancelled<int, String>>());
    pending.first.complete(const Ok<int>(1));
    pending.last.complete(const Ok<int>(2));
    expect(
      await second,
      isA<CommandSucceeded<int, String>>().having(
        (outcome) => outcome.value,
        'value',
        2,
      ),
    );
    await _tick();
    expect(lane.runningCount, 0);
    expect((lane.lastOutcome as CommandSucceeded<int, String>).value, 2);
    await lane.dispose();
  });

  test('concurrent never exceeds its configured maximum', () async {
    final pending = <Completer<Result<int, String>>>[];
    var active = 0;
    var peak = 0;
    final lane = CommandLane<int, String>(
      concurrency: const CommandConcurrency.concurrent(maxConcurrent: 2),
      action: (_) async {
        active += 1;
        peak = active > peak ? active : peak;
        final completer = Completer<Result<int, String>>();
        pending.add(completer);
        final result = await completer.future;
        active -= 1;
        return result;
      },
    );

    final first = lane.execute();
    final second = lane.execute();
    final rejected = await lane.execute();
    expect(
      rejected,
      isA<CommandRejected<int, String>>().having(
        (outcome) => outcome.reason,
        'reason',
        CommandLaneRejectionReason.concurrentLimit,
      ),
    );
    pending[0].complete(const Ok<int>(1));
    pending[1].complete(const Ok<int>(2));
    await Future.wait(<Future<CommandOutcome<int, String>>>[first, second]);
    expect(peak, 2);
    expect(active, 0);
    await lane.dispose();
  });

  test('crash reports once, rethrows, stops, and resumes explicitly', () async {
    final reporter = _CrashReporter();
    var shouldCrash = true;
    final lane = CommandLane<int, String>(
      reporter: reporter,
      action: (_) async {
        if (shouldCrash) _throwCrash();
        return const Ok<int>(9);
      },
    );

    await expectLater(lane.execute(), throwsA(isA<StateError>()));
    expect(reporter.errors, hasLength(1));
    expect(reporter.stacks.single.toString(), contains('_throwCrash'));
    expect(lane.isStopped, isTrue);
    expect(
      await lane.execute(),
      isA<CommandRejected<int, String>>().having(
        (outcome) => outcome.reason,
        'reason',
        CommandLaneRejectionReason.laneStopped,
      ),
    );
    shouldCrash = false;
    lane.resume();
    expect(await lane.execute(), isA<CommandSucceeded<int, String>>());
    await lane.dispose();
  });

  test('dispose cancels, drains, and leaves no running future', () async {
    final lane = CommandLane<int, String>(
      action: (signal) async {
        await signal.whenCancelled;
        signal.throwIfCancelled();
        return const Ok<int>(1);
      },
    );
    final execution = lane.execute();

    await Future.wait(<Future<void>>[lane.dispose(), lane.dispose()]);

    expect(await execution, isA<CommandCancelled<int, String>>());
    expect(lane.runningCount, 0);
    expect(lane.queuedCount, 0);
    expect(
      await lane.execute(),
      isA<CommandRejected<int, String>>().having(
        (outcome) => outcome.reason,
        'reason',
        CommandLaneRejectionReason.disposed,
      ),
    );
  });

  test('onChanged may dispose during the first unkeyed transition', () async {
    late final CommandLane<int, String> lane;
    Future<void>? reentrantDisposal;
    var requested = false;
    lane = CommandLane<int, String>(
      action: (signal) async {
        await signal.whenCancelled;
        signal.throwIfCancelled();
        return const Ok<int>(0);
      },
      onChanged: () {
        if (!requested && lane.runningCount == 1) {
          requested = true;
          reentrantDisposal = lane.dispose();
        }
      },
    );

    final outcome = lane.execute();

    await expectLater(reentrantDisposal, completes);
    expect(await outcome, isA<CommandCancelled<int, String>>());
    expect(lane.runningCount, 0);
    expect(lane.queuedCount, 0);
  });

  test('onChanged may dispose during the first keyed transition', () async {
    late final KeyedCommandLane<String, int, int, String> lane;
    Future<void>? reentrantDisposal;
    var requested = false;
    lane = KeyedCommandLane<String, int, int, String>(
      action: (key, argument, signal) async {
        await signal.whenCancelled;
        signal.throwIfCancelled();
        return const Ok<int>(0);
      },
      onChanged: () {
        if (!requested && lane.runningCount == 1) {
          requested = true;
          reentrantDisposal = lane.dispose();
        }
      },
    );

    final outcome = lane.execute('key', 1);

    await expectLater(reentrantDisposal, completes);
    expect(await outcome, isA<CommandCancelled<int, String>>());
    expect(lane.runningCount, 0);
    expect(lane.queuedCount, 0);
    expect(lane.activeKeyCount, 0);
  });

  test('keyed lanes bound keys and keep FIFO independently', () async {
    final pending = <String, List<Completer<Result<int, String>>>>{};
    final starts = <String>[];
    final lane = KeyedCommandLane<String, int, int, String>(
      concurrency: const CommandConcurrency.keyed(
        perKey: CommandConcurrency.sequential(maxQueue: 2),
        maxConcurrent: 2,
      ),
      action: (key, argument, signal) {
        starts.add('$key:$argument');
        final completer = Completer<Result<int, String>>();
        pending
            .putIfAbsent(key, () => <Completer<Result<int, String>>>[])
            .add(completer);
        return completer.future;
      },
    );

    final a1 = lane.execute('a', 1);
    final a2 = lane.execute('a', 2);
    final b1 = lane.execute('b', 1);
    final limited = await lane.execute('c', 1);
    expect(lane.activeKeyCount, 2);
    expect(lane.queuedCount, 1);
    expect(
      limited,
      isA<CommandRejected<int, String>>().having(
        (outcome) => outcome.reason,
        'reason',
        CommandLaneRejectionReason.keyLimit,
      ),
    );
    pending['a']![0].complete(const Ok<int>(1));
    await a1;
    await _tick();
    pending['a']![1].complete(const Ok<int>(2));
    pending['b']!.single.complete(const Ok<int>(1));
    await Future.wait(<Future<CommandOutcome<int, String>>>[a2, b1]);
    expect(starts, <String>['a:1', 'b:1', 'a:2']);
    expect(lane.runningCount, 0);
    expect(lane.queuedCount, 0);
    await lane.dispose();
  });

  test('keyed join requires the same argument in the same key', () async {
    final pending = Completer<Result<int, String>>();
    final lane = KeyedCommandLane<String, int, int, String>(
      concurrency: const CommandConcurrency.keyed(
        perKey: CommandConcurrency.join(),
      ),
      action: (key, argument, signal) => pending.future,
    );

    final first = lane.execute('a', 1);
    final joined = lane.execute('a', 1);
    expect(identical(first, joined), isTrue);
    expect(await lane.execute('a', 2), isA<CommandRejected<int, String>>());
    pending.complete(const Ok<int>(1));
    await joined;
    await lane.dispose();
  });
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

Never _throwCrash() => throw StateError('unexpected crash');

final class _CrashReporter implements CommandCrashReporter {
  final List<Object> errors = <Object>[];
  final List<StackTrace> stacks = <StackTrace>[];

  @override
  void report(Object error, StackTrace stackTrace) {
    errors.add(error);
    stacks.add(stackTrace);
  }
}
