import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:test/test.dart';

void main() {
  test('manifest validates unique datasets and contiguous migrations', () {
    OperationalDatasetRegistration registration(String feature) =>
        OperationalDatasetRegistration(
          feature: feature,
          dataset: 'tasks',
          partition: 'account_partition',
          codec: 'tasks_v1',
          retention: 'P30D',
          transactionBoundary: 'tasks_transaction',
        );

    final manifest = OperationalStorageContextManifest(
      context: 'primary',
      provider: 'drift',
      schemaVersion: 2,
      datasets: <OperationalDatasetRegistration>[registration('tasks')],
      migrations: <OperationalStorageMigration>[
        OperationalStorageMigration(
          fromVersion: 1,
          toVersion: 2,
          id: 'context_scoped_operational_tables',
        ),
      ],
    );
    expect(manifest.datasets.single.dataset, 'tasks');

    expect(
      () => OperationalStorageContextManifest(
        context: 'primary',
        provider: 'drift',
        schemaVersion: 2,
        datasets: <OperationalDatasetRegistration>[
          registration('tasks'),
          registration('other'),
        ],
        migrations: manifest.migrations,
      ),
      throwsArgumentError,
    );
  });

  test('public metadata invariants remain active in release mode', () {
    expect(
      () => OperationalDatasetRegistration(
        feature: 'Tasks',
        dataset: 'tasks',
        partition: 'default_partition',
        codec: 'tasks_v1',
        retention: 'forever',
        transactionBoundary: 'tasks_transaction',
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          OperationalStorageMigration(fromVersion: 1, toVersion: 3, id: 'skip'),
      throwsArgumentError,
    );
  });
}
