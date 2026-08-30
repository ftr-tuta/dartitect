import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../features/tasks/application/tasks_local_store.dart';
import '../features/tasks/application/tasks_mutation.dart';
import '../features/tasks/domain/tasks_model.dart';
import '../features/tasks/domain/tasks_repository.dart';
import '../features/tasks/infrastructure/tasks_dio.wiring.dartitect.g.dart';

final class PrimaryStorage
    implements
        TasksLocalStore,
        MutationOutboxStore<String, TasksMutation, TasksFailure> {
  PrimaryStorage()
    : _values = <Task>[const Task(id: 'first', title: 'First Task')],
      checkpoints = PrimaryCheckpointStore();

  final List<Task> _values;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final PrimaryCheckpointStore checkpoints;
  final Map<String, OutboxOperation<String, TasksMutation>> _outbox =
      <String, OutboxOperation<String, TasksMutation>>{};
  bool closed = false;

  List<OutboxOperation<String, TasksMutation>> get outbox =>
      List<OutboxOperation<String, TasksMutation>>.unmodifiable(_outbox.values);

  @override
  Stream<void> watch() => _changes.stream;

  @override
  Future<Result<List<Task>, TasksFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<List<Task>>(List<Task>.unmodifiable(_values));
  }

  Future<void> addOffline(Task task) async {
    _values.add(task);
    _changes.add(null);
  }

  @override
  Future<Result<void, TasksFailure>> applyLocalAndEnqueue(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    final index = _values.indexWhere((task) => task.id == operation.key);
    if (index < 0) {
      return Err<TasksFailure>(
        const TasksFailure('missing'),
        StackTrace.current,
      );
    }
    final current = _values[index];
    _values[index] = Task(
      id: current.id,
      title: current.title,
      version: current.version + 1,
      status: current.status == TaskStatus.open
          ? TaskStatus.completed
          : TaskStatus.open,
    );
    _outbox[operation.idempotencyKey] = operation;
    _changes.add(null);
    return const Ok<void>(null);
  }

  @override
  Future<Result<void, TasksFailure>> markState(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    _outbox[operation.idempotencyKey] = operation;
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<OutboxOperation<String, TasksMutation>>, TasksFailure>>
  loadRecoverable(CancellationSignal signal) async {
    signal.throwIfCancelled();
    return Ok<List<OutboxOperation<String, TasksMutation>>>(
      List<OutboxOperation<String, TasksMutation>>.unmodifiable(_outbox.values),
    );
  }

  @override
  Future<Result<void, TasksFailure>> compensate(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal signal,
  ) => applyLocalAndEnqueue(operation, signal);

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _changes.close();
  }
}

final class PrimaryCheckpointStore implements SyncCheckpointStore<String, int> {
  final Map<String, int> _values = <String, int>{};

  @override
  Future<int?> read(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    return _values[key];
  }

  @override
  Future<void> write(
    String key,
    int checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    _values[key] = checkpoint;
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    _values.remove(key);
  }
}

@DartitectApplicationContextFactory('primary')
final class PrimaryStorageFactory {
  const PrimaryStorageFactory();

  Future<PrimaryStorage> open() async => PrimaryStorage();

  Future<void> dispose(PrimaryStorage storage) => storage.close();
}

@DartitectTransportContextFactory('api')
final class ApiTransportFactory {
  const ApiTransportFactory();

  TasksDioModule open() => TasksDioModule.create(
    connectTimeout: const Duration(seconds: 2),
    receiveTimeout: const Duration(seconds: 2),
  );

  void dispose(TasksDioModule transport) => transport.dispose();
}
