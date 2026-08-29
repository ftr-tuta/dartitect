import 'package:dartitect/dartitect.dart';

import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';

abstract interface class TasksRemotePort {
  Future<Result<List<Task>, TasksFailure>> read(
    CancellationSignal cancellation,
  );
}
