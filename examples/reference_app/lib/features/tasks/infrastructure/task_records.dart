import 'package:objectbox/objectbox.dart';

/// Consumer-owned persisted task schema for the native reference workload.
@Entity()
final class TaskRecord {
  /// Creates one persisted task row.
  TaskRecord({
    this.id = 0,
    required this.title,
    required this.completed,
    required this.version,
    required this.syncState,
  });

  /// Stable domain key and ObjectBox identifier.
  @Id(assignable: true)
  int id;

  /// Searchable display title.
  String title;

  /// Local completion state.
  bool completed;

  /// Monotonic entity projection version.
  int version;

  /// Persisted [EntitySyncState] name without coupling generated schema to SDK.
  String syncState;
}

/// Consumer-owned durable operation schema.
@Entity()
final class OutboxRecord {
  /// Creates one persisted outbox operation.
  OutboxRecord({
    this.id = 0,
    required this.idempotencyKey,
    required this.taskId,
    required this.completed,
    required this.attempt,
    required this.syncState,
  });

  /// ObjectBox row identifier.
  @Id()
  int id;

  /// Stable at-least-once delivery key.
  String idempotencyKey;

  /// Affected task key.
  int taskId;

  /// Desired completion value.
  bool completed;

  /// Number of started delivery attempts.
  int attempt;

  /// Persisted [EntitySyncState] name.
  String syncState;
}

/// Payload-free durable synchronization journal fact.
@Entity()
final class SyncJournalRecord {
  /// Creates one journal row.
  SyncJournalRecord({
    this.id = 0,
    required this.attemptId,
    required this.sequence,
    required this.timestampMicros,
    required this.fact,
    this.datasetKey = '',
    required this.hasDatasetKey,
  });

  /// ObjectBox row identifier.
  @Id()
  int id;

  /// Consumer-safe attempt ID.
  String attemptId;

  /// Monotonic sequence inside the attempt.
  int sequence;

  /// UTC microseconds since epoch.
  int timestampMicros;

  /// Persisted SyncJournalFact name.
  String fact;

  /// Static dataset key when present.
  String datasetKey;

  /// Distinguishes a nullable key from attempt-level facts.
  bool hasDatasetKey;
}

/// Durable opaque checkpoint and latest accepted fencing token.
@Entity()
final class SyncCheckpointRecord {
  /// Creates one checkpoint row.
  SyncCheckpointRecord({
    this.id = 0,
    required this.datasetKey,
    required this.checkpoint,
    this.fencingToken = 0,
  });

  /// ObjectBox row identifier.
  @Id()
  int id;

  /// Static unique dataset key.
  String datasetKey;

  /// Opaque integer checkpoint for this workload.
  int checkpoint;

  /// Latest accepted fencing token.
  int fencingToken;
}
