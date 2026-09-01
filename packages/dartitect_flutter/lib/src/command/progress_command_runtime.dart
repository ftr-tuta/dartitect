import 'package:dartitect/dartitect.dart';

/// Internal bridge that keeps progress fencing inside shared command lanes.
///
/// The surrounding `Command0`, `Command1`, or `KeyedCommand1` remains the sole
/// admission authority. This runtime only creates execution-scoped progress
/// context after that lane has admitted and started work.
final class ProgressCommandRuntime<P> {
  /// Creates a latest-execution progress fence around [progress].
  ProgressCommandRuntime(ProgressReporter<P> progress)
    : _progress = LatestExecutionProgressReporter<P>(reporter: progress);

  final LatestExecutionProgressReporter<P> _progress;
  var _executionId = 0;

  /// Number of stale or post-terminal progress events rejected by the fence.
  int get droppedProgressCount => _progress.droppedEventCount;

  /// Runs one already-admitted action with a fresh progress context.
  Future<Result<T, F>> run<T, F extends Object>({
    required CancellationSignal cancellation,
    required Future<Result<T, F>> Function(CommandExecutionContext<P> context)
    action,
    DateTime? deadline,
    DateTime Function()? now,
  }) async {
    final current = ++_executionId;
    _progress.begin(current);
    try {
      return await action(
        CommandExecutionContext<P>(
          executionId: current,
          cancellation: cancellation,
          progress: _progress,
          deadline: deadline,
          now: now,
        ),
      );
    } finally {
      _progress.finish(current);
    }
  }

  /// Clears progress state and rejects future publications.
  void dispose() => _progress.dispose();
}
