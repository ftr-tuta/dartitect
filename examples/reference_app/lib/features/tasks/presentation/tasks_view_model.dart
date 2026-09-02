import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../application/offline_task_store.dart';
import '../application/task_repository.dart';
import '../domain/task.dart';
import '../domain/task_repository.dart';

/// Stable presentation result for one local-first mutation.
enum TaskMutationPresentation {
  /// Local change and remote acknowledgement both completed.
  synchronized,

  /// Local change is durable and waiting in the outbox.
  queued,

  /// Remote policy requires explicit review.
  review,

  /// Delivery requires an explicit audit before retry.
  audit,
}

/// Transient, route-owned reactions emitted by [TasksViewModel].
sealed class TasksEffect {
  const TasksEffect();
}

/// Requests a mounted route to present mutation feedback.
final class TasksMutationEffect extends TasksEffect {
  /// Creates one mutation feedback effect.
  const TasksMutationEffect(this.result);

  /// Payload-free mutation disposition.
  final TaskMutationPresentation result;
}

/// Requests a mounted route to navigate to projected diagnostics.
final class OpenTasksDiagnosticsEffect extends TasksEffect {
  /// Creates a diagnostics navigation effect.
  const OpenTasksDiagnosticsEffect(this.data);

  /// Immutable projection with no provider or session objects.
  final TasksDiagnosticsViewData data;
}

/// Values safe for diagnostics presentation and previews.
final class TasksDiagnosticsViewData {
  /// Creates one immutable presentation projection.
  const TasksDiagnosticsViewData({
    required this.storeKind,
    required this.journalEntries,
    required this.remoteRequests,
    required this.activeWatchers,
    required this.activeQueries,
    required this.activeWorkers,
  });

  /// Stable selected-engine label.
  final String storeKind;

  /// Current bounded journal size.
  final int journalEntries;

  /// Current remote request count.
  final int remoteRequests;

  /// Current watcher count.
  final int activeWatchers;

  /// Current query count.
  final int activeQueries;

  /// Current background worker count.
  final int activeWorkers;
}

/// MVVM owner for task commands, effects, selection, and presentation state.
final class TasksViewModel extends DartitectViewModel {
  /// Creates presentation state around a borrowed provider-neutral repository.
  TasksViewModel(this._repository) {
    forward(_repository.tasks, label: 'tasks');
    refreshCommand = ownCommand(
      Command0(_refresh, concurrency: const CommandConcurrency.join()),
      label: 'refreshCommand',
    );
    loadMoreCommand = ownCommand(
      Command0(_loadMore, concurrency: const CommandConcurrency.drop()),
      label: 'loadMoreCommand',
    );
    searchCommand = ownCommand(
      Command1<String, PageWriteReceipt<TaskCursor>, TaskFailure>.cancellable(
        _search,
        concurrency: const CommandConcurrency.restartLatest(),
      ),
      label: 'searchCommand',
    );
    toggleCommand = ownCommand(
      KeyedCommand1<int, int, TaskMutationPresentation, TaskFailure>(
        _toggle,
        concurrency: const CommandConcurrency.keyed(
          perKey: CommandConcurrency.sequential(maxQueue: 4),
          maxConcurrent: 8,
        ),
      ),
      label: 'toggleCommand',
    );
    connectivityCommand = ownCommand(
      Command1<bool, void, TaskFailure>(
        _setOffline,
        concurrency: const CommandConcurrency.restartLatest(),
      ),
      label: 'connectivityCommand',
    );
    effects = own(
      EffectChannel<TasksEffect>(
        capacity: 8,
        owner: EffectOwnerIdentity(
          kind: EffectOwnerKind.route,
          generation: Object(),
        ),
      ),
      (channel) => channel.disposeAsync(),
      label: 'tasksEffects',
    );
  }

  final TaskRepository _repository;

  /// Authoritative incremental local collection borrowed by [TasksView].
  PagedLiveResource<TaskCursor, int, Task, TaskFailure> get tasks =>
      _repository.tasks;

  /// Refresh command using a joining lane.
  late final Command0<PageWriteReceipt<TaskCursor>, TaskFailure> refreshCommand;

  /// Load-more command dropping reentrant requests.
  late final Command0<PageWriteReceipt<TaskCursor>, TaskFailure>
  loadMoreCommand;

  /// Restart-latest query command.
  late final Command1<String, PageWriteReceipt<TaskCursor>, TaskFailure>
  searchCommand;

