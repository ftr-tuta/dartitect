import 'dart:convert';
import 'dart:io';

import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lazy computed is one evaluation per observed owner commit', () async {
    const iterations = 10000;
    final owner = ReactiveOwner();
    final input = owner.value(0);
    var computes = 0;
    final lazy = owner.lazyComputed<int>(
      label: 'benchmark.lazy',
      dependencies: () => <ValueListenable<Object?>>[input],
      compute: (read) {
        computes += 1;
        return read.read(input) * 2;
      },
    )..addListener(() {});

    final stopwatch = Stopwatch()..start();
    for (var index = 1; index <= iterations; index += 1) {
      owner.update<void>((write) => write.set(input, index));
    }
    stopwatch.stop();
    expect(lazy.value, iterations * 2);
    expect(computes, iterations + 1);
    await owner.dispose();
    expect(owner.diagnostics.nodeCount, 0);
    stdout.writeln(
      jsonEncode(<String, Object>{
        'iterations': iterations,
        'microsecondsPerObservedCommit':
            stopwatch.elapsedMicroseconds / iterations,
        'computesPerCommit': (computes - 1) / iterations,
      }),
    );
  });
}
