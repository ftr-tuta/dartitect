import '../domain/tasks_model.dart';
import 'tasks_remote_dto.dart';

final class TasksMapper {
  const TasksMapper();

  Task fromRemote(TasksRemoteDto dto) => Task(
    id: dto.id,
    title: dto.title,
    version: dto.version,
    status: TaskStatus.values.byName(dto.status),
  );
}
