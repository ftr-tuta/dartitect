import 'dart:async';

import 'package:dartitect_flutter/dartitect_flutter_incremental.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'success and expected failure retain aggregate, progress, and receipt',
    () async {
      final success = _command(
        IncrementalOperation<int, _Failure>.sync(
          () => const <Result<int, _Failure>>[
            Ok<int>(1),
            Ok<int>(2),
            Ok<int>(3),
          ],
        ),
      );
      final execution = await success.execute();
      expect(
        execution,
        isA<CommandExecutionSucceeded<IncrementalCommandReceipt, _Failure>>(),
      );
      final succeeded =
          success.state as IncrementalCommandSucceeded<int, _Failure, String>;
      expect(succeeded.aggregate, 6);
      expect(succeeded.emissionCount, 3);
      expect(succeeded.totalWeight, 3);
      expect(succeeded.latestProgress, '3:6');
      expect(
        succeeded.receipt!.terminalKind,
        IncrementalCommandTerminalKind.succeeded,
      );
      expect(success.reset(), isTrue);
      expect(
        success.state,
        isA<IncrementalCommandIdle<int, _Failure, String>>(),
      );
      await success.disposeAsync();

      final expected = _Failure('typed');
      final expectedStack = StackTrace.current;
      final failure = _command(
        IncrementalOperation<int, _Failure>.sync(
          () => <Result<int, _Failure>>[
            const Ok<int>(4),
            Err<_Failure>(expected, expectedStack),
          ],
        ),
      );
      expect(
        await failure.execute(),
        isA<CommandExecutionFailed<IncrementalCommandReceipt, _Failure>>(),
      );
      final failed =
          failure.state as IncrementalCommandFailed<int, _Failure, String>;
      expect(failed.aggregate, 4);
      expect(failed.failure, same(expected));
      expect(failed.stackTrace, same(expectedStack));
      expect(
        failed.receipt!.terminalKind,
        IncrementalCommandTerminalKind.failed,
      );
      await failure.disposeAsync();
    },
  );

  test(
    'cancellation waits cleanup and retains the partial aggregate',
    () async {
      var cleaned = false;
      Stream<Result<int, _Failure>> producer() async* {
        try {
          yield const Ok<int>(2);
          yield const Ok<int>(4);
        } finally {
          await Future<void>.delayed(Duration.zero);
          cleaned = true;
        }
      }

      final command = _command(
        IncrementalOperation<int, _Failure>.async(producer),
      );
      command.addListener(() {
        final state = command.state;
        if (state is IncrementalCommandRunning<int, _Failure, String> &&
            state.emissionCount == 1) {
          command.cancel('stop');
        }
      });
      expect(
        await command.execute(),
        isA<CommandExecutionCancelled<IncrementalCommandReceipt, _Failure>>(),
      );
      expect(cleaned, isTrue);
      final cancelled =
          command.state as IncrementalCommandCancelled<int, _Failure, String>;
      expect(cancelled.aggregate, 2);
      expect(cancelled.emissionCount, 1);
      expect(cancelled.reason, 'stop');
      expect(
        cancelled.receipt!.terminalKind,
        IncrementalCommandTerminalKind.cancelled,
      );
      await command.disposeAsync();
    },
  );

  test('reducer crash preserves stack and partial state', () async {
    final error = StateError('reducer');
    final stack = StackTrace.current;
    final command = IncrementalCommand<int, int, _Failure, String>(
      operation: IncrementalOperation<int, _Failure>.sync(
        () => const <Result<int, _Failure>>[Ok<int>(1), Ok<int>(2)],
      ),
      initialAggregate: () => 0,
      reducer: (aggregate, item, _) {
        if (item == 2) Error.throwWithStackTrace(error, stack);
        return aggregate + item;
      },
      progressOf: (item, aggregate, _) => '$item:$aggregate',
    );
    await expectLater(command.execute(), throwsA(same(error)));
    final crashed =
        command.state as IncrementalCommandCrashed<int, _Failure, String>;
    expect(crashed.aggregate, 1);
    expect(crashed.error, same(error));
    expect(crashed.stackTrace, same(stack));
    expect(
      crashed.receipt!.terminalKind,
      IncrementalCommandTerminalKind.crashed,
    );
    await command.disposeAsync();
  });

  test(
    'frame coalescing reduces every item and fences terminal callback',
    () async {
      final frames = _FakeFrameScheduler();
      final release = Completer<void>();
      Stream<Result<int, _Failure>> producer() async* {
        yield const Ok<int>(1);
        await release.future;
        yield const Ok<int>(2);
      }

      final command = _command(
        IncrementalOperation<int, _Failure>.async(producer),
        publication: IncrementalPublication.coalesceFrame,
        frameScheduler: frames,
      );
      final observed = <IncrementalCommandState<int, _Failure, String>>[];
      command.addListener(() => observed.add(command.state));
      final execution = command.execute();
      await _waitFor(() => command.state.emissionCount == 1);
      expect(observed, isEmpty);
      expect(frames.pendingCount, 1);
      frames.flush();
      expect(observed.single.emissionCount, 1);

      release.complete();
      await execution;
      expect(
        command.state,
        isA<IncrementalCommandSucceeded<int, _Failure, String>>(),
      );
      final notifications = observed.length;
      frames.flush();
      expect(observed, hasLength(notifications));
      await command.disposeAsync();
    },
  );

  test(
    'microtask publication and every-emission publication remain bounded',
    () async {
      final microtask = _command(
        IncrementalOperation<int, _Failure>.sync(
          () => const <Result<int, _Failure>>[Ok<int>(1)],
        ),
        publication: IncrementalPublication.coalesceMicrotask,
      );
      var microtaskNotifications = 0;
      microtask.addListener(() => microtaskNotifications += 1);
      final microtaskExecution = microtask.execute();
      expect(microtaskNotifications, 0);
      await microtaskExecution;
      expect(microtaskNotifications, greaterThanOrEqualTo(1));
      await microtask.disposeAsync();

      final every = _command(
        IncrementalOperation<int, _Failure>.sync(
          () => const <Result<int, _Failure>>[Ok<int>(1), Ok<int>(2)],
        ),
      );
      final counts = <int>[];
      every.addListener(() => counts.add(every.state.emissionCount));
      await every.execute();
      expect(counts, containsAllInOrder(<int>[0, 1, 2, 2]));
      await every.disposeAsync();
    },
  );

  test('restartLatest fences stale execution and waits old cleanup', () async {
    var factoryCalls = 0;
    var firstCleaned = false;
    Stream<Result<int, _Failure>> producer() async* {
      factoryCalls += 1;
      if (factoryCalls == 1) {
        try {
          yield const Ok<int>(1);
          await Future<void>.delayed(const Duration(seconds: 10));
          yield const Ok<int>(99);
        } finally {
          firstCleaned = true;
        }
      } else {
        yield const Ok<int>(10);
      }
    }

    final command = _command(
      IncrementalOperation<int, _Failure>.async(producer),
      concurrency: const CommandConcurrency.restartLatest(),
    );
    Future<CommandExecution<IncrementalCommandReceipt, _Failure>>? second;
    command.addListener(() {
      final state = command.state;
      if (second == null &&
          state is IncrementalCommandRunning<int, _Failure, String> &&
          state.executionId == 1 &&
          state.emissionCount == 1) {
        second = command.execute();
      }
    });
    final first = command.execute();
    await _waitFor(() => second != null);
    expect(
      await first,
      isA<CommandExecutionCancelled<IncrementalCommandReceipt, _Failure>>(),
    );
    expect(firstCleaned, isTrue);
    expect(
      await second!,
      isA<CommandExecutionSucceeded<IncrementalCommandReceipt, _Failure>>(),
    );
    final state =
        command.state as IncrementalCommandSucceeded<int, _Failure, String>;
    expect(state.executionId, 2);
    expect(state.aggregate, 10);
    await command.disposeAsync();
  });

  test('dispose fences a pending frame notification', () async {
    final frames = _FakeFrameScheduler();
    final release = Completer<void>();
    final command = _command(
      IncrementalOperation<int, _Failure>.async(() async* {
        yield const Ok<int>(1);
        await release.future;
      }),
      publication: IncrementalPublication.coalesceFrame,
      frameScheduler: frames,
    );
    var notifications = 0;
    command.addListener(() => notifications += 1);
    command.execute().ignore();
    await _waitFor(() => command.state.emissionCount == 1);
    command.dispose();
    frames.flush();
    expect(notifications, 0);
    release.complete();
    await command.disposeAsync();
  });

  testWidgets('builder reuses its static child across state changes', (
    tester,
  ) async {
    final command = _command(
      IncrementalOperation<int, _Failure>.sync(
        () => const <Result<int, _Failure>>[Ok<int>(1)],
      ),
    );
    var childBuilds = 0;
    final child = _BuildCounter(onBuild: () => childBuilds += 1);
    Widget render(
      BuildContext context,
      IncrementalCommandState<int, _Failure, String> state,
      Widget? child,
    ) => child!;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: IncrementalCommandStateBuilder<int, int, _Failure, String>(
          command: command,
          idle: render,
          running: render,
          succeeded: render,
          failed: render,
          cancelled: render,
          crashed: render,
          child: child,
        ),
      ),
    );
    expect(childBuilds, 1);
    await command.execute();
    await tester.pump();
    expect(childBuilds, 1);
    await command.disposeAsync();
  });
}

IncrementalCommand<int, int, _Failure, String> _command(
  IncrementalOperation<int, _Failure> operation, {
  CommandConcurrency concurrency = const CommandConcurrency.reject(),
  IncrementalPublication publication = IncrementalPublication.everyEmission,
  SourceFrameScheduler frameScheduler = const FlutterSourceFrameScheduler(),
}) => IncrementalCommand<int, int, _Failure, String>(
  operation: operation,
  initialAggregate: () => 0,
  reducer: (aggregate, item, _) => aggregate + item,
  progressOf: (item, aggregate, _) => '$item:$aggregate',
  concurrency: concurrency,
  publication: publication,
  frameScheduler: frameScheduler,
);

final class _Failure {
  const _Failure(this.message);

  final String message;
}

final class _FakeFrameScheduler implements SourceFrameScheduler {
  final List<VoidCallback> _callbacks = <VoidCallback>[];

  int get pendingCount => _callbacks.length;

  @override
  void schedule(VoidCallback callback) => _callbacks.add(callback);

  void flush() {
    final callbacks = List<VoidCallback>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

final class _BuildCounter extends StatelessWidget {
  const _BuildCounter({required this.onBuild});

  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.shrink();
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition did not settle.');
}
