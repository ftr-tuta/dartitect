// ignore_for_file: public_member_api_docs

import 'package:dartitect/dartitect.dart';

import '../../../app/app_runtime.dart';
import '../../../composition/reference_factories.dart' show ReferenceTransport;
import '../application/offline_first_task_session.dart';
import '../presentation/tasks_view_model.dart';

final class ReferenceTasksLocalPort {
  const ReferenceTasksLocalPort(this.runtime);

  final AppRuntime runtime;
}

final class ReferenceTasksLocalAuthority {
  const ReferenceTasksLocalAuthority(this.port);

  final ReferenceTasksLocalPort port;
}

final class ReferenceTasksRemotePort {
  const ReferenceTasksRemotePort(this.transport);

  final ReferenceTransport transport;
}

final class ReferenceTasksMapper {
  const ReferenceTasksMapper();
}

@DartitectFeatureFactory('tasks')
final class TasksFactory {
  const TasksFactory();

  ReferenceTasksLocalPort createLocalPort(AppRuntime referenceRuntime) =>
      ReferenceTasksLocalPort(referenceRuntime);

  ReferenceTasksLocalAuthority createLocalAuthority(
    ReferenceTasksLocalPort localPort,
  ) => ReferenceTasksLocalAuthority(localPort);

  ReferenceTasksRemotePort createRemotePort(
    ReferenceTransport referenceTransport,
  ) => ReferenceTasksRemotePort(referenceTransport);

  ReferenceTasksMapper createMapper() => const ReferenceTasksMapper();

  LocalFirstTaskRepository createRepository(
    ReferenceTasksLocalPort localPort,
  ) => localPort.runtime.tasks;

  TasksViewModel createViewModel(LocalFirstTaskRepository repository) =>
      TasksViewModel(repository);
}
