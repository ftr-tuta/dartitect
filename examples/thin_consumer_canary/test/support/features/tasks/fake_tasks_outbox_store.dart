import 'package:dartitect/dartitect.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_mutation.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';

final class FakeTasksOutboxStore
    implements MutationOutboxStore<String, TasksMutation, TasksFailure> {
  final Map<String, OutboxOperation<String, TasksMutation>> rows =
      <String, OutboxOperation<String, TasksMutation>>{};

  @override
  Future<Result<void, TasksFailure>> applyLocalAndEnqueue(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    rows[operation.idempotencyKey] = operation;
    return const Ok<void>(null);
  }

  @override
  Future<Result<void, TasksFailure>> markState(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    rows[operation.idempotencyKey] = operation;
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<OutboxOperation<String, TasksMutation>>, TasksFailure>>
  loadRecoverable(CancellationSignal signal) async {
    signal.throwIfCancelled();
    return Ok(List.unmodifiable(rows.values));
  }

  @override
  Future<Result<void, TasksFailure>> compensate(
    OutboxOperation<String, TasksMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    rows.remove(operation.idempotencyKey);
    return const Ok<void>(null);
  }
}
