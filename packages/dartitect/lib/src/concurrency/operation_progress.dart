import 'dart:collection';

import '../lifecycle/contracts.dart';
import 'cancellation.dart';

/// One typed progress publication from an accepted operation execution.
final class OperationProgress<P> {
  /// Creates an immutable execution-scoped progress envelope.
  const OperationProgress({
    required this.executionId,
    required this.sequence,
    required this.payload,
  }) : assert(executionId > 0),
       assert(sequence > 0);

  /// Positive identity assigned when the operation was accepted.
  final int executionId;

  /// Positive, execution-local monotonic publication sequence.
  final int sequence;

  /// Operation-specific progress value.
  final P payload;

  @override
  bool operator ==(Object other) =>
      other is OperationProgress<P> &&
      executionId == other.executionId &&
      sequence == other.sequence &&
      payload == other.payload;

  @override
  int get hashCode => Object.hash(executionId, sequence, payload);
}

/// Synchronous destination for typed operation progress.
///
/// Returning `false` rejects a stale, out-of-order, disposed, or otherwise
/// unretained event. A reporter must never make operation success depend on a
/// diagnostic destination.
abstract interface class ProgressReporter<P> {
  /// Publishes [progress] if it belongs to the accepted execution boundary.
  bool report(OperationProgress<P> progress);
}

/// Progress destination that deliberately retains nothing.
final class NoOpProgressReporter<P> implements ProgressReporter<P> {
  /// Creates a no-op destination.
  const NoOpProgressReporter();

  @override
  bool report(OperationProgress<P> progress) => true;
}

/// Failure-isolating wrapper for a consumer-owned progress reporter.
final class SafeProgressReporter<P> implements ProgressReporter<P> {
  /// Wraps [reporter] and optionally reports its first failure.
  SafeProgressReporter({
    required ProgressReporter<P> reporter,
    void Function(Object error, StackTrace stackTrace)? onFailure,
  }) : _reporter = reporter,
       _onFailure = onFailure;

  final ProgressReporter<P> _reporter;
  final void Function(Object error, StackTrace stackTrace)? _onFailure;
  var _disabled = false;
  var _emitting = false;
  var _failureCount = 0;
  var _droppedReentrantCount = 0;

  /// Number of destination failures observed before disablement.
  int get failureCount => _failureCount;

  /// Number of recursive publications rejected.
  int get droppedReentrantCount => _droppedReentrantCount;

  /// Whether the destination has failed and is no longer called.
  bool get isDisabled => _disabled;

  @override
  bool report(OperationProgress<P> progress) {
    if (_disabled) return false;
    if (_emitting) {
      _droppedReentrantCount += 1;
      return false;
    }
    _emitting = true;
    try {
      return _reporter.report(progress);
    } catch (error, stackTrace) {
      _failureCount += 1;
      _disabled = true;
      try {
        _onFailure?.call(error, stackTrace);
      } on Object {
        // Reporting progress failure cannot affect operation behavior.
        return false;
      }
      return false;
    } finally {
      _emitting = false;
    }
  }
}

/// Bounded, memory-only progress ring fenced to the latest execution.
///
/// The first event selects an execution. A greater execution ID advances the
/// fence. Events from an older execution and non-monotonic events from the
/// current execution are rejected. Disposal clears every retained payload.
final class BoundedProgressReporter<P>
    implements ProgressReporter<P>, Disposable {
  /// Creates a ring retaining at most [capacity] events.
  BoundedProgressReporter({this.capacity = 64}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
    }
  }

  /// Maximum retained event count.
  final int capacity;

  final ListQueue<OperationProgress<P>> _events =
      ListQueue<OperationProgress<P>>();
  int? _executionId;
  var _lastSequence = 0;
  var _disposed = false;
  var _droppedEventCount = 0;

  /// Latest accepted execution fence.
  int? get executionId => _executionId;

  /// Immutable retained events in publication order.
  List<OperationProgress<P>> get events =>
      List<OperationProgress<P>>.unmodifiable(_events);

  /// Number of events rejected or overwritten by the bound.
  int get droppedEventCount => _droppedEventCount;

  /// Whether this buffer has been terminally cleared.
  bool get isDisposed => _disposed;

  @override
  bool report(OperationProgress<P> progress) {
    if (_disposed) return false;
    final current = _executionId;
    if (current != null && progress.executionId < current) {
      _droppedEventCount += 1;
      return false;
    }
    if (current == null || progress.executionId > current) {
      _executionId = progress.executionId;
      _lastSequence = 0;
    }
    if (progress.sequence <= _lastSequence) {
      _droppedEventCount += 1;
      return false;
    }
    _lastSequence = progress.sequence;
    if (_events.length == capacity) {
      _events.removeFirst();
      _droppedEventCount += 1;
    }
    _events.add(progress);
    return true;
  }

  /// Clears retained payloads and rejects every future event.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events.clear();
    _executionId = null;
    _lastSequence = 0;
  }
}

