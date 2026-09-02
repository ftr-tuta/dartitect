import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';

Future<void> main() async {
  final pool = await IsolateWorkerPool.spawn<int, int, _WorkerFailure>(
    size: 2,
    maxInFlight: 4,
    maxQueued: 8,
    handler: _double,
  );
  try {
    final results = await pool
        .mapSequence(Stream<int>.fromIterable(const <int>[1, 2, 3, 4]))
        .toList();
    final values = <int>[
      for (final result in results)
        switch (result) {
          Ok<dynamic>(:final value) => value as int,
          Err<Object>(:final failure) => throw StateError('$failure'),
        },
    ];
    assert(values.join(',') == '2,4,6,8');
  } finally {
    await pool.disposeAsync();
  }
}

Future<Result<int, _WorkerFailure>> _double(
  int value,
  CancellationSignal cancellation,
) async {
  cancellation.throwIfCancelled();
  return Ok<int>(value * 2);
}

final class _WorkerFailure implements Exception {}
