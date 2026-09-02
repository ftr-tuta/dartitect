import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';
import 'package:test/test.dart';

void main() {
  test('pool enforces in-flight and FIFO queue bounds', () async {
    final started = ReceivePort();
    final pool = await IsolateWorkerPool.spawn<_PoolTask, int, _Failure>(
      size: 1,
      maxInFlight: 1,
      maxQueued: 2,
      handler: _poolTaskHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(seconds: 1),
    );

    final first = pool.execute((
      value: 1,
      delayMilliseconds: 80,
      started: started.sendPort,
    ));
    final second = pool.execute((
      value: 2,
      delayMilliseconds: 5,
      started: started.sendPort,
    ));
    final third = pool.execute((
      value: 3,
      delayMilliseconds: 5,
      started: started.sendPort,
    ));

    expect(pool.activeRequestCount, 1);
    expect(pool.queuedRequestCount, 2);
    expect(
      () => pool.execute((
        value: 4,
        delayMilliseconds: 1,
        started: started.sendPort,
      )),
      throwsA(isA<IsolateWorkerPoolCapacityException>()),
    );

    final startOrder = await started.take(3).cast<int>().toList();
    expect(startOrder, <int>[1, 2, 3]);
    expect(
      await Future.wait(<Future<Result<int, _Failure>>>[first, second, third]),
      <Result<int, _Failure>>[
        const Ok<int>(1),
        const Ok<int>(2),
        const Ok<int>(3),
      ],
    );
    expect(pool.activeRequestCount, 0);
    expect(pool.queuedRequestCount, 0);
    started.close();
    await pool.disposeAsync();
    expect(pool.isDisposed, isTrue);
  });

  test('pool runs no more than maxInFlight requests', () async {
    final started = ReceivePort();
    final pool = await IsolateWorkerPool.spawn<_PoolTask, int, _Failure>(
      size: 2,
      maxInFlight: 2,
      maxQueued: 1,
      handler: _poolTaskHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(seconds: 1),
    );

    final requests = <Future<Result<int, _Failure>>>[
      for (var value = 1; value <= 3; value += 1)
        pool.execute((
          value: value,
          delayMilliseconds: 40,
          started: started.sendPort,
        )),
    ];
    await started.take(2).toList();
    expect(pool.activeRequestCount, 2);
    expect(pool.queuedRequestCount, 1);
    await Future.wait(requests);

    started.close();
    await pool.disposeAsync();
  });

  test('mapSequence preserves order or emits completion order', () async {
    final pool = await IsolateWorkerPool.spawn<_DelayTask, int, _Failure>(
      size: 2,
      maxInFlight: 3,
      maxQueued: 1,
      handler: _delayTaskHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(seconds: 1),
    );
    final tasks = <_DelayTask>[
      (value: 1, delayMilliseconds: 80),
      (value: 2, delayMilliseconds: 5),
      (value: 3, delayMilliseconds: 20),
    ];

    final ordered = await pool
        .mapSequence(Stream<_DelayTask>.fromIterable(tasks))
        .toList();
    final completionOrder = await pool
        .mapSequence(
          Stream<_DelayTask>.fromIterable(tasks),
          preserveOrder: false,
        )
        .toList();

    expect(_okValues(ordered), <int>[1, 2, 3]);
    expect(_okValues(completionOrder), <int>[2, 3, 1]);
    await pool.disposeAsync();
  });

  test('mapSequence pauses input at total admission capacity', () async {
    var discovered = 0;
    Stream<_DelayTask> input() async* {
      for (var value = 1; value <= 5; value += 1) {
        discovered += 1;
        yield (value: value, delayMilliseconds: 60);
      }
    }

    final pool = await IsolateWorkerPool.spawn<_DelayTask, int, _Failure>(
      size: 1,
      maxInFlight: 1,
      maxQueued: 1,
      handler: _delayTaskHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(seconds: 1),
    );
    final mapped = pool.mapSequence(input()).toList();

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(discovered, lessThanOrEqualTo(2));
    expect(_okValues(await mapped), <int>[1, 2, 3, 4, 5]);
    await pool.disposeAsync();
  });

  test('losing the map consumer cancels input and drains requests', () async {
    final started = ReceivePort();
    final cleaned = ReceivePort();
    var inputCancelled = false;
    late StreamController<_CleanupTask> input;
    input = StreamController<_CleanupTask>(
      onListen: () {
        input.add((started: started.sendPort, cleaned: cleaned.sendPort));
      },
      onCancel: () {
        inputCancelled = true;
      },
    );
    final pool = await IsolateWorkerPool.spawn<_CleanupTask, int, _Failure>(
      size: 1,
      maxInFlight: 1,
      maxQueued: 1,
      handler: _cleanupTaskHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(seconds: 1),
    );
    final subscription = pool
        .mapSequence(input.stream)
        .listen((_) {}, onError: (Object _, StackTrace _) {});
    await started.first;

    await subscription.cancel();

    expect(inputCancelled, isTrue);
    expect(await cleaned.first, 'cleaned');
    expect(pool.activeRequestCount, 0);
    expect(pool.queuedRequestCount, 0);
    await input.close();
    started.close();
    cleaned.close();
    await pool.disposeAsync();
  });

  test('failPool is terminal after an unexpected worker exit', () async {
    final pool = await IsolateWorkerPool.spawn<int, int, _Failure>(
      size: 1,
      maxInFlight: 1,
      maxQueued: 1,
      handler: _crashingHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(seconds: 1),
    );

    await expectLater(
      pool.execute(0),
      throwsA(isA<IsolateUnexpectedExitException>()),
    );
    expect(pool.isAccepting, isFalse);
    expect(
      () => pool.execute(2),
      throwsA(isA<IsolateWorkerPoolTerminalException>()),
    );
    await pool.disposeAsync();
    expect(pool.isDisposed, isTrue);
  });

  test(
    'replaceWorker never replays a request and enforces its budget',
    () async {
      final observed = ReceivePort();
      final observedValues = StreamIterator<int>(observed.cast<int>());
      final pool = await IsolateWorkerPool.spawn<_CrashTask, int, _Failure>(
        size: 1,
        maxInFlight: 1,
        maxQueued: 1,
        handler: _crashTaskHandler,
        crashPolicy: const IsolateWorkerCrashPolicy.replaceWorker(1),
        heartbeatInterval: const Duration(milliseconds: 10),
        heartbeatTimeout: const Duration(seconds: 1),
      );

      await expectLater(
        pool.execute((value: 1, crash: true, observed: observed.sendPort)),
        throwsA(isA<IsolateUnexpectedExitException>()),
      );
      final successful = pool.execute((
        value: 2,
        crash: false,
        observed: observed.sendPort,
      ));
      expect(await successful, const Ok<int>(2));
      expect(await observedValues.moveNext(), isTrue);
      expect(observedValues.current, 1);
      expect(await observedValues.moveNext(), isTrue);
      expect(observedValues.current, 2);
      expect(pool.replacementCount, 1);

      await expectLater(
        pool.execute((value: 3, crash: true, observed: observed.sendPort)),
        throwsA(isA<IsolateUnexpectedExitException>()),
      );
      expect(pool.isAccepting, isFalse);
      expect(
        () =>
            pool.execute((value: 4, crash: false, observed: observed.sendPort)),
        throwsA(isA<IsolateWorkerPoolTerminalException>()),
      );
      expect(await observedValues.moveNext(), isTrue);
      expect(observedValues.current, 3);
      await observedValues.cancel();
      observed.close();
      await pool.disposeAsync();
    },
  );

  test('disposeAsync drains admitted work before stopping workers', () async {
    final started = ReceivePort();
    final pool = await IsolateWorkerPool.spawn<_PoolTask, int, _Failure>(
      size: 1,
      maxInFlight: 1,
      maxQueued: 1,
      handler: _poolTaskHandler,
      heartbeatInterval: const Duration(milliseconds: 10),
      heartbeatTimeout: const Duration(seconds: 1),
    );
    final first = pool.execute((
      value: 1,
      delayMilliseconds: 40,
      started: started.sendPort,
    ));
    final second = pool.execute((
      value: 2,
      delayMilliseconds: 5,
      started: started.sendPort,
    ));

    final disposal = pool.disposeAsync();
    expect(pool.isAccepting, isFalse);
    expect(
      () => pool.execute((
        value: 3,
        delayMilliseconds: 1,
        started: started.sendPort,
      )),
      throwsA(isA<IsolateWorkerPoolClosedException>()),
    );
    expect(await first, const Ok<int>(1));
    expect(await second, const Ok<int>(2));
    await disposal;

    expect(pool.isDisposed, isTrue);
    expect(pool.activeRequestCount, 0);
    expect(pool.queuedRequestCount, 0);
    started.close();
  });

  test(
    'TransferableTypedData crosses the pool without materialization',
    () async {
      final pool =
          await IsolateWorkerPool.spawn<
            TransferableTypedData,
            TransferableTypedData,
            _Failure
          >(
            size: 1,
            maxInFlight: 1,
            maxQueued: 0,
            handler: _transferHandler,
            heartbeatInterval: const Duration(milliseconds: 10),
            heartbeatTimeout: const Duration(seconds: 1),
          );
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 255]);

      final result = await pool.execute(
        TransferableTypedData.fromList(<TypedData>[bytes]),
      );

      expect(result, isA<Ok<TransferableTypedData>>());
      final transferred = (result as Ok<TransferableTypedData>).value;
      expect(transferred.materialize().asUint8List(), bytes);
      await pool.disposeAsync();
    },
  );

  test('pool validates all runtime bounds without asserts', () async {
    await expectLater(
      IsolateWorkerPool.spawn<int, int, _Failure>(
        size: 0,
        maxInFlight: 1,
        maxQueued: 0,
        handler: _crashingHandler,
      ),
      throwsArgumentError,
    );
    await expectLater(
      IsolateWorkerPool.spawn<int, int, _Failure>(
        size: 1,
        maxInFlight: 0,
        maxQueued: 0,
        handler: _crashingHandler,
      ),
      throwsArgumentError,
    );
    await expectLater(
      IsolateWorkerPool.spawn<int, int, _Failure>(
        size: 1,
        maxInFlight: 1,
        maxQueued: -1,
        handler: _crashingHandler,
      ),
      throwsArgumentError,
    );
    await expectLater(
      IsolateWorkerPool.spawn<int, int, _Failure>(
        size: 1,
        maxInFlight: 1,
        maxQueued: 0,
        handler: _crashingHandler,
        crashPolicy: const IsolateWorkerCrashPolicy.replaceWorker(0),
      ),
      throwsArgumentError,
    );
  });
}

