import 'package:dartitect/dartitect.dart';

/// Deterministic outcome of one [OwnedGraphHarness] fault scenario.
final class OwnedGraphHarnessResult {
  /// Creates a graph harness outcome.
  const OwnedGraphHarnessResult({
    required this.timeline,
    required this.liveResourceCount,
    this.error,
    this.stackTrace,
  });

  /// Acquisition and LIFO release timeline.
  final List<String> timeline;

  /// Resource count remaining after rollback or disposal.
  final int liveResourceCount;

  /// Original injected or lifecycle error.
  final Object? error;

  /// Stack captured with [error].
  final StackTrace? stackTrace;
}

/// Exercises graph acquisition, rollback, commit, and zero-residual teardown.
final class OwnedGraphHarness {
  /// Creates a harness with a positive [resourceCount].
  OwnedGraphHarness({this.resourceCount = 3}) {
    if (resourceCount <= 0) {
      throw ArgumentError.value(resourceCount, 'resourceCount');
    }
  }

  /// Number of synthetic owned resources acquired by each scenario.
  final int resourceCount;

  /// Runs a scenario, optionally throwing after acquisition [failAfter].
  Future<OwnedGraphHarnessResult> run({int? failAfter}) async {
    if (failAfter != null && (failAfter < 1 || failAfter > resourceCount)) {
      throw ArgumentError.value(failAfter, 'failAfter');
    }
    final timeline = <String>[];
    var live = 0;
    try {
      final graph = await ResourceTransaction.create<String>((transaction) {
        for (var index = 1; index <= resourceCount; index += 1) {
          live += 1;
          timeline.add('acquire:$index');
          transaction.own<int>(index, (value) {
            timeline.add('release:$value');
            live -= 1;
          }, label: 'resource-$index');
          if (failAfter == index) throw StateError('fault:$index');
        }
        return 'root';
      });
      await graph.disposeAsync();
      return OwnedGraphHarnessResult(
        timeline: List<String>.unmodifiable(timeline),
        liveResourceCount: live,
      );
    } catch (error, stackTrace) {
      return OwnedGraphHarnessResult(
        timeline: List<String>.unmodifiable(timeline),
        liveResourceCount: live,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
