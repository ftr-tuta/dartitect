final class Task {
  const Task(this.id, this.title);

  final int id;
  final String title;
}

abstract interface class TaskStore {
  List<Task> get tasks;
  List<Task> get outbox;
  Future<void> save(Task task);
  Future<void> enqueue(Task task);
}

abstract interface class TaskRemoteService {
  Future<bool> send(Task task);
}

abstract interface class TaskRepository {
  TaskStore get store;
  Future<void> add(Task task);
}
