import 'package:dartitect/dartitect.dart';
import 'package:dartitect_isolates/dartitect_isolates.dart';

/// Real-isolate contract result with zero-residual facts.
final class IsolateWorkerHarnessResult<R, F extends Object> {
  /// Creates a worker harness outcome.
  const IsolateWorkerHarnessResult({
    required this.acknowledged,
    required this.activeRequestsAfterStop,
    required this.disposed,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// Expected result when no crash/deadline occurred.
  final Result<R, F>? result;

  /// Unexpected remote/protocol error.
  final Object? error;

  /// Original supervisor stack.
  final StackTrace? stackTrace;

  /// Whether the correlated ACK completed.
  final bool acknowledged;

  /// Residual pending request count after safe-stop.
  final int activeRequestsAfterStop;

  /// Whether ports/timers/isolate supervisor were released.
  final bool disposed;
}

/// Runs one request through a real [IsolateWorker] and always safe-stops it.
final class IsolateWorkerContractHarness<P, R, F extends Object> {
  /// Creates a harness for an isolate-local [handler].
  const IsolateWorkerContractHarness(this.handler);

  /// Receiving handler.
  final IsolateRequestHandler<P, R, F> handler;

  /// Spawns, correlates ACK/result, and tears down.
  Future<IsolateWorkerHarnessResult<R, F>> run(
    P payload, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final worker = await IsolateWorker.spawn<P, R, F>(
      handler: handler,
      heartbeatInterval: const Duration(milliseconds: 20),
      heartbeatTimeout: const Duration(milliseconds: 200),
    );
    var acknowledged = false;
    Result<R, F>? result;
    Object? error;
    StackTrace? stackTrace;
    try {
      final receipt = worker.send(payload, timeout: timeout);
      await receipt.accepted;
      acknowledged = true;
      result = await receipt.result;
    } catch (caught, caughtStack) {
      error = caught;
      stackTrace = caughtStack;
    } finally {
      await worker.safeStop();
    }
    return IsolateWorkerHarnessResult<R, F>(
      result: result,
      error: error,
      stackTrace: stackTrace,
      acknowledged: acknowledged,
      activeRequestsAfterStop: worker.activeRequestCount,
      disposed: worker.isDisposed,
    );
  }
}
