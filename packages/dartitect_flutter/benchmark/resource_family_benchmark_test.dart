import 'dart:convert';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded family churn plateaus and releases all entries', () async {
    await _runChurn(200);

    const iterations = 5000;
    final stopwatch = Stopwatch()..start();
    final metrics = await _runChurn(iterations);
    stopwatch.stop();
    final microsPerCycle =
        stopwatch.elapsedMicroseconds / iterations.toDouble();

    // ignore: avoid_print
    print(
      jsonEncode(<String, Object>{
        'iterations': iterations,
        'microsecondsPerAcquireRelease': microsPerCycle,
        'peakEntries': metrics.peakEntries,
        'retainedBeforeDispose': metrics.retainedBeforeDispose,
        'entriesAfterDispose': metrics.entriesAfterDispose,
        'timersAfterDispose': metrics.timersAfterDispose,
      }),
    );
    expect(metrics.peakEntries, 64);
    expect(metrics.retainedBeforeDispose, 64);
    expect(metrics.entriesAfterDispose, 0);
    expect(metrics.timersAfterDispose, 0);
  });
}

Future<
  ({
    int peakEntries,
    int retainedBeforeDispose,
    int entriesAfterDispose,
    int timersAfterDispose,
  })
>
_runChurn(int iterations) async {
  final family = ResourceFamily<int, int, String>(
    create: (_) => LiveResource<int, String>(source: const _NeverSource()),
    policy: FamilyCachePolicy<int, int>(
      idleTtl: const Duration(hours: 1),
      maxIdleEntries: 64,
      maxIdleWeight: 64,
    ),
    timerFactory: const _NoOpTimerFactory(),
  );
  var peakEntries = 0;
  for (var key = 0; key < iterations; key += 1) {
    await family.acquire(key).release();
    if (family.entryCount > peakEntries) peakEntries = family.entryCount;
  }
  final retained = family.entryCount;
  await family.dispose();
  return (
    peakEntries: peakEntries,
    retainedBeforeDispose: retained,
    entriesAfterDispose: family.entryCount,
    timersAfterDispose: family.activeTimerCount,
  );
}

final class _NeverSource implements ReactiveSource<int, String> {
  const _NeverSource();

  @override
  Future<Result<ReactiveSourceSession<int, String>, String>> open() {
    throw StateError('Cold benchmark resources must not open a source.');
  }
}

final class _NoOpTimerFactory implements ReactiveTimerFactory {
  const _NoOpTimerFactory();

  @override
  ReactiveTimerHandle schedule(Duration duration, void Function() callback) =>
      _NoOpTimer();
}

final class _NoOpTimer implements ReactiveTimerHandle {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;
}
