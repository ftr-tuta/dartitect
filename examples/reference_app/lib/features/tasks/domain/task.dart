import 'package:dartitect_sync/dartitect_sync.dart';

/// Pure-Dart task entity used by the offline-first reference workload.
final class Task {
  /// Creates an immutable task.
  const Task({
    required this.id,
    required this.title,
    this.completed = false,
    this.version = 1,
    this.syncState = EntitySyncState.synced,
  });

  /// Stable in-memory identifier.
  final int id;

  /// User-visible task title.
  final String title;

  /// Whether work is complete.
  final bool completed;

  /// Projection version used by [LiveCollection].
  final int version;

  /// Durable local synchronization state.
  final EntitySyncState syncState;

  /// Returns a locally changed copy.
  Task withCompletion(bool value, EntitySyncState state) => Task(
    id: id,
    title: title,
    completed: value,
    version: version + 1,
    syncState: state,
  );
}
