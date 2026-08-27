import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:drift/drift.dart';

import 'drift_instrumentation.dart';

/// Reads an opaque checkpoint using consumer-owned Drift schema and codecs.
typedef DriftCheckpointReader<K, C, D extends GeneratedDatabase> =
    FutureOr<C?> Function(D database, K key);

/// Writes an opaque checkpoint and receives the fencing token unchanged.
typedef DriftCheckpointWriter<K, C, D extends GeneratedDatabase> =
    FutureOr<void> Function(D database, K key, C checkpoint, int? fencingToken);

/// Removes an opaque checkpoint using consumer-owned policy.
typedef DriftCheckpointRemover<K, D extends GeneratedDatabase> =
    FutureOr<void> Function(D database, K key);

/// Drift-backed checkpoint port with no SDK-owned schema or token policy.
final class DriftSyncCheckpointStore<K, C, D extends GeneratedDatabase>
    implements SyncCheckpointStore<K, C> {
  /// Creates a checkpoint adapter over a borrowed [database].
  const DriftSyncCheckpointStore({
    required this.database,
    required this.readCheckpoint,
    required this.writeCheckpoint,
    required this.removeCheckpoint,
    this.instrumentation,
  });

  /// Borrowed consumer-generated database.
  final D database;

  /// Consumer-owned checkpoint reader.
  final DriftCheckpointReader<K, C, D> readCheckpoint;

  /// Consumer-owned checkpoint writer.
  final DriftCheckpointWriter<K, C, D> writeCheckpoint;

  /// Consumer-owned checkpoint remover.
  final DriftCheckpointRemover<K, D> removeCheckpoint;

  /// Optional borrowed instrumentation.
  final DriftInstrumentation? instrumentation;

  @override
  Future<C?> read(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    Future<C?> execute() =>
        database.transaction<C?>(() async => readCheckpoint(database, key));
    final tracing = instrumentation;
    final value = tracing == null
        ? await execute()
        : await tracing.trace(
            DriftInstrumentedOperation.checkpointRead,
            execute,
          );
    signal.throwIfCancelled();
    return value;
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    Future<void> execute() => database.transaction<void>(
      () async => writeCheckpoint(database, key, checkpoint, fencingToken),
    );
    final tracing = instrumentation;
    if (tracing == null) {
      await execute();
    } else {
      await tracing.trace(DriftInstrumentedOperation.checkpointWrite, execute);
    }
  }

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    Future<void> execute() =>
        database.transaction<void>(() async => removeCheckpoint(database, key));
    final tracing = instrumentation;
    if (tracing == null) {
      await execute();
    } else {
      await tracing.trace(DriftInstrumentedOperation.checkpointRemove, execute);
    }
  }
}
