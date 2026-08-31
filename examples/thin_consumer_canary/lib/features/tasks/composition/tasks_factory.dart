import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../../../composition/context_factories.dart'
    show PrimaryCheckpointStore, PrimaryStorage;
import '../application/tasks_local_store.dart';
import '../application/tasks_mutation.dart';
import '../application/tasks_remote_port.dart';
import '../application/tasks_sync_dataset.dart';
import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';
import '../infrastructure/tasks_dio.wiring.dartitect.g.dart';
import '../infrastructure/tasks_mapper.dart';
import '../presentation/tasks_view_model.dart';

final class TasksIdempotencyPolicy
    implements MutationIdempotencyPolicy<String, TasksMutation> {
  const TasksIdempotencyPolicy();

  @override
  String create(String key, TasksMutation argument) =>
      'task:$key:${argument.aggregateId}';
}

final class TasksConflictPolicy implements MutationConflictPolicy<Task> {
  const TasksConflictPolicy();

  @override
  Task resolve(Task local, Task remote) =>
      local.version >= remote.version ? local : remote;
}

final class TasksDioRemotePort implements TasksRemotePort {
  TasksDioRemotePort(this.transport);

  final TasksDioModule transport;
  final List<String> _delivered = <String>[];

  @override
  TasksRemoteMode mode = TasksRemoteMode.offline;

  @override
  List<String> get deliveredIdempotencyKeys =>
      List<String>.unmodifiable(_delivered);

  @override
  Future<Result<List<Task>, TasksFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<List<Task>>(<Task>[]);
  }

  @override
  Future<Result<void, TasksFailure>> synchronize(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    switch (mode) {
      case TasksRemoteMode.online:
        if (!_delivered.contains(operation.idempotencyKey)) {
          _delivered.add(operation.idempotencyKey);
        }
        return const Ok<void>(null);
      case TasksRemoteMode.offline:
        return Err<TasksFailure>(
          const TasksFailure('offline'),
          StackTrace.current,
        );
      case TasksRemoteMode.conflict:
        return Err<TasksFailure>(
          const TasksFailure('conflict'),
          StackTrace.current,
        );
      case TasksRemoteMode.uncertain:
        return Err<TasksFailure>(
          const TasksFailure('uncertain'),
          StackTrace.current,
        );
    }
  }
}

final class OfflineTasksRepository implements TasksRepository, AsyncDisposable {
  const OfflineTasksRepository(this.localStore, this.remotePort, this.mapper);

  final TasksLocalStore localStore;
  final TasksRemotePort remotePort;
  final TasksMapper mapper;

  @override
  Future<Result<List<Task>, TasksFailure>> load() async {
    final cancellation = CancellationSource();
    try {
      return await localStore.read(cancellation.signal);
    } finally {
      cancellation.dispose();
    }
  }

  @override
  Future<void> disposeAsync() async {}
}

@DartitectFeatureFactory('tasks')
final class TasksFactory {
  const TasksFactory();

  TasksLocalStore createLocalPort(PrimaryStorage primary) => primary;

  TasksRemotePort createRemotePort(TasksDioModule api) =>
      TasksDioRemotePort(api);

  TasksMapper createMapper() => const TasksMapper();

  MutationOutboxStore<String, TasksMutation, TasksFailure> createOutboxStore(
    PrimaryStorage primary,
  ) => primary;

  MutationIdempotencyPolicy<String, TasksMutation> createIdempotencyPolicy() =>
      const TasksIdempotencyPolicy();

  MutationConflictPolicy<Task> createConflictPolicy() =>
      const TasksConflictPolicy();

  Future<Result<void, TasksFailure>> synchronizeMutation(
    TasksRemotePort remotePort,
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal cancellation,
  ) => remotePort.synchronize(operation, cancellation);

  MutationFailurePolicy classifyMutationFailure(TasksFailure failure) =>
      switch (failure.code) {
        'conflict' => const MutationFailurePolicy.conflicted(),
        'uncertain' => const MutationFailurePolicy.uncertain(),
        _ => const MutationFailurePolicy.queued(),
      };

  SyncDataset<String, int, TasksFailure> createDataset() =>
      createTasksDataset();

  PrimaryCheckpointStore createCheckpointStore(PrimaryStorage primary) =>
      primary.checkpoints;

  Stream<void> watch(TasksLocalStore localPort) => localPort.watch();

  Future<Result<List<Task>, TasksFailure>> read(
    TasksLocalStore localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);

  OfflineTasksRepository createRepository(
    TasksLocalStore localPort,
    TasksRemotePort remotePort,
    TasksMapper mapper,
  ) => OfflineTasksRepository(localPort, remotePort, mapper);

  TasksViewModel createViewModel(OfflineTasksRepository repository) =>
      TasksViewModel(repository);
}
