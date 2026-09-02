import 'package:dartitect/dartitect_incremental.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

Future<void> main() async {
  final checkpoints = _MemoryCheckpoints<String, int>();
  final engine = SyncEngine<String, int, _SyncFailure>(
    datasets: <SyncDataset<String, int, _SyncFailure>>[
      SyncDataset<String, int, _SyncFailure>.incremental(
        key: 'records',
        synchronize: (context) => IncrementalOperation.sync(() sync* {
          final first = (context.checkpoint ?? 0) + 1;
          for (var checkpoint = first; checkpoint < first + 3; checkpoint++) {
            // Commit the corresponding consumer data before yielding.
            yield Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.checkpoint(checkpoint),
            );
          }
        }),
      ),
    ],
    graph: SyncDependencyGraph<String>(keys: const <String>['records']),
    checkpoints: checkpoints,
  );
  try {
    final report = await engine.start().done;
    assert(report.datasets.single.confirmedStepCount == 3);
    assert(checkpoints.values['records'] == 3);
  } finally {
    await engine.disposeAsync();
  }
}

final class _SyncFailure implements Exception {}

final class _MemoryCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  final values = <K, C>{};

  @override
  Future<C?> read(K key, CancellationSignal signal) async => values[key];

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    values[key] = checkpoint;
  }
}
