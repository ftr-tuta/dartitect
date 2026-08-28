import 'dart:async';
import 'dart:collection';

import '../concurrency/cancellation.dart';
import '../concurrency/operation_progress.dart';
import 'contracts.dart';
import 'owned_graph.dart';

/// Closed bootstrap progress phases.
enum BootstrapProgressPhase {
  /// A named stage is about to execute.
  stageStarted,

  /// A named stage completed.
  stageCompleted,

  /// A failed attempt is releasing partially acquired resources.
  rollingBack,
}

/// Payload-free progress for one named bootstrap stage.
final class BootstrapProgress {
  /// Creates one stage progress value.
  const BootstrapProgress({
    required this.phase,
    required this.stage,
    required this.stageIndex,
    required this.stageCount,
  });

  /// Current closed phase.
  final BootstrapProgressPhase phase;

  /// Consumer-declared static stage name.
  final String stage;

  /// One-based stage position.
  final int stageIndex;

  /// Total configured stage count.
  final int stageCount;
}

/// One named acquisition or initialization stage.
final class BootstrapStage {
  /// Creates a stage with a static non-empty [name].
  BootstrapStage({required this.name, required this.run}) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
  }

  /// Static progress and failure-boundary name.
  final String name;

  /// Stage body that registers owned resources through [ResourceTransaction].
  final FutureOr<void> Function(
    ResourceTransaction transaction,
    CommandExecutionContext<BootstrapProgress> context,
  )
  run;
}

/// Terminal bootstrap failure category.
enum BootstrapFailureKind {
  /// Cooperative caller or owner cancellation.
  cancelled,

  /// Absolute deadline elapsed.
  deadlineExceeded,

  /// A stage or root factory failed.
  construction,

  /// Construction failed and rollback also failed.
  rollback,
}

/// Immutable facts recorded for a bootstrap attempt.
final class BootstrapReport {
  /// Creates a terminal attempt report.
  BootstrapReport({
    required this.executionId,
    required Iterable<String> completedStages,
    this.failedStage,
  }) : completedStages = UnmodifiableListView<String>(
         List<String>.of(completedStages),
       );

  /// Positive execution identity shared with progress.
  final int executionId;

  /// Static names completed in order.
  final List<String> completedStages;

  /// Static stage name at failure, or `null` after success.
  final String? failedStage;
}

/// Success or typed bootstrap failure.
sealed class BootstrapAttempt<R> {
  const BootstrapAttempt(this.report);

  /// Terminal report for the attempt.
  final BootstrapReport report;
}

/// Successful, atomically committed application graph.
final class BootstrapSucceeded<R> extends BootstrapAttempt<R> {
  /// Creates a success that transfers [graph] ownership to the caller.
  const BootstrapSucceeded({
    required BootstrapReport report,
    required this.graph,
  }) : super(report);

  /// Complete committed graph.
  final OwnedGraph<R> graph;
}

/// Failed bootstrap with original construction and optional rollback errors.
final class BootstrapFailed<R> extends BootstrapAttempt<R> {
  /// Creates a typed terminal failure.
  const BootstrapFailed({
    required BootstrapReport report,
    required this.kind,
    required this.error,
    required this.stackTrace,
    this.rollbackError,
    this.rollbackStackTrace,
  }) : super(report);

  /// Stable failure category.
  final BootstrapFailureKind kind;

  /// Original failure for application presentation/reporting boundaries.
  final Object error;

  /// Original failure stack.
  final StackTrace stackTrace;

  /// Independent rollback failure, when present.
  final Object? rollbackError;

  /// Original rollback failure stack, when present.
  final StackTrace? rollbackStackTrace;
}

/// Serial, cancellable bootstrap coordinator over [ResourceTransaction].
final class BootstrapCoordinator<R> implements AsyncDisposable {
  /// Creates a coordinator from unique named stages and a root factory.
  BootstrapCoordinator({
    required Iterable<BootstrapStage> stages,
    required FutureOr<R> Function(
      ResourceTransaction transaction,
      CommandExecutionContext<BootstrapProgress> context,
    )
    buildRoot,
    ProgressReporter<BootstrapProgress> progress =
        const NoOpProgressReporter<Never>(),
  }) : stages = UnmodifiableListView<BootstrapStage>(
         List<BootstrapStage>.of(stages),
       ),
       _buildRoot = buildRoot,
       _progress = SafeProgressReporter<BootstrapProgress>(reporter: progress) {
    final names = <String>{};
    for (final stage in this.stages) {
      if (!names.add(stage.name)) {
        throw ArgumentError.value(
          stage.name,
          'stages',
          'Stage names must be unique.',
        );
      }
    }
  }

  /// Ordered named stages.
  final List<BootstrapStage> stages;

