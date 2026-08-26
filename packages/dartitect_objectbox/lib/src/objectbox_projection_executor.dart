import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:objectbox/objectbox.dart';

/// Callback run with ObjectBox's isolate-local attached Store wrapper.
///
/// The callback may create an isolate-local graph, query, or other resources,
/// but must close everything it creates in `finally`. ObjectBox closes the
/// attached [Store] wrapper after the callback settles.
typedef ObjectBoxProjectionCallback<P, R> = FutureOr<R> Function(
  Store store,
  P payload,
);

/// Background projection executor backed by [Store.runAsync].
///
/// The original Store is borrowed. Cancellation suppresses publication but
/// does not kill ObjectBox's worker isolate, allowing its Store and callback
/// cleanup to complete. Dispose this executor before closing the borrowed Store.
final class ObjectBoxProjectionExecutor<P, R>
    implements ProjectionExecutor<P, R> {
  /// Creates an executor from a borrowed [store] and transferable [project].
  ObjectBoxProjectionExecutor({
    required Store store,
    required ObjectBoxProjectionCallback<P, R> project,
  }) : _store = store,
       _project = project;

  final Store _store;
  final ObjectBoxProjectionCallback<P, R> _project;
  final Map<int, _ObjectBoxProjectionTask> _tasks =
      <int, _ObjectBoxProjectionTask>{};
  var _nextTaskId = 0;
  var _disposed = false;
  Future<void>? _disposeFuture;

  @override
  int get activeTaskCount => _tasks.length;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<TransferableProjectionResult<R>> execute(
    TransferableProjectionRequest<P> request,
    CancellationSignal signal,
  ) {
    if (_disposed) {
      throw StateError('ObjectBoxProjectionExecutor is disposed.');
    }
    if (_store.isClosed()) throw StateError('ObjectBox Store is closed.');
    signal.throwIfCancelled();

    final id = _nextTaskId++;
    final result = Completer<TransferableProjectionResult<R>>();
    final settled = Completer<void>();
    var cleaned = false;
    late final CancellationRegistration cancellation;

    void completeError(Object error, StackTrace stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }

    void cleanup() {
      if (cleaned) return;
      cleaned = true;
      cancellation.dispose();
      _tasks.remove(id);
      settled.complete();
    }

    cancellation = signal.register((reason) {
      completeError(CancellationException(reason), StackTrace.current);
    });
    _tasks[id] = _ObjectBoxProjectionTask(
      settled: settled.future,
      cancel: () => completeError(
        const CancellationException('ObjectBoxProjectionExecutor disposed'),
        StackTrace.current,
      ),
    );

    unawaited(
      Future<void>(() async {
        try {
          final value = await _store.runAsync<P, R>(_project, request.payload);
          if (!result.isCompleted) {
            result.complete(
              TransferableProjectionResult<R>(
                generation: request.generation,
                value: value,
              ),
            );
          }
        } catch (error, stackTrace) {
          completeError(error, stackTrace);
        } finally {
          cleanup();
        }
      }),
    );

    return result.future;
  }

  @override
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    final tasks = List<_ObjectBoxProjectionTask>.of(_tasks.values);
    for (final task in tasks) {
      task.cancel();
    }
    await Future.wait(tasks.map((task) => task.settled));
  }
}

final class _ObjectBoxProjectionTask {
  const _ObjectBoxProjectionTask({required this.settled, required this.cancel});

  final Future<void> settled;
  final void Function() cancel;
}
