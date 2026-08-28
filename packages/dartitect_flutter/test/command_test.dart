import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('commands emit only payload-free terminal diagnostics', () async {
    final diagnostics = DartitectDiagnosticBuffer(capacity: 8);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(diagnostics),
      detail: DartitectDiagnosticDetail.topology,
    );
    final command = Command0<int, _ExpectedFailure>(
      () async => const Ok<int>(7),
      diagnostics: emitter.subject(DartitectDiagnosticSubjectKind.command),
    );

    await command.execute();
    await command.disposeAsync();
    expect(
      diagnostics.events.map((event) => event.phase),
      containsAll(<DartitectDiagnosticPhase>{
        DartitectDiagnosticPhase.succeeded,
        DartitectDiagnosticPhase.disposed,
      }),
    );
    await emitter.dispose();
    diagnostics.dispose();
  });

  test('Command0 rejects reentrancy and publishes success', () async {
    final completion = Completer<Result<int, _ExpectedFailure>>();
    final command = Command0<int, _ExpectedFailure>(() => completion.future);
    var notifications = 0;
    command.addListener(() => notifications += 1);

    final first = command.execute();
    final rejected = await command.execute();
    expect(rejected, isA<CommandExecutionRejected<int, _ExpectedFailure>>());
    expect(
      (rejected as CommandExecutionRejected<int, _ExpectedFailure>).reason,
      CommandRejectionReason.busy,
    );
    expect(command.state, isA<CommandRunningState<int, _ExpectedFailure>>());

    completion.complete(const Ok<int>(7));
    expect(
      await first,
      isA<CommandExecutionSucceeded<int, _ExpectedFailure>>(),
    );
    expect(command.state, isA<CommandSuccessState<int, _ExpectedFailure>>());
    expect(notifications, 2);
    command.dispose();
  });

  test('Command1 supports records and typed expected failure', () async {
    final command = Command1<({int id, String value}), int, _ExpectedFailure>(
      (record) async => record.id > 0
          ? Ok<int>(record.value.length)
          : Err<_ExpectedFailure>(
              const _ExpectedFailure('invalid'),
              StackTrace.current,
            ),
    );

    expect(
      await command.execute((id: -1, value: 'x')),
      isA<CommandExecutionFailed<int, _ExpectedFailure>>(),
    );
    expect(command.state, isA<CommandFailureState<int, _ExpectedFailure>>());
    expect(command.reset(), isTrue);
    expect(
      await command.execute((id: 1, value: 'abc')),
      isA<CommandExecutionSucceeded<int, _ExpectedFailure>>(),
    );
    command.dispose();
  });

  test('dispose cancels and prevents stale notification', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final command = Command0<int, _ExpectedFailure>.cancellable((
      CancellationSignal signal,
    ) async {
      started.complete();
      await release.future;
      signal.throwIfCancelled();
      return const Ok<int>(1);
    });
    var notifications = 0;
    command.addListener(() => notifications += 1);

    final execution = command.execute();
    await started.future;
    command.dispose();
    release.complete();

    expect(
      await execution,
      isA<CommandExecutionCancelled<int, _ExpectedFailure>>(),
    );
    expect(notifications, 1);
    expect(command.isDisposed, isTrue);
    expect(
      (await command.execute()
              as CommandExecutionRejected<int, _ExpectedFailure>)
          .reason,
      CommandRejectionReason.disposed,
    );
  });

  test('unexpected crash reports once and retains original stack', () async {
    final reporter = _Reporter();
    late StackTrace thrownStack;
    final command = Command0<int, _ExpectedFailure>(
      () async => throw StateError('broken invariant'),
      reporter: reporter,
    );

    try {
      await command.execute();
      fail('Expected command crash.');
    } catch (_, stackTrace) {
      thrownStack = stackTrace;
    }

    final state = command.state as CommandCrashState<int, _ExpectedFailure>;
    expect(reporter.calls, 1);
    expect(state.stackTrace.toString(), thrownStack.toString());
    command.dispose();
  });

  test('join returns one identical Future and runs once', () async {
    final completion = Completer<Result<int, _ExpectedFailure>>();
    var calls = 0;
    final command = Command0<int, _ExpectedFailure>(() {
      calls += 1;
      return completion.future;
    }, concurrency: const CommandConcurrency.join());

    final first = command.execute();
    final joined = command.execute();
    expect(joined, same(first));
    expect(command.state.runningCount, 1);
    completion.complete(const Ok<int>(1));
    await first;
    expect(calls, 1);
    await command.disposeAsync();
  });

  test('drop and bounded sequential queue expose control outcomes', () async {
    final dropGate = Completer<Result<int, _ExpectedFailure>>();
    final dropping = Command0<int, _ExpectedFailure>(
      () => dropGate.future,
      concurrency: const CommandConcurrency.drop(),
    );
    final activeDrop = dropping.execute();
    expect(
      await dropping.execute(),
      isA<CommandExecutionDropped<int, _ExpectedFailure>>(),
    );
    dropGate.complete(const Ok<int>(1));
    await activeDrop;
    await dropping.disposeAsync();

    final gates = <Completer<Result<int, _ExpectedFailure>>>[
      Completer<Result<int, _ExpectedFailure>>(),
      Completer<Result<int, _ExpectedFailure>>(),
    ];
    var calls = 0;
    final sequential = Command0<int, _ExpectedFailure>(
      () => gates[calls++].future,
      concurrency: const CommandConcurrency.sequential(maxQueue: 1),
    );
    final first = sequential.execute();
    final second = sequential.execute();
    final overflow = await sequential.execute();
    expect(sequential.state.runningCount, 1);
    expect(sequential.state.queuedCount, 1);
    expect(
      (overflow as CommandExecutionRejected<int, _ExpectedFailure>).reason,
      CommandRejectionReason.queueFull,
    );
    gates[0].complete(const Ok<int>(1));
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    gates[1].complete(const Ok<int>(2));
    await second;
    expect(sequential.state.runningCount, 0);
    expect(sequential.state.queuedCount, 0);
    await sequential.disposeAsync();
  });

  test('restartLatest cancels stale terminal publication', () async {
    final gates = <Completer<void>>[Completer<void>(), Completer<void>()];
    var calls = 0;
    final command = Command0<int, _ExpectedFailure>.cancellable((signal) async {
      final current = calls++;
      await gates[current].future;
      signal.throwIfCancelled();
      return Ok<int>(current);
    }, concurrency: const CommandConcurrency.restartLatest());

    final first = command.execute();
    final second = command.execute();
    expect(
      await first,
      isA<CommandExecutionCancelled<int, _ExpectedFailure>>(),
    );
    gates[1].complete();
    final accepted =
        await second as CommandExecutionSucceeded<int, _ExpectedFailure>;
    expect(accepted.value, 1);
    gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    final state = command.state as CommandSuccessState<int, _ExpectedFailure>;
    expect(state.value, 1);
    expect(state.executionId, command.state.latestAcceptedExecutionId);
    await command.disposeAsync();
  });

  test(
    'concurrent bounds and terminal execution ordering remain stable',
    () async {
      final gates = <Completer<Result<int, _ExpectedFailure>>>[
        Completer<Result<int, _ExpectedFailure>>(),
        Completer<Result<int, _ExpectedFailure>>(),
      ];
      var calls = 0;
      final command = Command0<int, _ExpectedFailure>(
        () => gates[calls++].future,
        concurrency: const CommandConcurrency.concurrent(maxConcurrent: 2),
      );
      final first = command.execute();
      final second = command.execute();
      final rejected = await command.execute();
      expect(command.state.runningCount, 2);
      expect(
        (rejected as CommandExecutionRejected<int, _ExpectedFailure>).reason,
        CommandRejectionReason.concurrentLimit,
      );

      gates[1].complete(const Ok<int>(2));
      final secondResult =
          await second as CommandExecutionSucceeded<int, _ExpectedFailure>;
      gates[0].complete(const Ok<int>(1));
      await first;
      final state = command.state as CommandSuccessState<int, _ExpectedFailure>;
      expect(state.value, 2);
      expect(state.executionId, secondResult.executionId);
      await command.disposeAsync();
    },
  );

  test(
    'dedicated keyed command bounds active keys and queues per key',
    () async {
      final gates = <Completer<Result<int, _ExpectedFailure>>>[
        Completer<Result<int, _ExpectedFailure>>(),
        Completer<Result<int, _ExpectedFailure>>(),
      ];
      var calls = 0;
      final command = KeyedCommand1<String, int, int, _ExpectedFailure>(
        (key, argument, signal) => gates[calls++].future,
        concurrency: const CommandConcurrency.keyed(
          perKey: CommandConcurrency.sequential(maxQueue: 1),
          maxConcurrent: 1,
        ),
      );
      final first = command.execute('a', 1);
      final queued = command.execute('a', 2);
      final otherKey = await command.execute('b', 3);
      expect(command.activeKeyCount, 1);
      expect(command.state.queuedCount, 1);
      expect(
        (otherKey as CommandExecutionRejected<int, _ExpectedFailure>).reason,
        CommandRejectionReason.keyLimit,
      );
      gates[0].complete(const Ok<int>(1));
      await first;
      await Future<void>.delayed(Duration.zero);
      gates[1].complete(const Ok<int>(2));
      await queued;
      expect(command.activeKeyCount, 0);
      await command.disposeAsync();
    },
  );
}

final class _Reporter implements CommandCrashReporter {
  var calls = 0;

  @override
  void report(Object error, StackTrace stackTrace) => calls += 1;
}

final class _ExpectedFailure implements Exception {
  const _ExpectedFailure(this.message);

  final String message;
}
