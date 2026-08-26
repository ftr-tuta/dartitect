import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

Future<void> main() async {
  const repetitions = 100;
  for (final datasets in const <int>[1, 10, 100]) {
    final checkpoints = _BenchmarkCheckpoints<int, int>();
    final graph = SyncDependencyGraph<int>(
      keys: List<int>.generate(datasets, (index) => index),
    );
    final definitions = <SyncDataset<int, int, _BenchmarkFailure>>[
      for (var index = 0; index < datasets; index += 1)
        SyncDataset<int, int, _BenchmarkFailure>(
          key: index,
          synchronize: (_) async => Ok<SyncDatasetOutcome<int>>(
            SyncDatasetOutcome<int>.checkpoint(index),
          ),
        ),
    ];
    final watch = Stopwatch()..start();
    for (var run = 0; run < repetitions; run += 1) {
      final engine = SyncEngine<int, int, _BenchmarkFailure>(
        datasets: definitions,
        graph: graph,
        checkpoints: checkpoints,
      );
      await engine.start().done;
      await engine.disposeAsync();
    }
    watch.stop();
    final us = watch.elapsedMicroseconds / repetitions;
    // ignore: avoid_print
    print('$datasets datasets: ${us.toStringAsFixed(2)} us/run');
  }

  final snapshotWatch = Stopwatch()..start();
  final snapshots = <ResourceSnapshot<int, int>>[
    for (var index = 0; index < 10000; index += 1)
      ResourceSnapshot<int, int>(
        value: index,
        metadata: index,
        revision: index,
        observedAt: DateTime.utc(2026),
        isStale: false,
      ),
  ];
  snapshotWatch.stop();
  assert(snapshots.length == 10000);
  // ignore: avoid_print
  print('10000 snapshots: ${snapshotWatch.elapsedMicroseconds.toString()} us');
}

final class _BenchmarkFailure implements Exception {}

final class _BenchmarkCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  final Map<K, C> values = <K, C>{};

  @override
  Future<C?> read(K key, CancellationSignal signal) async => values[key];

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    values[key] = checkpoint;
  }
}
