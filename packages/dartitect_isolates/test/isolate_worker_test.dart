import 'dart:async';
import 'dart:isolate';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';
import 'package:test/test.dart';

void main() {
  test('real worker correlates ACK, success, and expected failure', () async {
    final worker = await IsolateWorker.spawn<int, int, _Failure>(
      handler: _handler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(milliseconds: 100),
    );

    final success = worker.send(2, requestId: 'success');
    await success.accepted;
    expect(await success.result, const Ok<int>(4));

    final failure = await worker.execute(-1, requestId: 'failure');
    expect(failure, isA<Err<_Failure>>());
    expect(worker.activeRequestCount, 0);
    await worker.safeStop();
    expect(worker.isDisposed, isTrue);
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

final class _Failure implements Exception {
  const _Failure();

  @override
  bool operator ==(Object other) => other is _Failure;

  @override
  int get hashCode => 1;
}
