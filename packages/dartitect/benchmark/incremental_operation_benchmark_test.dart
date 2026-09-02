import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect_incremental.dart';
import 'package:test/test.dart';

const _scales = <int>[0, 1, 32, 1000, 100000];

void main() {
  test(
    'incremental inputs retain no values and report curated scales',
    () async {
      final samples = <Map<String, Object?>>[];
      for (final count in _scales) {
        samples.add(await _measure('eager', count, _eager(count)));
      }
      for (final count in const <int>[32, 1000, 100000]) {
        samples.add(
          await _measure('sync-generator', count, _syncGenerator(count)),
        );
      }
      samples.add(await _measureAsync('async-generator', 1000));

      final batchWatch = Stopwatch()..start();
      final batches =
          await IncrementalOperation<List<int>, _Failure>.sync(
            () => _batches(100000, 1000),
          ).fold<int>(
            initial: 0,
            reducer: (total, batch, _) => total + batch.length,
          );
      batchWatch.stop();
      expect(batches.aggregate, 100000);
      expect(batches.report.emissionCount, 100);
      samples.add(<String, Object?>{
        'shape': 'batches',
        'logicalItems': 100000,
        'emissions': batches.report.emissionCount,
        'totalMicros': batchWatch.elapsedMicroseconds,
      });

      final rssBefore = ProcessInfo.currentRss;
      final repeatedMicros = <int>[];
      for (var repetition = 0; repetition < 15; repetition++) {
        final watch = Stopwatch()..start();
        final result = await IncrementalOperation<int, _Failure>.sync(
          () => _syncGenerator(1000),
        ).consume(onValue: (_, _) {});
        watch.stop();
        expect(result.report.emissionCount, 1000);
        repeatedMicros.add(watch.elapsedMicroseconds);
      }
      final rssAfter = ProcessInfo.currentRss;

      stdout.writeln(
        jsonEncode(<String, Object?>{
          'benchmark': 'incremental-core',
          'metrics': 'informative',
          'samples': samples,
          'sameRunnerSummary': <String, Object?>{
            'repetitions': repeatedMicros.length,
            'p50Micros': _percentile(repeatedMicros, 0.50),
            'p95Micros': _percentile(repeatedMicros, 0.95),
            'rssBytes': <String, int>{'before': rssBefore, 'after': rssAfter},
          },
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('slow consumers backpressure and cancellation drains cleanup', () async {
    var activeConsumers = 0;
    var maximumActiveConsumers = 0;
    final slow = IncrementalOperation<int, _Failure>.async(
      () => _asyncGenerator(32),
    );
    final slowWatch = Stopwatch()..start();
    final slowResult = await slow.consume(
      onValue: (_, _) async {
        activeConsumers += 1;
        maximumActiveConsumers = maximumActiveConsumers < activeConsumers
            ? activeConsumers
            : maximumActiveConsumers;
        await Future<void>.delayed(Duration.zero);
        activeConsumers -= 1;
      },
    );
    slowWatch.stop();

    final cancellation = CancellationSource();
    var produced = 0;
    var cleaned = false;
    Stream<Result<int, _Failure>> cancellable() async* {
      try {
        for (var value = 0; value < 100000; value++) {
          produced += 1;
          yield Ok<int>(value);
        }
      } finally {
        cleaned = true;
      }
    }

    final cancelled = IncrementalOperation<int, _Failure>.async(cancellable);
    await expectLater(
      cancelled.consume(
        cancellation: cancellation.signal,
        onValue: (_, context) {
          if (context.sequence == 32) cancellation.cancel('benchmark bound');
        },
      ),
      throwsA(isA<CancellationException>()),
    );

    expect(slowResult.report.emissionCount, 32);
    expect(maximumActiveConsumers, 1);
    expect(produced, 32);
    expect(cleaned, isTrue);
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'benchmark': 'incremental-backpressure-cancellation',
        'metrics': 'informative',
        'slowConsumerTotalMicros': slowWatch.elapsedMicroseconds,
        'maximumActiveConsumers': maximumActiveConsumers,
        'cancelledAfter': produced,
        'cleanupComplete': cleaned,
      }),
    );
  });
}

Future<Map<String, Object?>> _measure(
  String shape,
  int count,
  Iterable<Result<int, _Failure>> values,
) async {
  final watch = Stopwatch()..start();
  int? firstItemMicros;
  final result = await IncrementalOperation<int, _Failure>.sync(() => values)
      .fold<int>(
        initial: 0,
        reducer: (total, item, _) {
          firstItemMicros ??= watch.elapsedMicroseconds;
          return total + item;
        },
      );
  watch.stop();
  expect(result.report.emissionCount, count);
  expect(result.aggregate, count == 0 ? 0 : (count - 1) * count ~/ 2);
  return <String, Object?>{
    'shape': shape,
    'logicalItems': count,
    'emissions': result.report.emissionCount,
    'firstItemMicros': firstItemMicros,
    'totalMicros': watch.elapsedMicroseconds,
  };
}

Future<Map<String, Object?>> _measureAsync(String shape, int count) async {
  final watch = Stopwatch()..start();
  int? firstItemMicros;
  final result =
      await IncrementalOperation<int, _Failure>.async(
        () => _asyncGenerator(count),
      ).fold<int>(
        initial: 0,
        reducer: (total, item, _) {
          firstItemMicros ??= watch.elapsedMicroseconds;
          return total + item;
        },
      );
  watch.stop();
  expect(result.report.emissionCount, count);
  expect(result.aggregate, (count - 1) * count ~/ 2);
  return <String, Object?>{
    'shape': shape,
    'logicalItems': count,
    'emissions': result.report.emissionCount,
    'firstItemMicros': firstItemMicros,
    'totalMicros': watch.elapsedMicroseconds,
  };
}

List<Result<int, _Failure>> _eager(int count) => <Result<int, _Failure>>[
  for (var value = 0; value < count; value++) Ok<int>(value),
];

Iterable<Result<int, _Failure>> _syncGenerator(int count) sync* {
  for (var value = 0; value < count; value++) {
    yield Ok<int>(value);
  }
}

Stream<Result<int, _Failure>> _asyncGenerator(int count) async* {
  for (var value = 0; value < count; value++) {
    yield Ok<int>(value);
  }
}

Iterable<Result<List<int>, _Failure>> _batches(int count, int batchSize) sync* {
  for (var start = 0; start < count; start += batchSize) {
    final end = start + batchSize > count ? count : start + batchSize;
    yield Ok<List<int>>(<int>[
      for (var value = start; value < end; value++) value,
    ]);
  }
}

int _percentile(List<int> samples, double percentile) {
  final ordered = List<int>.of(samples)..sort();
  return ordered[((ordered.length - 1) * percentile).ceil()];
}

final class _Failure implements Exception {}
