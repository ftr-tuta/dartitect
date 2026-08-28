import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versioned restoration codec remains deterministic under churn', () {
    const iterations = 100000;
    final codec = VersionedRestorationCodec<int, String>(
      currentVersion: 2,
      encodePayload: (value) => value,
      decodePayload: (payload) => payload is int
          ? Ok<int>(payload)
          : const Err<String>('invalid', StackTrace.empty),
      mapIssue: (issue) => issue.name,
      migrations: <int, VersionedRestorationMigration<String>>{
        1: (payload) => Ok<Object?>(payload),
      },
    );
    var decodedTotal = 0;
    final stopwatch = Stopwatch()..start();
    for (var value = 0; value < iterations; value += 1) {
      final decoded = codec.decode(codec.encode(value));
      switch (decoded) {
        case Ok<dynamic>(:final value):
          decodedTotal += value as int;
        case Err<Object>():
          fail('Deterministic restoration round-trip failed.');
      }
    }
    stopwatch.stop();
    expect(decodedTotal, (iterations - 1) * iterations ~/ 2);
    stdout.writeln(
      jsonEncode(<String, Object>{
        'iterations': iterations,
        'nanosecondsPerEncodeDecode':
            (stopwatch.elapsedMicroseconds * 1000) / iterations,
      }),
    );
  });
}
