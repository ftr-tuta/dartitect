import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/foundation.dart';

import '../domain/tasks_repository.dart';

/// Native MVVM state that depends only on the repository contract.
final class TasksViewModel extends ChangeNotifier implements AsyncDisposable {
  TasksViewModel(TasksRepository repository)
    : loadCommand = Command0<List<String>, TasksFailure>(repository.load) {
    loadCommand.addListener(notifyListeners);
  }

  final Command0<List<String>, TasksFailure> loadCommand;

  List<String> get items => switch (loadCommand.state) {
    CommandSuccessState<List<String>, TasksFailure>(:final value) => value,
    CommandCancelledState<List<String>, TasksFailure>() => const <String>[],
    _ => const <String>[],
  };

  Future<void> start() async {
    await loadCommand.execute();
  }

  Future<void>? _disposeFuture;

  @override
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    loadCommand.removeListener(notifyListeners);
    await loadCommand.disposeAsync();
    super.dispose();
  }

  @override
  // The async path calls ChangeNotifier.dispose after draining the command.
  // ignore: must_call_super
  void dispose() => unawaited(disposeAsync());
}
