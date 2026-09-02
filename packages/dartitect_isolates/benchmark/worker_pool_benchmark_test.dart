import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bounded pool maps 1000 values with and without preserved order',
    () async {
      const count = 1000;
      final pool = await IsolateWorkerPool.spawn<int, int, _Failure>(
        size: 2,
        maxInFlight: 4,
        maxQueued: 28,
        handler: _double,
        heartbeatInterval: const Duration(milliseconds: 50),
        heartbeatTimeout: const Duration(seconds: 2),
      );

      final orderedWatch = Stopwatch()..start();
      final ordered = await pool
          .mapSequence(
            Stream<int>.fromIterable(<int>[
              for (var value = 0; value < count; value++) value,
            ]),
          )
          .toList();
      orderedWatch.stop();
      final unorderedWatch = Stopwatch()..start();
      final unordered = await pool
          .mapSequence(
            Stream<int>.fromIterable(<int>[
              for (var value = 0; value < count; value++) value,
            ]),
            preserveOrder: false,
          )
          .toList();
      unorderedWatch.stop();

      expect(
        _okValues(ordered),
        orderedEquals(<int>[
          for (var value = 0; value < count; value++) value * 2,
        ]),
      );
      expect(_okValues(unordered), hasLength(count));
      expect(_okValues(unordered).toSet(), hasLength(count));
      expect(pool.activeRequestCount, 0);
      expect(pool.queuedRequestCount, 0);
      await pool.disposeAsync();
      expect(pool.isDisposed, isTrue);
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'benchmark': 'incremental-isolate-pool',
          'metrics': 'informative',
          'items': count,
          'orderedTotalMicros': orderedWatch.elapsedMicroseconds,
          'unorderedTotalMicros': unorderedWatch.elapsedMicroseconds,
          'activeAfterDrain': pool.activeRequestCount,
          'queuedAfterDrain': pool.queuedRequestCount,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('transferable bytes stay opaque until the worker endpoint', () async {
    final pool =
        await IsolateWorkerPool.spawn<TransferableTypedData, int, _Failure>(
          size: 1,
          maxInFlight: 1,
          maxQueued: 0,
          handler: _byteLength,
          heartbeatInterval: const Duration(milliseconds: 50),
          heartbeatTimeout: const Duration(seconds: 2),
        );
    final payload = TransferableTypedData.fromList(<Uint8List>[
      Uint8List(1024 * 1024),
    ]);

    final watch = Stopwatch()..start();
    final result = await pool.execute(payload);
    watch.stop();

    expect(result, const Ok<int>(1024 * 1024));
    await pool.disposeAsync();
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'benchmark': 'incremental-transferable-bytes',
        'metrics': 'informative',
        'bytes': 1024 * 1024,
        'totalMicros': watch.elapsedMicroseconds,
      }),
    );
  });
}

Future<Result<int, _Failure>> _double(
  int value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value * 2);
}

Future<Result<int, _Failure>> _byteLength(
  TransferableTypedData value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value.materialize().lengthInBytes);
}

List<int> _okValues(Iterable<Result<int, _Failure>> results) => <int>[
  for (final result in results)
    switch (result) {
      Ok<dynamic>(:final value) => value as int,
      Err<Object>() => throw StateError('Unexpected typed benchmark failure.'),
    },
];

final class _Failure implements Exception {}
