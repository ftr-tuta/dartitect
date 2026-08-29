import 'package:dartitect/dartitect.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_remote_port.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_model.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';

final class FakeTasksRemote implements TasksRemotePort {
  @override
  Future<Result<List<Task>, TasksFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<List<Task>>(<Task>[
      Task(id: 'fixture', title: 'Fixture task'),
    ]);
  }
}