typedef _PoolTask = ({int value, int delayMilliseconds, SendPort started});
typedef _DelayTask = ({int value, int delayMilliseconds});
typedef _CleanupTask = ({SendPort started, SendPort cleaned});
typedef _CrashTask = ({int value, bool crash, SendPort observed});

Future<Result<int, _Failure>> _poolTaskHandler(
  _PoolTask task,
  CancellationSignal cancellation,
) async {
  task.started.send(task.value);
  await Future<void>.delayed(Duration(milliseconds: task.delayMilliseconds));
  cancellation.throwIfCancelled();
  return Ok<int>(task.value);
}

Future<Result<int, _Failure>> _delayTaskHandler(
  _DelayTask task,
  CancellationSignal cancellation,
) async {
  await Future<void>.delayed(Duration(milliseconds: task.delayMilliseconds));
  cancellation.throwIfCancelled();
  return Ok<int>(task.value);
}

Future<Result<int, _Failure>> _cleanupTaskHandler(
  _CleanupTask task,
  CancellationSignal cancellation,
) async {
  task.started.send('started');
  try {
    await cancellation.whenCancelled;
    cancellation.throwIfCancelled();
    return const Ok<int>(1);
  } finally {
    task.cleaned.send('cleaned');
  }
}

Future<Result<int, _Failure>> _crashingHandler(
  int value,
  CancellationSignal cancellation,
) async {
  if (value == 0) Isolate.exit();
  return Ok<int>(value * 2);
}

Future<Result<int, _Failure>> _crashTaskHandler(
  _CrashTask task,
  CancellationSignal cancellation,
) async {
  task.observed.send(task.value);
  if (task.crash) Isolate.exit();
  return Ok<int>(task.value);
}

Future<Result<TransferableTypedData, _Failure>> _transferHandler(
  TransferableTypedData value,
  CancellationSignal cancellation,
) async => Ok<TransferableTypedData>(value);

List<int> _okValues(List<Result<int, _Failure>> results) => <int>[
  for (final result in results) (result as Ok<int>).value,
];

final class _Failure implements Exception {
  const _Failure();
}
