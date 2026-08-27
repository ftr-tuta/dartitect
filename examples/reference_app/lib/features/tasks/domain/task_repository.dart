/// Expected task failure handled by the feature.
sealed class TaskFailure implements Exception {
  /// Creates an expected failure with a safe [message].
  const TaskFailure(this.message);

  /// Safe user-facing failure description.
  final String message;
}

/// Network is unavailable and the durable operation remains queued.
final class TaskOfflineFailure extends TaskFailure {
  /// Creates a safe offline failure.
  const TaskOfflineFailure() : super('Offline; local change is queued.');
}

/// Remote policy definitively rejected the mutation.
final class TaskRejectedFailure extends TaskFailure {
  /// Creates a safe rejection.
  const TaskRejectedFailure() : super('Remote policy rejected the change.');
}

/// Local and remote versions require explicit reconciliation.
final class TaskConflictFailure extends TaskFailure {
  /// Creates a safe conflict failure.
  const TaskConflictFailure() : super('A conflict requires reconciliation.');
}

/// Delivery may have committed and must be audited before retry.
final class TaskUncertainFailure extends TaskFailure {
  /// Creates a safe uncertain-delivery failure.
  const TaskUncertainFailure()
    : super('Delivery outcome is uncertain; audit before retry.');
}

/// Local persistence failed without exposing its path or payload.
final class TaskStorageFailure extends TaskFailure {
  /// Creates a safe storage failure.
  const TaskStorageFailure() : super('Local persistence failed.');
}

/// Causal local observation did not arrive inside the bounded window.
final class TaskObservationTimeoutFailure extends TaskFailure {
  /// Creates a safe observation timeout.
  const TaskObservationTimeoutFailure() : super('Local observation timed out.');
}

/// Immutable desired task state persisted in the consumer outbox.
final class const TaskMutation({
  /// Affected task key.
  required final int taskId,

  /// Desired completion value, making duplicate delivery idempotent.
  required final bool completed,
}) {
  /// Creates a mutation for one task.
  this;
}
