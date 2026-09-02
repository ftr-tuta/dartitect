import 'dart:async';
import 'dart:isolate';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';
import 'package:test/test.dart';

void main() {
  test('real worker correlates ACK, success, and expected failure', () async {
    final diagnostics = DartitectDiagnosticBuffer(capacity: 32);
    final emitter = DartitectDiagnosticsEmitter(
      reporter: DartitectDiagnosticReporterRegistration.borrowed(diagnostics),
      detail: DartitectDiagnosticDetail.topology,
    );
    final worker = await IsolateWorker.spawn<int, int, _Failure>(
      handler: _handler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(milliseconds: 100),
      diagnostics: emitter.subject(DartitectDiagnosticSubjectKind.isolate),
    );

    final success = worker.send(2, requestId: 'private-request-sentinel');
    await success.accepted;
    expect(await success.result, const Ok<int>(4));

    final failure = await worker.execute(-1, requestId: 'failure');
    expect(failure, isA<Err<_Failure>>());
    expect(worker.activeRequestCount, 0);
    await worker.safeStop();
    expect(worker.isDisposed, isTrue);
    expect(
      diagnostics.events.map((event) => event.phase),
      containsAll(<DartitectDiagnosticPhase>{
        DartitectDiagnosticPhase.started,
        DartitectDiagnosticPhase.succeeded,
        DartitectDiagnosticPhase.updated,
        DartitectDiagnosticPhase.failed,
        DartitectDiagnosticPhase.disposed,
      }),
    );
    expect(
      '${diagnostics.events.map((event) => event.toJson())}',
      isNot(contains('private-request-sentinel')),
    );
    await emitter.dispose();
    diagnostics.dispose();
  });

  test('remote crash and request deadline terminate exactly once', () async {
    final worker = await IsolateWorker.spawn<int, int, _Failure>(
      handler: _handler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(worker.execute(13), throwsA(isA<RemoteIsolateCrash>()));
    await expectLater(
      worker.execute(99, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<IsolateRequestDeadlineException>()),
    );
    expect(worker.activeRequestCount, 0);
    await worker.disposeAsync();
  });

  test(
    'unexpected isolate exit fails active request and drains supervisor',
    () async {
      final worker = await IsolateWorker.spawn<int, int, _Failure>(
        handler: _handler,
        heartbeatInterval: const Duration(milliseconds: 10),
        heartbeatTimeout: const Duration(milliseconds: 100),
      );

      final receipt = worker.send(77, requestId: 'unexpected-exit');
      await receipt.accepted;
      await expectLater(
        receipt.result,
        throwsA(isA<IsolateUnexpectedExitException>()),
      );
      expect(worker.activeRequestCount, 0);
      expect(worker.isDisposed, isTrue);
      await Future.wait<void>(<Future<void>>[
        worker.disposeAsync(),
        worker.disposeAsync(),
      ]);
      expect(worker.activeRequestCount, 0);
    },
  );

  test('rejects stale protocol before spawning', () async {
    await expectLater(
      IsolateWorker.spawn<int, int, _Failure>(
        handler: _handler,
        protocolVersion: 99,
      ),
      throwsArgumentError,
    );
  });

  test('late response cannot complete a reused public request ID', () async {
    final worker =
        await IsolateWorker.spawn<
          ({int value, int delayMilliseconds}),
          int,
          _Failure
        >(
          handler: _delayedHandler,
          heartbeatInterval: const Duration(milliseconds: 10),
          heartbeatTimeout: const Duration(seconds: 1),
        );

    final first = worker.send(
      (value: 1, delayMilliseconds: 80),
      requestId: 'reused',
      timeout: const Duration(milliseconds: 20),
    );
    await first.accepted;
    _blockEventLoop(const Duration(milliseconds: 120));
    await expectLater(
      first.result,
      throwsA(isA<IsolateRequestDeadlineException>()),
    );

    final second = worker.send(
      (value: 2, delayMilliseconds: 160),
      requestId: 'reused',
      timeout: const Duration(seconds: 1),
    );
    await second.accepted;
    final secondOutcome = await second.result;
    expect(secondOutcome, isA<Ok<int>>());
    expect((secondOutcome as Ok<int>).value, 2);
    expect(worker.activeRequestCount, 0);
    await worker.safeStop();
  });

  test(
    'awaiting only result does not leave an unobserved acceptance error',
    () async {
      final worker = await IsolateWorker.spawn<Object, Object, _Failure>(
        handler: _objectHandler,
        heartbeatInterval: const Duration(milliseconds: 10),
        heartbeatTimeout: const Duration(milliseconds: 100),
      );
      final unsendable = ReceivePort();
      final unobserved = <Object>[];

      await runZonedGuarded(() async {
        await expectLater(worker.execute(unsendable), throwsArgumentError);
        await Future<void>.delayed(Duration.zero);
      }, (error, stackTrace) => unobserved.add(error));

      expect(unobserved, isEmpty);
      unsendable.close();
      await worker.safeStop();
    },
  );

  test('safeStop remains bounded for a non-cooperative handler', () async {
    final worker =
        await IsolateWorker.spawn<
          ({int value, int delayMilliseconds}),
          int,
          _Failure
        >(
          handler: _delayedHandler,
          heartbeatInterval: const Duration(milliseconds: 10),
          heartbeatTimeout: const Duration(seconds: 1),
        );
    final receipt = worker.send(
      (value: 3, delayMilliseconds: 5000),
      requestId: 'non-cooperative',
      timeout: const Duration(seconds: 10),
    );
    await receipt.accepted;
    final stopwatch = Stopwatch()..start();

    await worker.safeStop(deadline: const Duration(milliseconds: 30));

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    await expectLater(
      receipt.result,
      throwsA(isA<IsolateUnexpectedExitException>()),
    );
    expect(worker.isDisposed, isTrue);
    expect(worker.activeRequestCount, 0);
    await worker.safeStop(deadline: const Duration(milliseconds: 30));
  });

  test('optional cancellation waits for remote handler cleanup', () async {
    final finished = ReceivePort();
    final cancellation = CancellationSource();
    final worker = await IsolateWorker.spawn<SendPort, int, _Failure>(
      handler: _cancellableHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(milliseconds: 100),
    );
    final receipt = worker.send(
      finished.sendPort,
      cancellation: cancellation.signal,
    );
    await receipt.accepted;

    cancellation.cancel('test');
    await expectLater(receipt.result, throwsA(isA<CancellationException>()));

    expect(await finished.first, 'finished');
    expect(worker.activeRequestCount, 0);
    finished.close();
    await worker.disposeAsync();
  });
}

Future<Result<int, _Failure>> _handler(
  int value,
  CancellationSignal cancellation,
) async {
  if (value == 99) {
    await cancellation.whenCancelled;
    cancellation.throwIfCancelled();
  }
  if (value == 77) Isolate.exit();
  if (value == 13) throw StateError('remote crash');
  if (value < 0) return Err<_Failure>(const _Failure(), StackTrace.current);
  return Ok<int>(value * 2);
}

Future<Result<int, _Failure>> _delayedHandler(
  ({int value, int delayMilliseconds}) request,
  CancellationSignal cancellation,
) async {
  await Future<void>.delayed(Duration(milliseconds: request.delayMilliseconds));
  return Ok<int>(request.value);
}

Future<Result<Object, _Failure>> _objectHandler(
  Object value,
  CancellationSignal cancellation,
) async => Ok<Object>(value);

Future<Result<int, _Failure>> _cancellableHandler(
  SendPort finished,
  CancellationSignal cancellation,
) async {
  try {
    await cancellation.whenCancelled;
    cancellation.throwIfCancelled();
    return const Ok<int>(1);
  } finally {
    finished.send('finished');
  }
}

void _blockEventLoop(Duration duration) {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < duration) {}
}

final class _Failure implements Exception {
  const _Failure();

  @override
  bool operator ==(Object other) => other is _Failure;

  @override
  int get hashCode => 1;
}
