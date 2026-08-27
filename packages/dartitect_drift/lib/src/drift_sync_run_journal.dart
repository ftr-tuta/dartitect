import 'dart:async';

import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:drift/drift.dart';

import 'drift_instrumentation.dart';

/// Appends a journal entry through consumer-owned schema and serialization.
typedef DriftJournalAppender<K, D extends GeneratedDatabase> =
    FutureOr<void> Function(D database, SyncJournalEntry<K> entry);

/// Reconstructs incomplete attempts through consumer-owned queries.
typedef DriftIncompleteAttemptsReader<K, D extends GeneratedDatabase> =
    FutureOr<List<IncompleteSyncAttempt<K>>> Function(D database);

/// Drift-backed journal adapter over a borrowed generated database.
final class DriftSyncRunJournal<K, D extends GeneratedDatabase>
    implements SyncRunJournal<K> {
  /// Creates a journal from consumer-owned persistence callbacks.
  const DriftSyncRunJournal({
    required this.database,
    required this.appendEntry,
    required this.readIncompleteAttempts,
    this.instrumentation,
  });

  /// Borrowed consumer-generated database.
  final D database;

  /// Consumer-owned append callback.
  final DriftJournalAppender<K, D> appendEntry;

  /// Consumer-owned recovery callback.
  final DriftIncompleteAttemptsReader<K, D> readIncompleteAttempts;

  /// Optional borrowed instrumentation.
  final DriftInstrumentation? instrumentation;

  @override
  Future<void> append(SyncJournalEntry<K> entry) async {
    Future<void> execute() =>
        database.transaction<void>(() async => appendEntry(database, entry));
    final tracing = instrumentation;
    if (tracing == null) {
      await execute();
    } else {
      await tracing.trace(DriftInstrumentedOperation.journalAppend, execute);
    }
  }

  @override
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts() async {
    Future<List<IncompleteSyncAttempt<K>>> execute() =>
        database.transaction<List<IncompleteSyncAttempt<K>>>(
          () async => List<IncompleteSyncAttempt<K>>.unmodifiable(
            await readIncompleteAttempts(database),
          ),
        );
    final tracing = instrumentation;
    return tracing == null
        ? execute()
        : tracing.trace(DriftInstrumentedOperation.journalLoad, execute);
  }
}
