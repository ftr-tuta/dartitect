import 'package:dartitect/dartitect.dart';

import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';

abstract interface class TasksRemotePort {
  Future<Result<List<TasksModel>, TasksFailure>> read(
    CancellationSignal cancellation,
  );
}
