// ignore_for_file: public_member_api_docs

import 'package:dartitect/dartitect.dart';

import '../../../app/app_runtime.dart';
import '../../../composition/reference_factories.dart' show ReferenceTransport;
import '../application/offline_first_task_session.dart';

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

final class ReferenceTasksRepository {
  const ReferenceTasksRepository(this.port);

  final ReferenceTasksLocalPort port;

  OfflineFirstTaskSession get session => port.runtime.tasks;
}

final class ReferenceTasksViewModel {
  const ReferenceTasksViewModel(this.repository);

  final ReferenceTasksRepository repository;

  OfflineFirstTaskSession get session => repository.session;
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

  ReferenceTasksRepository createRepository(
    ReferenceTasksLocalPort localPort,
  ) => ReferenceTasksRepository(localPort);

  ReferenceTasksViewModel createViewModel(
    ReferenceTasksRepository repository,
  ) => ReferenceTasksViewModel(repository);
}
