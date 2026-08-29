import 'package:dartitect/dartitect.dart';

import '../application/tasks_remote_port.dart';
import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';

final class FakeTasksRemote implements TasksRemotePort {
  @override
  Future<Result<List<TasksModel>, TasksFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<List<TasksModel>>(<TasksModel>[TasksModel(id: 'fixture')]);
  }
}
