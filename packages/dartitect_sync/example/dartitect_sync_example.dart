import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

Future<void> main() async {
  final localNotes = <String>[];
  final checkpoints = _MemoryCheckpoints<String, int>();
  final engine = SyncEngine<String, int, _SyncFailure>(
    datasets: <SyncDataset<String, int, _SyncFailure>>[
      SyncDataset<String, int, _SyncFailure>(
        key: 'notes',
        synchronize: (context) async {
          context.cancellation.throwIfCancelled();
          // Remote data is committed to the local source before checkpointing.
          localNotes.add('Offline-first note');
          return const Ok<SyncDatasetOutcome<int>>(
            SyncDatasetOutcome<int>.checkpoint(1),
          );
        },
      ),
      SyncDataset<String, int, _SyncFailure>(
        key: 'search_index',
        synchronize: (context) async {
          context.cancellation.throwIfCancelled();
          return const Ok<SyncDatasetOutcome<int>>(
            SyncDatasetOutcome<int>.checkpoint(1),
          );
        },
      ),
    ],
    graph: SyncDependencyGraph<String>(
      keys: const <String>['notes', 'search_index'],
      dependencies: const <String, List<String>>{
        'search_index': <String>['notes'],
      },
    ),
    checkpoints: checkpoints,
  );

  final report = await engine.start().done;
  assert(report.succeeded);
  assert(localNotes.single == 'Offline-first note');
  await engine.disposeAsync();
}

final class _SyncFailure implements Exception {
  const _SyncFailure();
}

final class _MemoryCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  final Map<K, C> _values = <K, C>{};

  @override
  Future<C?> read(K key, CancellationSignal signal) async => _values[key];

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    _values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    _values[key] = checkpoint;
  }
}
