import 'dart:async';

/// Failure raised while cancellation or terminal cleanup is being attempted.
final class AsyncLifecycleCleanupFailure {
  /// Creates a cleanup failure with its original stack trace.
  const AsyncLifecycleCleanupFailure(this.error, this.stackTrace);

  /// Original cleanup error.
  final Object error;

  /// Original cleanup stack trace.
  final StackTrace stackTrace;
}

/// Aggregates every failure without skipping later cleanup work.
final class AsyncLifecycleCleanupException implements Exception {
  /// Creates an aggregate from non-empty [failures].
  const AsyncLifecycleCleanupException(this.failures);

  /// Failures in attempted cleanup order.
  final List<AsyncLifecycleCleanupFailure> failures;

  @override
  String toString() =>
      'AsyncLifecycleCleanupException(${failures.length} failures)';
}

/// Admission and drain barrier for asynchronous owned work.
final class AsyncLifecycleBarrier {
  final Set<_BarrierOperation> _operations = <_BarrierOperation>{};
  var _closing = false;
  var _closed = false;
  Future<void>? _closeFuture;

  /// Whether new work and publications are still accepted.
  bool get isOpen => !_closing && !_closed;

  /// Whether terminal cleanup has completed.
  bool get isClosed => _closed;

  /// Number of admitted operations not yet settled.
  int get activeOperationCount => _operations.length;

  /// Runs admitted [body] and tracks it until success or failure settles.
  ///
  /// [cancel] is invoked at most once if [close] starts while the operation is
  /// active. Cancellation is cooperative; close still waits for [body].
  Future<T> run<T>(
    Future<T> Function() body, {
    FutureOr<void> Function()? cancel,
  }) {
    if (!isOpen) {
      return Future<T>.error(
        StateError('AsyncLifecycleBarrier is closing or closed.'),
      );
    }
    final operation = _BarrierOperation(cancel);
    _operations.add(operation);
    late final Future<T> future;
    try {
      future = Future<T>.sync(body);
    } catch (error, stackTrace) {
      _operations.remove(operation);
      Error.throwWithStackTrace(error, stackTrace);
    }
    operation.settled = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    unawaited(
      operation.settled.whenComplete(() => _operations.remove(operation)),
    );
    return future;
  }

  /// Closes admission synchronously, requests cancellation, and drains work.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closing = true;
    final failures = <AsyncLifecycleCleanupFailure>[];
    final snapshot = _operations.toList(growable: false);
    for (final operation in snapshot) {
      try {
        await operation.requestCancel();
      } catch (error, stackTrace) {
        failures.add(AsyncLifecycleCleanupFailure(error, stackTrace));
      }
    }
    await Future.wait<void>(
      snapshot.map((operation) => operation.settled),
      eagerError: false,
    );
    _closed = true;
    if (failures.isNotEmpty) {
      throw AsyncLifecycleCleanupException(
        List<AsyncLifecycleCleanupFailure>.unmodifiable(failures),
      );
    }
  }
}

final class _BarrierOperation {
  _BarrierOperation(this._cancel);

  final FutureOr<void> Function()? _cancel;
  late Future<void> settled;
  var _cancelled = false;

  Future<void> requestCancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _cancel?.call();
  }
}