  /// Bounded independent per-row mutation lanes.
  late final KeyedCommand1<int, int, TaskMutationPresentation, TaskFailure>
  toggleCommand;

  /// Restart-latest connectivity transition.
  late final Command1<bool, void, TaskFailure> connectivityCommand;

  /// Bounded route-effect channel consumed only while mounted.
  late final EffectChannel<TasksEffect> effects;

  String _query = '';
  int? _selectedTaskId;
  var _started = false;

  /// Current normalized query retained across responsive layout changes.
  String get query => _query;

  /// Selected row retained across responsive layout changes.
  int? get selectedTaskId => _selectedTaskId;

  /// Selected item projected from the authoritative collection.
  Task? get selectedTask {
    final id = _selectedTaskId;
    return id == null ? null : tasks.collection.item(id).value;
  }

  /// Current connectivity choice without exposing the remote adapter.
  bool get isOffline => _repository.isOffline;

  /// Starts the local-first aggregate once.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(refreshCommand.execute());
  }

  /// Selects a row without mutating domain state.
  void selectTask(int id) {
    if (_selectedTaskId == id) return;
    _selectedTaskId = id;
    notifyListeners();
  }

  /// Emits a navigation request containing only projected diagnostics.
  void openDiagnostics() {
    final snapshot = _repository.diagnosticsSnapshot();
    effects.sink.emit(
      OpenTasksDiagnosticsEffect(
        TasksDiagnosticsViewData(
          storeKind: snapshot.storeKind,
          journalEntries: snapshot.journalEntries,
          remoteRequests: snapshot.remoteRequests,
          activeWatchers: snapshot.activeWatchers,
          activeQueries: snapshot.activeQueries,
          activeWorkers: snapshot.activeWorkers,
        ),
      ),
    );
  }

  /// Forwards route lifecycle without exposing repository internals.
  void setForeground(bool value) => _repository.setForeground(value);

  Future<Result<PageWriteReceipt<TaskCursor>, TaskFailure>> _refresh() async =>
      _pageResult(await _repository.refresh());

  Future<Result<PageWriteReceipt<TaskCursor>, TaskFailure>> _loadMore() async =>
      _pageResult(await _repository.loadMore());

  Future<Result<PageWriteReceipt<TaskCursor>, TaskFailure>> _search(
    String query,
    CancellationSignal cancellation,
  ) async {
    final normalized = query.trim();
    final result = _pageResult(await _repository.search(normalized));
    cancellation.throwIfCancelled();
    _query = normalized;
    notifyListeners();
    return result;
  }

  Future<Result<TaskMutationPresentation, TaskFailure>> _toggle(
    int key,
    int id,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final outcome = await _repository.toggle(id);
    cancellation.throwIfCancelled();
    return switch (outcome) {
      CommandSucceeded<
        MutationExecution<TaskMutation, int, void, TaskFailure>,
        TaskFailure
      >(
        :final value,
      ) =>
        _mutationResult(value.disposition),
      CommandFailed<Object?, TaskFailure>(:final failure, :final stackTrace) =>
        Err<TaskFailure>(failure, stackTrace),
      _ => Err<TaskFailure>(const TaskStorageFailure(), StackTrace.current),
    };
  }

  Result<TaskMutationPresentation, TaskFailure> _mutationResult(
    CommitDisposition disposition,
  ) {
    final result = switch (disposition) {
      CommitDisposition.committed => TaskMutationPresentation.synchronized,
      CommitDisposition.queued => TaskMutationPresentation.queued,
      CommitDisposition.rejected => TaskMutationPresentation.review,
      CommitDisposition.uncertain => TaskMutationPresentation.audit,
    };
    effects.sink.emit(TasksMutationEffect(result));
    return Ok<TaskMutationPresentation>(result);
  }

  Future<Result<void, TaskFailure>> _setOffline(bool offline) =>
      _repository.setOffline(offline);

  Result<PageWriteReceipt<TaskCursor>, TaskFailure> _pageResult(
    CommandOutcome<PageWriteReceipt<TaskCursor>, TaskFailure> outcome,
  ) => switch (outcome) {
    CommandSucceeded<PageWriteReceipt<TaskCursor>, TaskFailure>(:final value) =>
      Ok<PageWriteReceipt<TaskCursor>>(value),
    CommandFailed<PageWriteReceipt<TaskCursor>, TaskFailure>(
      :final failure,
      :final stackTrace,
    ) =>
      Err<TaskFailure>(failure, stackTrace),
    _ => Err<TaskFailure>(const TaskStorageFailure(), StackTrace.current),
  };
}
