import 'package:dartitect/dartitect.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';

/// Deterministic memory implementation owned by the composition root.
final class MemoryTasksRepository implements TasksRepository {
  MemoryTasksRepository([
    Iterable<String> values = const <String>['First Tasks'],
  ]) : _values = List<String>.of(values);

  final List<String> _values;

  @override
  Future<Result<List<String>, TasksFailure>> load() async =>
      Ok<List<String>>(List<String>.unmodifiable(_values));
}
