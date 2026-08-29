import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_sync_dataset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dataset advances an opaque checkpoint', () async {
    final cancellation = CancellationSource();
    final result = await createTasksDataset().synchronize(
      SyncDatasetContext(
        key: 'tasks',
        runId: 'fixture',
        checkpoint: 1,
        cancellation: cancellation.signal,
        deadline: null,
      ),
    );
    expect((result as Ok<SyncDatasetOutcome<int>>).value.checkpoint, 2);
    cancellation.dispose();
  });
}
