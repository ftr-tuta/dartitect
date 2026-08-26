import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:objectbox/objectbox.dart';

/// Reads an opaque consumer checkpoint in an ObjectBox transaction.
typedef ObjectBoxCheckpointReader<K, C> = C? Function(Store store, K key);

/// Writes an opaque consumer checkpoint in an ObjectBox transaction.
typedef ObjectBoxCheckpointWriter<K, C> = void Function(
  Store store,
  K key,
  C checkpoint,
  int? fencingToken,
);

/// Removes an opaque consumer checkpoint in an ObjectBox transaction.
typedef ObjectBoxCheckpointRemover<K> = void Function(Store store, K key);

/// ObjectBox-backed checkpoint port with consumer-owned entity/codec policy.
///
/// The [Store] is borrowed. Entity annotations, generated code, key encoding,
/// encryption, and retention remain in consumer callbacks. Each operation is
/// cancellation-checked and transactionally bounded.
final class ObjectBoxSyncCheckpointStore<K, C>
    implements SyncCheckpointStore<K, C> {
  /// Creates a checkpoint port over a borrowed [store].
  const ObjectBoxSyncCheckpointStore({
    required this.store,
    required this.readCheckpoint,
    required this.writeCheckpoint,
    required this.removeCheckpoint,
  });

  /// Borrowed consumer-created ObjectBox Store.
  final Store store;

  /// Consumer checkpoint reader.
  final ObjectBoxCheckpointReader<K, C> readCheckpoint;

  /// Consumer checkpoint writer.
  final ObjectBoxCheckpointWriter<K, C> writeCheckpoint;

  /// Consumer checkpoint remover.
  final ObjectBoxCheckpointRemover<K> removeCheckpoint;

  @override
  Future<C?> read(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    final result = store.runInTransaction<C?>(
      TxMode.read,
      () => readCheckpoint(store, key),
    );
    signal.throwIfCancelled();
    return result;
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    store.runInTransaction<void>(
      TxMode.write,
      () => writeCheckpoint(store, key, checkpoint, fencingToken),
    );
    signal.throwIfCancelled();
  }

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    store.runInTransaction<void>(
      TxMode.write,
      () => removeCheckpoint(store, key),
    );
    signal.throwIfCancelled();
  }
}
