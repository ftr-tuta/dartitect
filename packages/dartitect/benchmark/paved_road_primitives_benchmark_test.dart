import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('typed progress and local history stay bounded under churn', () {
    const iterations = 100000;
    final progress = BoundedProgressReporter<int>(capacity: 64);
    final progressWatch = Stopwatch()..start();
    for (var sequence = 1; sequence <= iterations; sequence += 1) {
      progress.report(
        OperationProgress<int>(
          executionId: 1,
          sequence: sequence,
          payload: sequence,
        ),
      );
    }
    progressWatch.stop();
    expect(progress.events, hasLength(64));

    final history = BoundedLocalHistory<int>(initialValue: 0, maxEntries: 64);
    final historyWatch = Stopwatch()..start();
    for (var value = 1; value <= iterations; value += 1) {
      history.edit(value);
    }
    for (var index = 0; index < 63; index += 1) {
      expect(history.undo(), isTrue);
      expect(history.redo(), isTrue);
    }
    historyWatch.stop();
    expect(history.retainedEntryCount, 64);

    progress.dispose();
    history.dispose();
    expect(progress.events, isEmpty);
    expect(history.retainedEntryCount, 0);
    stdout.writeln(
      jsonEncode(<String, Object>{
        'iterations': iterations,
        'progressNanosecondsPerPublication':
            (progressWatch.elapsedMicroseconds * 1000) / iterations,
        'historyNanosecondsPerEdit':
            (historyWatch.elapsedMicroseconds * 1000) / iterations,
        'retainedProgressAfterDispose': progress.events.length,
        'retainedHistoryAfterDispose': history.retainedEntryCount,
      }),
    );
  });
}
