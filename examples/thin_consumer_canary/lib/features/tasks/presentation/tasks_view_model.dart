import 'package:dartitect_flutter/dartitect_flutter.dart';

import '../domain/tasks_repository.dart';

/// Native MVVM state that depends only on the repository contract.
final class TasksViewModel(TasksRepository repository)
    extends DartitectViewModel {
  /// Owns the repository command for this ViewModel lifetime.
  this {
    loadCommand = ownCommand(
      Command0<List<String>, TasksFailure>(repository.load),
      label: 'loadCommand',
    );
  }

  late final Command0<List<String>, TasksFailure> loadCommand;

  List<String> get items => switch (loadCommand.state) {
    CommandSuccessState<List<String>, TasksFailure>(:final value) => value,
    CommandCancelledState<List<String>, TasksFailure>() => const <String>[],
    _ => const <String>[],
  };

  Future<void> start() async {
    await loadCommand.execute();
  }
}
