import '../domain/tasks_repository.dart';
import '../presentation/tasks_view_model.dart';

/// Explicit provider-aware composition boundary for Tasks.
abstract final class TasksComposition {
  static TasksViewModel createViewModel(TasksRepository repository) =>
      TasksViewModel(repository);
}
