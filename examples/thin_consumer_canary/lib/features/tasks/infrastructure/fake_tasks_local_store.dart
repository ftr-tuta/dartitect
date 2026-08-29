import 'dart:async';

import 'package:dartitect/dartitect.dart';

import '../application/tasks_local_store.dart';
import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';

final class FakeTasksLocalStore implements TasksLocalStore {
  final StreamController<void> changes = StreamController<void>.broadcast();
  final List<TasksModel> values = <TasksModel>[];

  @override
  Stream<void> watch() => changes.stream;

  @override
  Future<Result<List<TasksModel>, TasksFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return Ok<List<TasksModel>>(List.unmodifiable(values));
  }

  Future<void> dispose() => changes.close();
}
