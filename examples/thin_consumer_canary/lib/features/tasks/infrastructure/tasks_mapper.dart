import '../domain/tasks_model.dart';
import 'tasks_remote_dto.dart';

Task mapTasksRemoteDto(TasksRemoteDto dto) => Task(
  id: dto.id,
  title: dto.title,
  version: dto.version,
  status: TaskStatus.values.byName(dto.status),
);
