import 'package:dartitect_sync/dartitect_sync.dart';

/// Pure-Dart task entity used by the offline-first reference workload.
final class const Task({
  /// Stable in-memory identifier.
  required final int id,

  /// User-visible task title.
  required final String title,

  /// Whether work is complete.
  final bool completed = false,

  /// Projection version used by [LiveCollection].
  final int version = 1,

  /// Durable local synchronization state.
  final EntitySyncState syncState = EntitySyncState.synced,
}) {
  /// Creates an immutable task.
  this;

  /// Returns a locally changed copy.
  Task withCompletion(bool value, EntitySyncState state) => Task(
    id: id,
    title: title,
    completed: value,
    version: version + 1,
    syncState: state,
  );
}
