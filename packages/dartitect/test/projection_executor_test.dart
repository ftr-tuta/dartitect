@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test(
    'background execution preserves generation and transferable data',
    () async {
      final executor = IsolateProjectionExecutor<TransferableTypedData, int>(
        project: _sumTransferredBytes,
      );
      final cancellation = CancellationSource();

      final result = await executor.execute(
        TransferableProjectionRequest<TransferableTypedData>(
          generation: 7,
          payload: TransferableTypedData.fromList(<TypedData>[
            Uint8List.fromList(<int>[1, 2, 3, 4]),
          ]),
        ),
        cancellation.signal,
      );

      expect(result.generation, 7);
      expect(result.value, 10);
      expect(executor.activeTaskCount, 0);
      cancellation.dispose();
      await executor.disposeAsync();
    },
  );

  test(
    'non-transferable request is rejected without a residual isolate',
    () async {
      final executor = IsolateProjectionExecutor<Object, String>(
        project: _objectType,
      );
      final cancellation = CancellationSource();
      final port = ReceivePort();

      await expectLater(
        executor.execute(
          TransferableProjectionRequest<Object>(generation: 0, payload: port),
          cancellation.signal,
        ),
        throwsA(isA<ProjectionTransferException>()),
      );

      expect(executor.activeTaskCount, 0);
      port.close();
      cancellation.dispose();
      await executor.disposeAsync();
    },
  );

  test('remote crash keeps its stack and worker exit is explicit', () async {
    final crashing = IsolateProjectionExecutor<int, int>(project: _crash);
    final exiting = IsolateProjectionExecutor<int, int>(
      project: _exitWithoutResult,
    );
    final firstCancellation = CancellationSource();
    final secondCancellation = CancellationSource();

    Object? crash;
    StackTrace? crashStack;
    try {
      await crashing.execute(
        const TransferableProjectionRequest<int>(generation: 1, payload: 1),
        firstCancellation.signal,
      );
    } catch (error, stackTrace) {
      crash = error;
      crashStack = stackTrace;
    }
    expect(crash, isA<ProjectionRemoteException>());
    expect('$crash', contains('projection exploded'));
    expect('$crashStack', contains('_crash'));

    await expectLater(
      exiting.execute(
        const TransferableProjectionRequest<int>(generation: 2, payload: 1),
        secondCancellation.signal,
      ),
      throwsA(isA<ProjectionIsolateExitException>()),
    );
    expect(exiting.activeTaskCount, 0);

    firstCancellation.dispose();
    secondCancellation.dispose();
    await crashing.disposeAsync();
    await exiting.disposeAsync();
  });

  test(
    'cancel suppresses result while dispose drains worker cleanup',
    () async {
      final executor = IsolateProjectionExecutor<int, int>(
        project: _slowDouble,
      );
      final cancellation = CancellationSource();
      final future = executor.execute(
        const TransferableProjectionRequest<int>(generation: 3, payload: 4),
        cancellation.signal,
      );

      cancellation.cancel('stale generation');
      await expectLater(future, throwsA(isA<CancellationException>()));
      await executor.disposeAsync();

      expect(executor.activeTaskCount, 0);
      expect(executor.isDisposed, isTrue);
    },
  );
}

int _sumTransferredBytes(TransferableTypedData data) =>
    data.materialize().asUint8List().fold(0, (sum, value) => sum + value);

String _objectType(Object value) => value.runtimeType.toString();

int _crash(int value) => throw StateError('projection exploded: $value');

int _exitWithoutResult(int value) => Isolate.exit();

Future<int> _slowDouble(int value) async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return value * 2;
}
