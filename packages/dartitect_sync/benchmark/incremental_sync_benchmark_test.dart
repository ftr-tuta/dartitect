import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect_incremental.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:test/test.dart';

void main() {
  test('incremental checkpoints remain single-flight at 1000 steps', () async {
    const steps = 1000;
    final checkpoints = _BenchmarkCheckpoints<String, int>();
    final engine = SyncEngine<String, int, _Failure>(
      datasets: <SyncDataset<String, int, _Failure>>[
        SyncDataset<String, int, _Failure>.incremental(
          key: 'items',
          synchronize: (_) => IncrementalOperation.sync(() sync* {
            for (var checkpoint = 1; checkpoint <= steps; checkpoint++) {
              yield Ok<SyncDatasetOutcome<int>>(
                SyncDatasetOutcome<int>.checkpoint(checkpoint),
              );
            }
          }),
        ),
      ],
      graph: SyncDependencyGraph<String>(keys: const <String>['items']),
      checkpoints: checkpoints,
    );

    final watch = Stopwatch()..start();
    final report = await engine.start().done;
    watch.stop();

    expect(report.succeeded, isTrue);
    expect(report.datasets.single.confirmedStepCount, steps);
    expect(report.datasets.single.confirmedCheckpoint, steps);
    expect(checkpoints.writeCount, steps);
    expect(checkpoints.maximumActiveWrites, 1);
    await engine.disposeAsync();
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'benchmark': 'incremental-sync-checkpoints',
        'metrics': 'informative',
        'steps': steps,
        'maximumActiveWrites': checkpoints.maximumActiveWrites,
        'totalMicros': watch.elapsedMicroseconds,
      }),
    );
  });

  test('bounded DAG runs 32 independent nodes in stable order', () async {
    const nodeCount = 32;
    var active = 0;
    var maximumActive = 0;
    final datasets = <SyncDataset<int, int, _Failure>>[
      for (var key = 0; key < nodeCount; key++)
        SyncDataset<int, int, _Failure>(
          key: key,
          synchronize: (_) async {
            active += 1;
            if (active > maximumActive) maximumActive = active;
            await Future<void>.delayed(Duration.zero);
            active -= 1;
            return const Ok<SyncDatasetOutcome<int>>(
              SyncDatasetOutcome<int>.unchanged(),
            );
          },
        ),
    ];
    final engine = SyncEngine<int, int, _Failure>(
      datasets: datasets,
      graph: SyncDependencyGraph<int>(
        keys: <int>[for (var key = 0; key < nodeCount; key++) key],
      ),
      checkpoints: _BenchmarkCheckpoints<int, int>(),
      executionPolicy: const SyncExecutionPolicy.boundedParallel(4),
    );

    final watch = Stopwatch()..start();
    final report = await engine.start().done;
    watch.stop();

    expect(
      report.datasets.map((dataset) => dataset.key),
      orderedEquals(<int>[for (var key = 0; key < nodeCount; key++) key]),
    );
    expect(maximumActive, inInclusiveRange(2, 4));
    await engine.disposeAsync();
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'benchmark': 'incremental-sync-dag',
        'metrics': 'informative',
        'nodes': nodeCount,
        'maximumActive': maximumActive,
        'totalMicros': watch.elapsedMicroseconds,
      }),
    );
  });
}

final class _Failure implements Exception {}

final class _BenchmarkCheckpoints<K, C> implements SyncCheckpointStore<K, C> {
  final values = <K, C>{};
  var writeCount = 0;
  var _activeWrites = 0;
  var maximumActiveWrites = 0;

  @override
  Future<C?> read(K key, CancellationSignal signal) async => values[key];

  @override
  Future<void> remove(K key, CancellationSignal signal) async {
    values.remove(key);
  }

  @override
  Future<void> write(
    K key,
    C checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    _activeWrites += 1;
    if (_activeWrites > maximumActiveWrites) {
      maximumActiveWrites = _activeWrites;
    }
    await Future<void>.delayed(Duration.zero);
    signal.throwIfCancelled();
    values[key] = checkpoint;
    writeCount += 1;
    _activeWrites -= 1;
  }
}
