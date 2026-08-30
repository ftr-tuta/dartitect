import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';

import '../application/tasks_local_store.dart';
import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';

PullReactiveSource<List<Task>, TasksFailure> createTasksPullSource(
  TasksLocalStore store,
) => PullReactiveSource(
  triggers: <PullInvalidationTrigger>[store.watch],
  pull: store.read,
);
