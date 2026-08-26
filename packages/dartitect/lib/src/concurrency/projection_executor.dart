import 'dart:async';
import 'dart:isolate';

import '../lifecycle/contracts.dart';
import 'cancellation.dart';

/// Explicit location selected for one projection operation.
enum ProjectionExecution {
  /// Runs synchronously in the caller's isolate and remains the default.
  inline,

  /// Runs through an explicitly injected [ProjectionExecutor].
  background,
}

/// Generation-tagged payload sent to one projection executor.
final class TransferableProjectionRequest<P> {
  /// Creates a request whose [payload] must be isolate-transferable when the
  /// selected execution is [ProjectionExecution.background].
  const TransferableProjectionRequest({
    required this.generation,
    required this.payload,
  }) : assert(generation >= 0, 'generation must not be negative');

  /// Main-graph generation that owns this work.
  final int generation;

  /// Immutable or otherwise isolate-transferable projection input.
  final P payload;
}

/// Generation-tagged value returned by one projection executor.
final class TransferableProjectionResult<R> {
  /// Creates a transferable result for [generation].
  const TransferableProjectionResult({
    required this.generation,
    required this.value,
  }) : assert(generation >= 0, 'generation must not be negative');

  /// Generation copied exactly from the corresponding request.
  final int generation;

  /// Projection result, which must be isolate-transferable for background work.
  final R value;
}

/// One request or callback could not be sent to a worker isolate.
final class ProjectionTransferException implements Exception {
  /// Creates a payload-free transfer failure.
  const ProjectionTransferException();

  @override
  String toString() =>
      'ProjectionTransferException: request and callback must be transferable.';
}

/// A worker isolate terminated without returning a result or structured error.
final class ProjectionIsolateExitException implements Exception {
  /// Creates an unexpected worker-exit failure.
  const ProjectionIsolateExitException();

  @override
  String toString() =>
      'ProjectionIsolateExitException: worker exited without a result.';
}

/// Structured error returned by a background projection callback.
final class ProjectionRemoteException implements Exception {
  /// Creates a remote failure with its original string and stack transcript.
  const ProjectionRemoteException(this.message, this.remoteStackTrace);

  /// Remote error representation.
  final String message;

  /// Remote stack trace representation.
  final String remoteStackTrace;

  @override
  String toString() => 'ProjectionRemoteException: $message';
}

/// Explicit owner of projection tasks and their worker-isolate lifecycle.
abstract interface class ProjectionExecutor<P, R> implements AsyncDisposable {
  /// Executes one generation-tagged transferable request.
  Future<TransferableProjectionResult<R>> execute(
    TransferableProjectionRequest<P> request,
    CancellationSignal signal,
  );

  /// Tasks whose worker isolates have not exited yet.
  int get activeTaskCount;

  /// Whether terminal disposal has begun.
  bool get isDisposed;
}

/// Callback executed inside one worker isolate per projection request.
typedef IsolateProjectionCallback<P, R> = FutureOr<R> Function(P payload);

