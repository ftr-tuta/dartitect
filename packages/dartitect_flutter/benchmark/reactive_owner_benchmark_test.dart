import 'dart:convert';
import 'dart:io';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('atomic graph cycle has one compute and no residual nodes', () async {
    const iterations = 10000;
    final owner = ReactiveOwner();
    final input = owner.value(0);
    var computes = 0;
    final doubled = owner.computed<int>(
      const ReactiveKey<int>(
        'benchmark.doubled',
        namespace: 'dartitect.benchmark',
        definitionRevision: 1,
        definitionFingerprint: 'doubled-v1',
      ),
      <ReactiveNode<Object?>>[input],
      (read) {
        computes += 1;
        return read.read(input) * 2;
      },
    );
    var notifications = 0;
    doubled.addListener(() => notifications += 1);

    for (var index = 1; index <= 1000; index += 1) {
      owner.update<void>((write) => write.set(input, index));
    }
    final stopwatch = Stopwatch()..start();
    for (var index = 1; index <= iterations; index += 1) {
      owner.update<void>((write) {
        write.set(input, index);
        write.set(input, index + 1);
        write.set(input, index + 2);
      });
    }
    stopwatch.stop();
    final diagnosticsBeforeDispose = owner.diagnostics;
    await owner.dispose();
    final diagnosticsAfterDispose = owner.diagnostics;

    expect(computes, iterations + 1001);
    expect(notifications, iterations + 1000);
    expect(diagnosticsAfterDispose.nodeCount, 0);
    expect(diagnosticsAfterDispose.listenerCount, 0);
    stdout.writeln(
      jsonEncode(<String, Object>{
        'iterations': iterations,
        'microsecondsPerAtomicCycle':
            stopwatch.elapsedMicroseconds / iterations,
        'computesPerCycle': (computes - 1001) / iterations,
        'notificationsPerCycle': (notifications - 1000) / iterations,
        'nodesBeforeDispose': diagnosticsBeforeDispose.nodeCount,
        'nodesAfterDispose': diagnosticsAfterDispose.nodeCount,
        'listenersAfterDispose': diagnosticsAfterDispose.listenerCount,
      }),
    );
  });
}
