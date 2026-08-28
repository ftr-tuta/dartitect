import 'dart:async';

import 'package:dartitect/dartitect.dart';

/// Rejection when both the active and queued bulkhead bounds are full.
final class BulkheadRejectedException implements Exception {
  /// Creates a bounded-capacity rejection.
  const BulkheadRejectedException();
}

/// Bounded concurrent execution with a bounded FIFO wait queue.
final class Bulkhead implements AsyncDisposable {
  /// Creates a bulkhead with positive concurrency and a non-negative queue.
  Bulkhead({this.maxConcurrent = 4, this.maxQueue = 64}) {
    if (maxConcurrent <= 0 || maxQueue < 0) {
      throw ArgumentError('Bulkhead bounds are invalid.');
    }
  }

  /// Maximum running operations.
  final int maxConcurrent;

  /// Maximum queued operations.
  final int maxQueue;

  final List<_BulkheadEntry<Object?>> _queue = <_BulkheadEntry<Object?>>[];
  final Set<Future<void>> _running = <Future<void>>{};
  final Set<_BulkheadEntry<Object?>> _activeEntries =
      <_BulkheadEntry<Object?>>{};
  var _disposed = false;
  Future<void>? _disposal;

  /// Number of operations currently running.
  int get runningCount => _running.length;

  /// Number of operations waiting in FIFO order.
  int get queuedCount => _queue.length;

  /// Admits, queues, or rejects [operation].
  Future<T> run<T>(
    Future<T> Function(CancellationSignal cancellation) operation, {
    CancellationSignal? cancellation,
  }) {
    if (_disposed) throw StateError('Bulkhead is disposed.');
    cancellation?.throwIfCancelled();
    final entry = _BulkheadEntry<T>(operation, cancellation);
    if (_running.length < maxConcurrent) {
      _start(entry as _BulkheadEntry<Object?>);
    } else {
      if (_queue.length >= maxQueue) {
        throw const BulkheadRejectedException();
      }
      entry.registration = cancellation?.register((reason) {
        if (_queue.remove(entry) && !entry.completer.isCompleted) {
          entry.completer.completeError(CancellationException(reason));
        }
        entry.disposeRegistration();
      });
      _queue.add(entry as _BulkheadEntry<Object?>);
    }
    return entry.completer.future;
  }

  void _start(_BulkheadEntry<Object?> entry) {
    entry.disposeRegistration();
    entry.registration = entry.cancellation?.register(entry.source.cancel);
    _activeEntries.add(entry);
    final work = _run(entry);
    _running.add(work);
    unawaited(
      work.whenComplete(() {
        _running.remove(work);
        _activeEntries.remove(entry);
        _startNext();
      }),
    );
  }

  Future<void> _run(_BulkheadEntry<Object?> entry) async {
    try {
      entry.source.signal.throwIfCancelled();
      final value = await entry.operation(entry.source.signal);
      if (!entry.completer.isCompleted) entry.completer.complete(value);
    } catch (error, stackTrace) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(error, stackTrace);
      }
    } finally {
      entry.disposeRegistration();
      entry.source.dispose();
    }
  }

  void _startNext() {
    if (_disposed || _running.length >= maxConcurrent || _queue.isEmpty) return;
    _start(_queue.removeAt(0));
  }

  /// Rejects queued work, cancels running work, and drains it.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _queue) {
      entry.disposeRegistration();
      entry.source.dispose();
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(StateError('Bulkhead is disposed.'));
      }
    }
    _queue.clear();
    for (final entry in _activeEntries) {
      entry.source.cancel('Bulkhead disposed');
    }
    await Future.wait<void>(_running.toList(growable: false));
    _activeEntries.clear();
  }
}

final class _BulkheadEntry<T> {
  _BulkheadEntry(this.operation, this.cancellation);

  final Future<T> Function(CancellationSignal cancellation) operation;
  final CancellationSignal? cancellation;
  final CancellationSource source = CancellationSource();
  final Completer<T> completer = Completer<T>();
  CancellationRegistration? registration;

  void disposeRegistration() {
    registration?.dispose();
    registration = null;
  }
}
