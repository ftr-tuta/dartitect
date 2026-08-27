import 'package:dartitect/dartitect.dart';
import 'package:dartitect_drift/dartitect_drift.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../lib/infrastructure/provider_database.dart';

void main() {
  test('consumer schema composes Drift transactions and sync ports', () async {
    final owner = await DriftDatabaseOwner.create<ProviderDatabase>(
      openDatabase: () => ProviderDatabase(NativeDatabase.memory()),
    );
    addTearDown(owner.disposeAsync);
    final transaction = DriftMutationTransaction<ProviderDatabase>(
      owner.database,
    );
    final checkpoints = DriftSyncCheckpointStore<String, int, ProviderDatabase>(
      database: owner.database,
      readCheckpoint: (database, key) async => (await (database.select(
        database.providerCheckpoints,
      )..where((row) => row.key.equals(key))).getSingleOrNull())?.checkpoint,
      writeCheckpoint: (database, key, checkpoint, fencingToken) async {
        await database
            .into(database.providerCheckpoints)
            .insertOnConflictUpdate(
              ProviderCheckpointsCompanion.insert(
                key: key,
                checkpoint: checkpoint,
              ),
            );
      },
      removeCheckpoint: (database, key) async {
        await (database.delete(
          database.providerCheckpoints,
        )..where((row) => row.key.equals(key))).go();
      },
    );
    expect(checkpoints, isA<SyncCheckpointStore<String, int>>());

    expect(
      await transaction.run<void, StateError>((database) async {
        await database
            .into(database.providerRows)
            .insert(
              ProviderRowsCompanion.insert(id: 'one', value: 'consumer-owned'),
            );
        return const Ok<void>(null);
      }),
      isA<Ok<void>>(),
    );
    final cancellation = CancellationSource();
    await checkpoints.write('provider', 1, cancellation.signal);
    expect(await checkpoints.read('provider', cancellation.signal), 1);
    cancellation.dispose();
  });
}
