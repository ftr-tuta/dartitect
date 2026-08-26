import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:objectbox/objectbox.dart';

/// Consumer-generated ObjectBox journal persistence callbacks.
///
/// The callbacks bridge generated entity types while this adapter enforces the
/// borrowed-Store transaction boundary.
final class ObjectBoxSyncRunJournal<K> implements SyncRunJournal<K> {
  /// Creates a durable journal adapter over a borrowed [store].
  const ObjectBoxSyncRunJournal({
    required this.store,
    required this.appendEntry,
    required this.readIncompleteAttempts,
  });

  /// Borrowed ObjectBox Store.
  final Store store;

  /// Persists one entry in the active write transaction.
  final void Function(Store store, SyncJournalEntry<K> entry) appendEntry;

  /// Reconstructs incomplete attempts in the active read transaction.
  final List<IncompleteSyncAttempt<K>> Function(Store store)
  readIncompleteAttempts;

  @override
  Future<void> append(SyncJournalEntry<K> entry) async {
    store.runInTransaction<void>(TxMode.write, () => appendEntry(store, entry));
  }

  @override
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts() async =>
      List<IncompleteSyncAttempt<K>>.unmodifiable(
        store.runInTransaction<List<IncompleteSyncAttempt<K>>>(
          TxMode.read,
          () => readIncompleteAttempts(store),
        ),
      );
}
