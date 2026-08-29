import 'package:dartitect_flutter/dartitect_flutter.dart';

import '../domain/tasks_model.dart';
import '../domain/tasks_repository.dart';

/// Native MVVM state that depends only on the repository contract.
final class TasksViewModel(TasksRepository repository)
    extends DartitectViewModel {
  /// Owns the repository command for this ViewModel lifetime.
  this {
    loadCommand = ownCommand(
      Command0<List<Task>, TasksFailure>(repository.load),
      label: 'loadCommand',
    );
  }

  late final Command0<List<Task>, TasksFailure> loadCommand;

  List<Task> get items => switch (loadCommand.state) {
    CommandSuccessState<List<Task>, TasksFailure>(:final value) => value,
    CommandCancelledState<List<Task>, TasksFailure>() => const <Task>[],
    _ => const <Task>[],
  };

  Future<void> start() async {
    await loadCommand.execute();
  }
}