/// Per-task isolate executor with cancellation-safe stale result suppression.
///
/// Cancellation completes the caller-facing future immediately but deliberately
/// does not kill the isolate. The worker can therefore run its own `finally`
/// cleanup. [disposeAsync] prevents admission and drains every worker exit.
final class IsolateProjectionExecutor<P, R>
    implements ProjectionExecutor<P, R> {
  /// Creates an executor around a transferable top-level/static [project].
  IsolateProjectionExecutor({
    required IsolateProjectionCallback<P, R> project,
    this.debugName = 'Dartitect projection',
  }) : _project = project {
    if (debugName.trim().isEmpty) {
      throw ArgumentError.value(debugName, 'debugName', 'Must not be empty.');
    }
  }

  final IsolateProjectionCallback<P, R> _project;
  final Map<int, _ProjectionTask> _tasks = <int, _ProjectionTask>{};
  var _nextTaskId = 0;
  var _disposed = false;
  Future<void>? _disposeFuture;

  /// Static debug name applied to worker isolates.
  final String debugName;

  @override
  int get activeTaskCount => _tasks.length;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<TransferableProjectionResult<R>> execute(
    TransferableProjectionRequest<P> request,
    CancellationSignal signal,
  ) {
    if (_disposed) throw StateError('ProjectionExecutor is disposed.');
    signal.throwIfCancelled();

    final id = _nextTaskId++;
    final result = Completer<TransferableProjectionResult<R>>();
    final settled = Completer<void>();
    final resultPort = RawReceivePort();
    final errorPort = RawReceivePort();
    final exitPort = RawReceivePort();
    var terminalMessageReceived = false;
    var cleaned = false;
    CancellationRegistration? cancellation;

    void completeError(Object error, StackTrace stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }

    void cleanup() {
      if (cleaned) return;
      cleaned = true;
      cancellation?.dispose();
      resultPort.close();
      errorPort.close();
      exitPort.close();
      _tasks.remove(id);
      if (!settled.isCompleted) settled.complete();
    }

    resultPort.handler = (Object? message) {
      if (cleaned) return;
      terminalMessageReceived = true;
      if (message is _ProjectionSuccess) {
        if (!result.isCompleted) {
          result.complete(
            TransferableProjectionResult<R>(
              generation: message.generation,
              value: message.value as R,
            ),
          );
        }
      } else if (message is _ProjectionFailure) {
        completeError(
          ProjectionRemoteException(message.error, message.stackTrace),
          StackTrace.fromString(message.stackTrace),
        );
      } else {
        completeError(
          const ProjectionIsolateExitException(),
          StackTrace.current,
        );
      }
      cleanup();
    };
    errorPort.handler = (Object? message) {
      if (cleaned) return;
      terminalMessageReceived = true;
      final parts = message is List<Object?> ? message : const <Object?>[];
      final error = parts.isEmpty ? 'Worker isolate failed.' : '${parts.first}';
      final stack = parts.length < 2 ? '' : '${parts[1]}';
      completeError(
        ProjectionRemoteException(error, stack),
        StackTrace.fromString(stack),
      );
      cleanup();
    };
    exitPort.handler = (Object? _) {
      Future<void>.delayed(Duration.zero, () {
        if (cleaned || terminalMessageReceived) return;
        completeError(
          const ProjectionIsolateExitException(),
          StackTrace.current,
        );
        cleanup();
      });
    };

    cancellation = signal.register((reason) {
      completeError(CancellationException(reason), StackTrace.current);
    });
    final task = _ProjectionTask(
      settled: settled.future,
      cancel: () => completeError(
        const CancellationException('ProjectionExecutor disposed'),
        StackTrace.current,
      ),
    );
    _tasks[id] = task;

    unawaited(
      Future<void>(() async {
        try {
          await Isolate.spawn<_ProjectionIsolateMessage<P, R>>(
            _runProjection<P, R>,
            _ProjectionIsolateMessage<P, R>(
              resultPort.sendPort,
              request,
              _project,
            ),
            debugName: debugName,
            errorsAreFatal: true,
            onError: errorPort.sendPort,
            onExit: exitPort.sendPort,
          );
        } catch (error, stackTrace) {
          terminalMessageReceived = true;
          completeError(const ProjectionTransferException(), stackTrace);
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
    final tasks = List<_ProjectionTask>.of(_tasks.values);
    for (final task in tasks) {
      task.cancel();
    }
    await Future.wait(tasks.map((task) => task.settled));
  }
}

final class _ProjectionTask {
  const _ProjectionTask({required this.settled, required this.cancel});

  final Future<void> settled;
  final void Function() cancel;
}

final class _ProjectionIsolateMessage<P, R> {
  const _ProjectionIsolateMessage(this.resultPort, this.request, this.project);

  final SendPort resultPort;
  final TransferableProjectionRequest<P> request;
  final IsolateProjectionCallback<P, R> project;
}

final class _ProjectionSuccess {
  const _ProjectionSuccess(this.generation, this.value);

  final int generation;
  final Object? value;
}

final class _ProjectionFailure {
  const _ProjectionFailure(this.generation, this.error, this.stackTrace);

  final int generation;
  final String error;
  final String stackTrace;
}

Future<void> _runProjection<P, R>(
  _ProjectionIsolateMessage<P, R> message,
) async {
  try {
    final value = await message.project(message.request.payload);
    Isolate.exit(
      message.resultPort,
      _ProjectionSuccess(message.request.generation, value),
    );
  } catch (error, stackTrace) {
    Isolate.exit(
      message.resultPort,
      _ProjectionFailure(
        message.request.generation,
        _safeErrorString(error),
        stackTrace.toString(),
      ),
    );
  }
}

String _safeErrorString(Object error) {
  try {
    return error.toString();
  } on Object {
    return 'Background projection failed.';
  }
}
