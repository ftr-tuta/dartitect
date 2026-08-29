import '../domain/tasks_model.dart';
import 'tasks_remote_dto.dart';

TasksModel mapTasksRemoteDto(TasksRemoteDto dto) =>
    TasksModel(id: dto.id, labels: <String>[dto.label]);
