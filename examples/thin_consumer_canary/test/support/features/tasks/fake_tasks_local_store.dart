import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_local_store.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_model.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';

final class FakeTasksLocalStore implements TasksLocalStore {
  final StreamController<void> changes = StreamController<void>.broadcast();
  final List<Task> values = <Task>[];

  @override
  Stream<void> watch() => changes.stream;

  @override
  Future<Result<List<Task>, TasksFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<List<Task>>(List.unmodifiable(values));
  }

  Future<void> dispose() => changes.close();
}
