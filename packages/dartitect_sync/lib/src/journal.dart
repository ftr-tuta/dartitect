import 'package:dartitect/dartitect.dart';

/// Payload-free durable fact recorded for one synchronization attempt.
enum SyncJournalFact {
  /// Attempt admission began.
  attemptStarted,

  /// One static dataset began.
  datasetStarted,

  /// Dataset and checkpoint boundary completed.
  datasetSucceeded,

  /// Dataset returned an expected typed failure.
  datasetFailed,

  /// Dataset was skipped by dependency, lease, cancellation, or deadline.
  datasetSkipped,

  /// Attempt reached one terminal report.
  attemptCompleted,

  /// Attempt crashed unexpectedly.
  attemptCrashed,
}

/// One immutable, allowlisted journal entry.
///
/// Entries intentionally contain no checkpoint, failure text, payload,
/// identity, request data, or provider object.
final class SyncJournalEntry<K> extends ValueEquality {
  /// Creates a validated journal fact.
  SyncJournalEntry({
    required this.attemptId,
    required this.sequence,
    required this.timestamp,
    required this.fact,
    this.datasetKey,
    this.hasDatasetKey = false,
  }) {
    if (attemptId.trim().isEmpty) {
      throw ArgumentError.value(attemptId, 'attemptId', 'must not be empty');
    }
    if (sequence <= 0) {
      throw ArgumentError.value(sequence, 'sequence', 'must be positive');
    }
    if (!timestamp.isUtc) {
      throw ArgumentError.value(timestamp, 'timestamp', 'must be UTC');
    }
    final datasetFact = switch (fact) {
      SyncJournalFact.datasetStarted ||
      SyncJournalFact.datasetSucceeded ||
      SyncJournalFact.datasetFailed ||
      SyncJournalFact.datasetSkipped => true,
      _ => false,
    };
    if (datasetFact != hasDatasetKey) {
      throw ArgumentError(
        'Dataset facts require a dataset key and attempt facts forbid one.',
      );
    }
  }

  /// Consumer-safe attempt identifier.
  final String attemptId;

  /// One-based, monotonic sequence within the attempt.
  final int sequence;

  /// UTC fact time.
  final DateTime timestamp;

  /// Closed lifecycle fact.
  final SyncJournalFact fact;

  /// Static dataset key when [hasDatasetKey] is true.
  final K? datasetKey;

  /// Distinguishes a nullable key from an attempt-level fact.
  final bool hasDatasetKey;

  @override
  Iterable<Object?> get equalityFields => <Object?>[
    attemptId,
    sequence,
    timestamp,
    fact,
    datasetKey,
    hasDatasetKey,
  ];
}

/// Durable summary of an attempt that did not record a terminal fact.
final class IncompleteSyncAttempt<K> extends ValueEquality {
  /// Creates an immutable recovery summary.
  IncompleteSyncAttempt({
    required this.attemptId,
    required this.startedAt,
    required Iterable<K> completedDatasetKeys,
  }) : completedDatasetKeys = immutableListCopy(completedDatasetKeys) {
    if (attemptId.trim().isEmpty) {
      throw ArgumentError.value(attemptId, 'attemptId', 'must not be empty');
    }
    if (!startedAt.isUtc) {
      throw ArgumentError.value(startedAt, 'startedAt', 'must be UTC');
    }
  }

  /// Interrupted attempt identifier.
  final String attemptId;

  /// UTC admission time.
  final DateTime startedAt;

  /// Dataset keys whose durable checkpoint boundary completed.
  final List<K> completedDatasetKeys;

  @override
  Iterable<Object?> get equalityFields => <Object?>[
    attemptId,
    startedAt,
    completedDatasetKeys,
  ];
}

/// Consumer-owned durable run journal.
///
/// The adapter validates ordering and atomically persists each entry. Retention,
/// serialization, encryption, and compaction remain consumer policy.
abstract interface class SyncRunJournal<K> {
  /// Appends one fact durably before returning.
  Future<void> append(SyncJournalEntry<K> entry);

  /// Loads interrupted attempts from the last valid durable facts.
  Future<List<IncompleteSyncAttempt<K>>> loadIncompleteAttempts();
}
