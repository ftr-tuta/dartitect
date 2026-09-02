import 'repository_contract.dart';

abstract base class InMemoryTaskStore implements TaskStore {
  @override
  final List<Task> tasks = <Task>[];

  @override
  final List<Task> outbox = <Task>[];

  @override
  Future<void> save(Task task) async => tasks.add(task);

  @override
  Future<void> enqueue(Task task) async => outbox.add(task);
}

final class MemoryTaskStore extends InMemoryTaskStore {}

final class DriftTaskStore extends InMemoryTaskStore {}

final class ObjectBoxTaskStore extends InMemoryTaskStore {}
