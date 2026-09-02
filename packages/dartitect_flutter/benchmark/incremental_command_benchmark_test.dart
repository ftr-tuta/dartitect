import 'dart:convert';

import 'package:dartitect_flutter/dartitect_flutter_incremental.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coalesced command reduces all items with bounded notifications',
    () async {
      const iterations = 1000;
      final frames = _BenchmarkFrameScheduler();
      final command = IncrementalCommand<int, int, _Failure, int>(
        operation: IncrementalOperation<int, _Failure>.sync(() sync* {
          for (var value = 1; value <= iterations; value++) {
            yield Ok<int>(value);
          }
        }),
        initialAggregate: () => 0,
        reducer: (aggregate, item, _) => aggregate + item,
        progressOf: (_, aggregate, _) => aggregate,
        publication: IncrementalPublication.coalesceFrame,
        frameScheduler: frames,
      );
      var notifications = 0;
      command.addListener(() => notifications += 1);

      final watch = Stopwatch()..start();
      await command.execute();
      watch.stop();

      final state =
          command.state as IncrementalCommandSucceeded<int, _Failure, int>;
      expect(state.emissionCount, iterations);
      expect(state.aggregate, iterations * (iterations + 1) ~/ 2);
      expect(notifications, lessThan(iterations));
      expect(frames.pendingCount, 1);
      final notificationsAtTerminal = notifications;
      frames.flush();
      expect(notifications, notificationsAtTerminal);
      await command.disposeAsync();
      expect(command.isDisposed, isTrue);
      // ignore: avoid_print
      print(
        jsonEncode(<String, Object?>{
          'benchmark': 'incremental-flutter-command',
          'metrics': 'informative',
          'emissions': iterations,
          'notifications': notifications,
          'totalMicros': watch.elapsedMicroseconds,
        }),
      );
    },
  );
}

final class _Failure implements Exception {}

final class _BenchmarkFrameScheduler implements SourceFrameScheduler {
  final _callbacks = <VoidCallback>[];

  int get pendingCount => _callbacks.length;

  @override
  void schedule(VoidCallback callback) => _callbacks.add(callback);

  void flush() {
    final callbacks = List<VoidCallback>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}
