import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/tasks_repository.dart';

SyncDataset<String, int, TasksFailure> createTasksDataset() => SyncDataset(
  key: 'tasks',
  synchronize: (context) async {
    context.cancellation.throwIfCancelled();
    return Ok<SyncDatasetOutcome<int>>(
      SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
    );
  },
);
