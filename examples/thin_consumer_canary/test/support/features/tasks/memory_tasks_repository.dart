import 'package:dartitect/dartitect.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_model.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';

/// Deterministic memory implementation owned by the composition root.
final class MemoryTasksRepository implements TasksRepository {
  MemoryTasksRepository([
    Iterable<Task> values = const <Task>[
      Task(id: 'first', title: 'First Task'),
    ],
  ]) : _values = List<Task>.of(values);

  final List<Task> _values;

  @override
  Future<Result<List<Task>, TasksFailure>> load() async =>
      Ok<List<Task>>(List<Task>.unmodifiable(_values));
}
