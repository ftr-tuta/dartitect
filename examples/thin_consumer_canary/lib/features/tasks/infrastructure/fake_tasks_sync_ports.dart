import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

final class FakeTasksCheckpoints implements SyncCheckpointStore<String, int> {
  final Map<String, int> values = <String, int>{};

  @override
  Future<int?> read(String key, CancellationSignal signal) async => values[key];

  @override
  Future<void> write(
    String key,
    int checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    values[key] = checkpoint;
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    values.remove(key);
  }
}