  final FutureOr<R> Function(
    ResourceTransaction transaction,
    CommandExecutionContext<BootstrapProgress> context,
  )
  _buildRoot;
  final ProgressReporter<BootstrapProgress> _progress;
  _BootstrapRun? _active;
  var _executionId = 0;
  var _disposed = false;
  Future<void>? _disposal;

  /// Whether one attempt is currently active.
  bool get isRunning => _active != null;

  /// Runs every stage and commits the complete graph atomically.
  Future<BootstrapAttempt<R>> run({
    CancellationSignal? cancellation,
    DateTime? deadline,
  }) {
    if (_disposed) throw StateError('BootstrapCoordinator is disposed.');
    if (_active != null) throw StateError('Bootstrap is already running.');
    if (deadline != null && !deadline.isUtc) {
      throw ArgumentError.value(deadline, 'deadline', 'Must use UTC.');
    }
    cancellation?.throwIfCancelled();
    final active = _BootstrapRun();
    active.externalRegistration = cancellation?.register(active.source.cancel);
    _active = active;
    final result = _execute(++_executionId, deadline, active);
    active.done = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<BootstrapAttempt<R>> _execute(
    int executionId,
    DateTime? deadline,
    _BootstrapRun active,
  ) async {
    Timer? deadlineTimer;
    var deadlineElapsed = false;
    final transaction = ResourceTransaction(label: 'BootstrapCoordinator');
    final completed = <String>[];
    String? currentStage;
    CommandExecutionContext<BootstrapProgress>? context;
    try {
      if (deadline != null) {
        final remaining = deadline.difference(DateTime.now().toUtc());
        if (remaining <= Duration.zero) deadlineElapsed = true;
        if (!deadlineElapsed) {
          deadlineTimer = Timer(remaining, () {
            deadlineElapsed = true;
            active.source.cancel('Bootstrap deadline exceeded');
          });
        }
      }
      context = CommandExecutionContext<BootstrapProgress>(
        executionId: executionId,
        cancellation: active.source.signal,
        deadline: deadline,
        progress: _progress,
      );
      for (var index = 0; index < stages.length; index += 1) {
        currentStage = stages[index].name;
        context.throwIfUnavailable();
        context.publish(
          BootstrapProgress(
            phase: BootstrapProgressPhase.stageStarted,
            stage: currentStage,
            stageIndex: index + 1,
            stageCount: stages.length,
          ),
        );
        await stages[index].run(transaction, context);
        context.throwIfUnavailable();
        completed.add(currentStage);
        context.publish(
          BootstrapProgress(
            phase: BootstrapProgressPhase.stageCompleted,
            stage: currentStage,
            stageIndex: index + 1,
            stageCount: stages.length,
          ),
        );
      }
      currentStage = 'root';
      context.throwIfUnavailable();
      final root = await _buildRoot(transaction, context);
      context.throwIfUnavailable();
      return BootstrapSucceeded<R>(
        report: BootstrapReport(
          executionId: executionId,
          completedStages: completed,
        ),
        graph: transaction.commit(root),
      );
    } catch (error, stackTrace) {
      Object? rollbackError;
      StackTrace? rollbackStackTrace;
      try {
        _progress.report(
          OperationProgress<BootstrapProgress>(
            executionId: executionId,
            sequence: (context?.progressSequence ?? 0) + 1,
            payload: BootstrapProgress(
              phase: BootstrapProgressPhase.rollingBack,
              stage: currentStage ?? 'bootstrap',
              stageIndex: completed.length + 1,
              stageCount: stages.length,
            ),
          ),
        );
        await transaction.rollback();
      } catch (caught, caughtStack) {
        rollbackError = caught;
        rollbackStackTrace = caughtStack;
      }
      final kind = rollbackError != null
          ? BootstrapFailureKind.rollback
          : deadlineElapsed
          ? BootstrapFailureKind.deadlineExceeded
          : error is CancellationException
          ? BootstrapFailureKind.cancelled
          : BootstrapFailureKind.construction;
      return BootstrapFailed<R>(
        report: BootstrapReport(
          executionId: executionId,
          completedStages: completed,
          failedStage: currentStage,
        ),
        kind: kind,
        error: error,
        stackTrace: stackTrace,
        rollbackError: rollbackError,
        rollbackStackTrace: rollbackStackTrace,
      );
    } finally {
      deadlineTimer?.cancel();
      active.externalRegistration?.dispose();
      active.source.dispose();
      if (identical(_active, active)) _active = null;
    }
  }

  /// Cancels and drains the active attempt without owning committed graphs.
  @override
  Future<void> disposeAsync() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    final active = _active;
    active?.source.cancel('BootstrapCoordinator disposed');
    await active?.done;
  }
}

final class _BootstrapRun {
  final CancellationSource source = CancellationSource();
  CancellationRegistration? externalRegistration;
  Future<void>? done;
}
