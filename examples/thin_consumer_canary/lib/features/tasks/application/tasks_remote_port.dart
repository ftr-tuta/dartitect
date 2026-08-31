import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';
import 'tasks_mutation.dart';

enum TasksRemoteMode { online, offline, conflict, uncertain }

abstract interface class TasksRemotePort {
  TasksRemoteMode get mode;
  set mode(TasksRemoteMode value);

  List<String> get deliveredIdempotencyKeys;

  Future<Result<List<Task>, TasksFailure>> read(
    CancellationSignal cancellation,
  );

  Future<Result<void, TasksFailure>> synchronize(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal cancellation,
  );
}
