import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/task.dart';
import '../domain/task_repository.dart';

/// Search and page cursor transferred across the remote/local pipeline.
final class const TaskCursor({
  /// Case-insensitive title filter.
  final String query = '',

  /// Remote page offset.
  final int offset = 0,
}) {
  /// Creates a typed task cursor.
  this;
}

/// One store-owned query watcher session.
abstract interface class TaskStoreWatch implements AsyncDisposable {
  /// Authoritative local invalidation stream.
  Stream<void> get signals;
}

/// Stable lifecycle counters retained after store disposal for E2E assertions.
final class TaskStoreDiagnostics {
  /// Creates zeroed diagnostics.
  TaskStoreDiagnostics();

  /// Open watcher subscriptions.
  int activeWatchers = 0;

  /// Open ObjectBox or in-memory query handles.
  int activeQueries = 0;

  /// In-flight background projection tasks.
  int activeBackgroundTasks = 0;

  /// Whether store teardown completed.
  bool disposed = false;
}

/// Consumer-owned authoritative local boundary used by the session graph.
abstract interface class OfflineTaskStore
    implements
        MutationOutboxStore<int, TaskMutation, TaskFailure>,
        SyncCheckpointStore<String, int>,
        AsyncDisposable {
  /// Whether this implementation uses a real generated ObjectBox Store.
  bool get isNativeObjectBox;

  /// Lifecycle census that remains readable after disposal.
  TaskStoreDiagnostics get diagnostics;

  /// Durable payload-free sync attempt journal.
  SyncRunJournal<String> get syncJournal;

  /// Seeds a deterministic dataset only when the store is empty.
  Future<void> seed(int count);

  /// Opens one activation-local watcher/query pair.
  Future<TaskStoreWatch> watch();

  /// Selects the local query and visible page window for subsequent reads.
  void select(TaskCursor cursor, {required bool reset});

  /// Reads the authoritative filtered/paged local snapshot.
  Future<Result<PagedLocalSnapshot<int, Task>, TaskFailure>> readSnapshot(
    CancellationSignal signal,
  );

  /// Atomically writes a remote page and returns its local revision.
  Future<Result<PageWriteReceipt<TaskCursor>, TaskFailure>> writePage(
    PageWrite<TaskCursor, Task> write,
    CancellationSignal signal,
  );

  /// Runs a checksum in an explicit background isolate/store wrapper.
  Future<int> backgroundChecksum();

  /// Reads one persisted task for audit/test purposes.
  Future<Task?> findTask(int id);
}