/// Payload-free execution fence around a borrowed progress destination.
///
/// Only the latest begun execution may publish. Finishing it rejects late
/// events, while beginning a newer execution immediately fences older work.
final class LatestExecutionProgressReporter<P>
    implements ProgressReporter<P>, Disposable {
  /// Creates a failure-isolating fence around [reporter].
  LatestExecutionProgressReporter({required ProgressReporter<P> reporter})
    : _reporter = SafeProgressReporter<P>(reporter: reporter);

  final SafeProgressReporter<P> _reporter;
  int? _activeExecutionId;
  var _latestExecutionId = 0;
  var _lastSequence = 0;
  var _droppedEventCount = 0;
  var _disposed = false;

  /// Execution currently allowed to publish, or `null` after its terminal.
  int? get activeExecutionId => _activeExecutionId;

  /// Number of stale, out-of-order, inactive, or post-disposal events rejected.
  int get droppedEventCount => _droppedEventCount;

  /// Begins a strictly newer accepted execution.
  void begin(int executionId) {
    if (_disposed) throw StateError('Progress reporter is disposed.');
    if (executionId <= _latestExecutionId) {
      throw ArgumentError.value(
        executionId,
        'executionId',
        'Must be greater than the latest execution ID.',
      );
    }
    _latestExecutionId = executionId;
    _activeExecutionId = executionId;
    _lastSequence = 0;
  }

  /// Closes [executionId] if it is still the latest active execution.
  bool finish(int executionId) {
    if (_activeExecutionId != executionId) return false;
    _activeExecutionId = null;
    return true;
  }

  @override
  bool report(OperationProgress<P> progress) {
    if (_disposed || progress.executionId != _activeExecutionId) {
      _droppedEventCount += 1;
      return false;
    }
    if (progress.sequence <= _lastSequence) {
      _droppedEventCount += 1;
      return false;
    }
    _lastSequence = progress.sequence;
    return _reporter.report(progress);
  }

  /// Rejects future publications without owning the borrowed destination.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _activeExecutionId = null;
    _lastSequence = 0;
  }
}

/// Cancellation, deadline, and typed progress for one accepted execution.
final class CommandExecutionContext<P> {
  /// Creates a context for a positive [executionId].
  CommandExecutionContext({
    required this.executionId,
    required this.cancellation,
    ProgressReporter<P> progress = const NoOpProgressReporter<Never>(),
    this.deadline,
    DateTime Function()? now,
  }) : _progress = progress,
       _now = now ?? _systemNow {
    if (executionId <= 0) {
      throw ArgumentError.value(
        executionId,
        'executionId',
        'Must be positive.',
      );
    }
    if (deadline != null && !deadline!.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
  }

  /// Positive accepted execution identity.
  final int executionId;

  /// Borrowed cooperative cancellation signal.
  final CancellationSignal cancellation;

  /// Optional absolute UTC deadline.
  final DateTime? deadline;

  final ProgressReporter<P> _progress;
  final DateTime Function() _now;
  var _sequence = 0;

  /// Latest sequence attempted by this execution.
  int get progressSequence => _sequence;

  /// Whether the deadline has elapsed at the injected clock.
  bool get isDeadlineExceeded {
    final limit = deadline;
    return limit != null && !_now().toUtc().isBefore(limit);
  }

  /// Throws cancellation or [OperationDeadlineExceededException].
  void throwIfUnavailable() {
    cancellation.throwIfCancelled();
    if (isDeadlineExceeded) {
      throw OperationDeadlineExceededException(deadline!);
    }
  }

  /// Publishes one typed event with the next execution-local sequence.
  bool publish(P payload) {
    throwIfUnavailable();
    final event = OperationProgress<P>(
      executionId: executionId,
      sequence: ++_sequence,
      payload: payload,
    );
    return _progress.report(event);
  }

  static DateTime _systemNow() => DateTime.now().toUtc();
}

/// Deadline control flow for an operation that exceeded its explicit bound.
final class OperationDeadlineExceededException implements Exception {
  /// Creates a failure retaining only the configured UTC boundary.
  const OperationDeadlineExceededException(this.deadline);

  /// Expired UTC deadline.
  final DateTime deadline;

  @override
  String toString() => 'OperationDeadlineExceededException($deadline)';
}
