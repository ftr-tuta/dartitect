import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

import '../domain/task.dart';
import '../domain/task_repository.dart';
import 'offline_task_store.dart';

/// Deterministic transport states exercised by the reference workload.
enum ReferenceRemoteMode {
  /// Requests and mutations succeed.
  online,

  /// Transport is unreachable and mutations remain queued.
  offline,

  /// The server definitively rejects mutations.
  reject,

  /// The server reports a version conflict.
  conflict,

  /// Delivery outcome is intentionally ambiguous.
  uncertain,

  /// An unexpected adapter invariant crashes the mutation lane.
  crash,
}

/// Lifecycle and delivery counters retained for workload assertions.
final class ReferenceRemoteDiagnostics {
  /// Total mutation requests reaching the remote boundary.
  int mutationRequests = 0;

  /// Unique idempotency keys applied by the fake server.
  int appliedDeliveries = 0;

  /// Repeated requests suppressed by the fake server.
  int duplicateDeliveries = 0;

  /// Adapter close calls made by the owned transport.
  int closeCalls = 0;
}

/// Provider-neutral task transport contract owned by the application layer.
abstract interface class TaskRemote implements Disposable {
  /// Stable diagnostics readable after disposal.
  ReferenceRemoteDiagnostics get diagnostics;

  /// Current deterministic remote behavior.
  ReferenceRemoteMode get mode;

  /// Selects the next request behavior without changing local state.
  set mode(ReferenceRemoteMode value);

  /// Fetches one page with cooperative cancellation.
  Future<Result<PageBatch<TaskCursor, Task>, TaskFailure>> requestPage(
    PageRequest<TaskCursor> request,
    CancellationSignal signal,
  );

  /// Delivers one idempotent mutation.
  Future<Result<void, TaskFailure>> synchronize(
    OutboxOperation<int, TaskMutation> operation,
    CancellationSignal signal,
  );
}
