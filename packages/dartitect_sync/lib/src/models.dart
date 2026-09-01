import 'dart:async';
import 'dart:collection';

import 'package:dartitect/dartitect.dart';

import 'ports.dart';

/// Input supplied to one provider-neutral dataset operation.
final class SyncDatasetContext<K, C> {
  /// Creates a dataset execution context.
  const SyncDatasetContext({
    required this.key,
    required this.runId,
    required this.checkpoint,
    required this.cancellation,
    required this.deadline,
    this.authority,
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

  /// Current typed lease authority, or `null` when fencing is not configured.
  ///
  /// A consumer whose storage supports fencing passes [SyncAuthority.fencingToken]
  /// into the same atomic transaction as its dataset commit. Calling
  /// [SyncAuthority.ensureAuthority] alone is not an atomic storage fence.
  final SyncAuthority? authority;
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

  /// Some boundary may have applied, but a later required boundary failed.
  incomplete,
}

/// Terminal state of one independently observable sync boundary.
enum SyncBoundaryStatus {
  /// This boundary was not reached.
  notAttempted,

  /// This boundary was not configured or required.
  notRequired,

  /// This boundary completed successfully.
  succeeded,

  /// This boundary failed and retains its original error and stack.
  failed,
}

/// Immutable receipt for one application/checkpoint/journal/release boundary.
final class SyncBoundaryReceipt {
  /// Creates a boundary that was not reached.
  const SyncBoundaryReceipt.notAttempted()
    : status = SyncBoundaryStatus.notAttempted,
      error = null,
      stackTrace = null;

  /// Creates a boundary that was not configured or required.
  const SyncBoundaryReceipt.notRequired()
    : status = SyncBoundaryStatus.notRequired,
      error = null,
      stackTrace = null;

  /// Creates a successfully completed boundary.
  const SyncBoundaryReceipt.succeeded()
    : status = SyncBoundaryStatus.succeeded,
      error = null,
      stackTrace = null;

  /// Creates a failed boundary preserving [error] and [stackTrace].
  const SyncBoundaryReceipt.failed(this.error, this.stackTrace)
    : status = SyncBoundaryStatus.failed;

  /// Boundary terminal state.
  final SyncBoundaryStatus status;

  /// Original failure when [status] is [SyncBoundaryStatus.failed].
  final Object? error;

  /// Original failure stack.
  final StackTrace? stackTrace;

  /// Whether this boundary permits a successful run summary.
  bool get isSuccessful =>
      status == SyncBoundaryStatus.succeeded ||
      status == SyncBoundaryStatus.notRequired;
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
    this.application = const SyncBoundaryReceipt.notAttempted(),
    this.checkpoint = const SyncBoundaryReceipt.notAttempted(),
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

  /// Consumer dataset-application boundary.
  final SyncBoundaryReceipt application;

  /// Checkpoint confirmation boundary.
  final SyncBoundaryReceipt checkpoint;
}

/// Immutable terminal report for one run.
final class SyncReport<K, C, F extends Object> {
  /// Creates a terminal report.
  SyncReport({
    required this.runId,
    required this.startedAt,
    required this.finishedAt,
    required Iterable<SyncDatasetReport<K, C, F>> datasets,
    this.journal = const SyncBoundaryReceipt.notRequired(),
    this.leaseRelease = const SyncBoundaryReceipt.notRequired(),
    this.cleanup = const SyncBoundaryReceipt.succeeded(),
  }) : datasets = List<SyncDatasetReport<K, C, F>>.unmodifiable(datasets);

  /// Consumer-safe run identifier.
  final String runId;

  /// Run start instant.
  final DateTime startedAt;

  /// Terminal instant after lease release was attempted.
  final DateTime finishedAt;

  /// Stable plan-order dataset results.
  final List<SyncDatasetReport<K, C, F>> datasets;

  /// Aggregate durable-journal boundary for this run.
  final SyncBoundaryReceipt journal;

  /// Lease-release boundary after all selected work.
  final SyncBoundaryReceipt leaseRelease;

  /// Consumer and engine terminal-cleanup boundary.
  final SyncBoundaryReceipt cleanup;

  /// Whether every selected dataset succeeded.
  bool get succeeded =>
      datasets.every(
        (dataset) => dataset.status == SyncDatasetStatus.succeeded,
      ) &&
      journal.isSuccessful &&
      leaseRelease.isSuccessful &&
      cleanup.isSuccessful;

  /// Whether cancellation or deadline stopped any dataset.
  bool get cancelled =>
      datasets.any((dataset) => dataset.status == SyncDatasetStatus.cancelled);
}

/// Unexpected terminal failure paired with an unambiguous partial receipt.
final class SyncRunTerminalException<K, C, F extends Object>
    implements Exception {
  /// Creates a terminal failure preserving the original [cause].
  const SyncRunTerminalException({
    required this.report,
    required this.cause,
    required this.causeStackTrace,
  });

  /// Complete boundary receipt assembled after release and cleanup attempts.
  final SyncReport<K, C, F> report;

  /// Original unexpected failure.
  final Object cause;

  /// Original failure stack.
  final StackTrace causeStackTrace;

  @override
  String toString() =>
      'SyncRunTerminalException(runId: ${report.runId}; cause: $cause)';
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
  final ListQueue<SyncProgressEvent<K>> _recent;

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
  final ListQueue<SyncProgressEvent<K>> _recent =
      ListQueue<SyncProgressEvent<K>>();

  /// Read-only stream view.
  SyncProgressStream<K> get stream =>
      SyncProgressStream<K>._(_controller.stream, _recent);

  /// Publishes one event without waiting for listeners.
  void add(SyncProgressEvent<K> event) {
    if (_controller.isClosed) return;
    _recent.add(event);
    if (_recent.length > maxRecentEvents) _recent.removeFirst();
    _controller.add(event);
  }

  /// Closes the stream idempotently.
  Future<void> close() => _controller.close();
}
