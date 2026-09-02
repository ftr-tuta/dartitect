import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/task.dart';
import '../domain/task_repository.dart';
import 'offline_task_store.dart';

/// Provider-neutral, payload-free diagnostics projected by the repository.
final class TaskRepositoryDiagnostics {
  /// Creates one immutable diagnostics snapshot.
  const TaskRepositoryDiagnostics({
    required this.storeKind,
    required this.journalEntries,
    required this.remoteRequests,
    required this.activeWatchers,
    required this.activeQueries,
    required this.activeWorkers,
  });

  /// Selected store engine without paths or provider objects.
  final String storeKind;

  /// Number of bounded causal journal entries.
  final int journalEntries;

  /// Number of requests crossing the remote boundary.
  final int remoteRequests;

  /// Current local watcher count.
  final int activeWatchers;

  /// Current local query count.
  final int activeQueries;

  /// Current isolate worker count.
  final int activeWorkers;
}

/// Provider-neutral local-first boundary consumed by presentation state.
///
/// No ObjectBox, Drift, Dio, Store, session, or generated-provider type crosses
/// this contract. The implementation coordinates exactly one selected store,
/// its outbox/journal, and one remote service.
abstract interface class TaskRepository implements AsyncDisposable {
  /// Authoritative local collection observed by the ViewModel.
  PagedLiveResource<TaskCursor, int, Task, TaskFailure> get tasks;

  /// Whether remote delivery is deliberately disabled.
  bool get isOffline;

  /// Refreshes the current query from its first page.
  Future<CommandOutcome<PageWriteReceipt<TaskCursor>, TaskFailure>> refresh();

  /// Loads the next local-first page.
  Future<CommandOutcome<PageWriteReceipt<TaskCursor>, TaskFailure>> loadMore();

  /// Restarts the aggregate for [query] and publishes only its current result.
  Future<CommandOutcome<PageWriteReceipt<TaskCursor>, TaskFailure>> search(
    String query,
  );

  /// Applies one durable local toggle before remote delivery.
  Future<
    CommandOutcome<
      MutationExecution<TaskMutation, int, void, TaskFailure>,
      TaskFailure
    >
  >
  toggle(int id);

  /// Selects offline/online transport behavior and drains pending work online.
  Future<Result<void, TaskFailure>> setOffline(bool offline);

  /// Records route lifecycle without retaining a Flutter context.
  void setForeground(bool value);

  /// Projects current runtime evidence without exposing provider instances.
  TaskRepositoryDiagnostics diagnosticsSnapshot();
}
