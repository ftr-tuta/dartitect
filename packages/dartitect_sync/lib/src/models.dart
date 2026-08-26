import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Input supplied to one provider-neutral dataset operation.
final class SyncDatasetContext<K, C> {
  /// Creates a dataset execution context.
  const SyncDatasetContext({
    required this.key,
    required this.runId,
    required this.checkpoint,
    required this.cancellation,
    required this.deadline,
  });

  /// Static dataset identifier.
  final K key;

  /// Consumer-safe run identifier.
  final String runId;

  /// Latest confirmed opaque checkpoint, when present.
  final C? checkpoint;

  /// Cooperative run cancellation.
  final CancellationSignal cancellation;

  /// Optional run deadline.
  final DateTime? deadline;
}

/// Successful dataset outcome with an optional newly confirmed checkpoint.
final class SyncDatasetOutcome<C> {
  /// Completes without advancing a checkpoint.
  const SyncDatasetOutcome.unchanged()
    : checkpoint = null,
      hasCheckpoint = false;

  /// Completes with [checkpoint] to persist before reporting success.
  const SyncDatasetOutcome.checkpoint(this.checkpoint) : hasCheckpoint = true;

  /// Opaque consumer checkpoint.
  final C? checkpoint;

  /// Whether [checkpoint] is present, including a valid nullable checkpoint.
  final bool hasCheckpoint;
}

/// One typed provider-neutral dataset selected by a consumer graph.
final class SyncDataset<K, C, F extends Object> {
  /// Creates a dataset operation.
  const SyncDataset({required this.key, required this.synchronize});

  /// Static dataset identifier used by dependency and progress facts.
  final K key;

  /// Performs one attempt. Expected failures return [Err]; crashes throw.
  final Future<Result<SyncDatasetOutcome<C>, F>> Function(
    SyncDatasetContext<K, C> context,
  )
  synchronize;
}

/// Terminal state of one dataset within a report.
enum SyncDatasetStatus {
  /// Dataset and checkpoint persistence completed.
  succeeded,

  /// Dataset returned an expected typed failure.
  failed,

  /// Dataset did not run because a prerequisite or lease blocked it.
  skipped,

  /// Dataset did not run or finish because the run was cancelled/deadlined.
  cancelled,
}

/// Stable reason for a skipped or cancelled dataset.
enum SyncDatasetStopReason {
  /// A dependency did not succeed.
  blockedDependency,

  /// Another run holds the lease.
  leaseUnavailable,

  /// The current fencing lease expired or could not renew.
  leaseExpired,

  /// Cooperative cancellation was requested.
  cancelled,

  /// The command deadline elapsed.
  deadlineExceeded,
}

/// Immutable result for one dataset.
final class SyncDatasetReport<K, C, F extends Object> {
  /// Creates one dataset report.
  const SyncDatasetReport({
    required this.key,
    required this.status,
    this.failure,
    this.failureStackTrace,
    this.stopReason,
    this.confirmedCheckpoint,
    this.hasConfirmedCheckpoint = false,
  });

  /// Dataset identifier.
  final K key;

  /// Terminal dataset state.
  final SyncDatasetStatus status;

  /// Expected typed failure.
  final F? failure;

  /// Stack captured with [failure].
  final StackTrace? failureStackTrace;

  /// Why work was skipped or cancelled.
  final SyncDatasetStopReason? stopReason;

  /// Checkpoint confirmed by the persistence port.
  final C? confirmedCheckpoint;

  /// Whether [confirmedCheckpoint] is present.
  final bool hasConfirmedCheckpoint;
}

/// Immutable terminal report for one run.
final class SyncReport<K, C, F extends Object> {
  /// Creates a terminal report.
  SyncReport({
    required this.runId,
    required this.startedAt,
    required this.finishedAt,
    required Iterable<SyncDatasetReport<K, C, F>> datasets,
  }) : datasets = List<SyncDatasetReport<K, C, F>>.unmodifiable(datasets);

  /// Consumer-safe run identifier.
  final String runId;

  /// Run start instant.
  final DateTime startedAt;

  /// Terminal instant after lease release was attempted.
  final DateTime finishedAt;

  /// Stable plan-order dataset results.
  final List<SyncDatasetReport<K, C, F>> datasets;

  /// Whether every selected dataset succeeded.
  bool get succeeded => datasets.every(
    (dataset) => dataset.status == SyncDatasetStatus.succeeded,
  );

  /// Whether cancellation or deadline stopped any dataset.
  bool get cancelled =>
      datasets.any((dataset) => dataset.status == SyncDatasetStatus.cancelled);
}

/// Payload-free progress phase.
enum SyncProgressPhase {
  /// Run admitted.
  runStarted,

  /// Dataset operation started.
  datasetStarted,

  /// Dataset operation succeeded.
  datasetSucceeded,

  /// Dataset returned expected failure.
  datasetFailed,

  /// Dataset was skipped.
  datasetSkipped,

  /// Dataset or run was cancelled.
  cancelled,

  /// Run produced a terminal report.
  runCompleted,

  /// Run threw unexpectedly.
  runCrashed,
}

/// Monotonic payload-free progress event.
final class SyncProgressEvent<K> {
  /// Creates a progress event.
  const SyncProgressEvent({
    required this.runId,
    required this.sequence,
    required this.phase,
    required this.timestamp,
    this.key,
  });

  /// Consumer-safe run identifier.
  final String runId;

  /// One-based monotonic sequence within the run.
  final int sequence;

  /// Static lifecycle phase.
  final SyncProgressPhase phase;

  /// UTC event instant.
  final DateTime timestamp;

  /// Static dataset identifier, when the event is dataset-scoped.
  final K? key;
}

/// Read-only progress stream owned and closed by a [SyncRun].
final class SyncProgressStream<K> {
  SyncProgressStream._(this._stream, this._recent);

  final Stream<SyncProgressEvent<K>> _stream;
  final List<SyncProgressEvent<K>> _recent;

  /// Broadcast event stream. Runtime execution never waits for listeners.
  Stream<SyncProgressEvent<K>> get events => _stream;

  /// Bounded recent-event snapshot for diagnostics.
  List<SyncProgressEvent<K>> get recent =>
      List<SyncProgressEvent<K>>.unmodifiable(_recent);
}

/// Engine-owned bounded progress publisher.
///
/// Consumers normally read [SyncRun.progress]; this public seam allows
/// deterministic adapter and contract tests without a global event bus.
final class SyncProgressController<K> {
  /// Creates a publisher with a positive recent-event bound.
  SyncProgressController({required this.maxRecentEvents})
    : _controller = StreamController<SyncProgressEvent<K>>.broadcast(
        sync: true,
      );

  /// Maximum number of events retained by [stream]'s recent snapshot.
  final int maxRecentEvents;
  final StreamController<SyncProgressEvent<K>> _controller;
  final List<SyncProgressEvent<K>> _recent = <SyncProgressEvent<K>>[];

  /// Read-only stream view.
  SyncProgressStream<K> get stream =>
      SyncProgressStream<K>._(_controller.stream, _recent);

  /// Publishes one event without waiting for listeners.
  void add(SyncProgressEvent<K> event) {
    if (_controller.isClosed) return;
    _recent.add(event);
    if (_recent.length > maxRecentEvents) _recent.removeAt(0);
    _controller.add(event);
  }

  /// Closes the stream idempotently.
  Future<void> close() => _controller.close();
}
