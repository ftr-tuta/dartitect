import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      (arguments.single != 'debug' && arguments.single != 'profile')) {
    stderr.writeln(
      'Usage: dart [--enable-asserts] run '
      'tool/benchmark_lifecycle_churn.dart <debug|profile>',
    );
    exitCode = 64;
    return;
  }
  final mode = arguments.single;
  var assertionsEnabled = false;
  assert(() {
    assertionsEnabled = true;
    return true;
  }());
  if ((mode == 'debug') != assertionsEnabled) {
    stderr.writeln('$mode mode does not match the assertion state.');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final contract = jsonDecode(
    File('${root.path}/tool/lifecycle_churn_benchmark_contract.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  if (contract['schemaVersion'] != 1) {
    throw const FormatException('Unsupported lifecycle benchmark schema.');
  }
  final warmup = contract['warmupIterations']! as int;
  final iterations = contract['measuredIterations']! as int;
  final sampleCount = contract['samples']! as int;
  final budget =
      ((contract['budgets']! as Map<String, Object?>)[mode]!
              as Map<String, Object?>)['maxNanosecondsPerCreateDispose']!
          as int;

  await _measure(warmup);
  final samples = <int>[];
  for (var sample = 0; sample < sampleCount; sample += 1) {
    samples.add(await _measure(iterations));
  }
  samples.sort();
  final median = samples[samples.length ~/ 2];
  final failures = <String>[
    if (median > budget) 'median $median ns/create-dispose exceeded $budget ns',
  ];
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'mode': mode,
      'assertionsEnabled': assertionsEnabled,
      'samples': sampleCount,
      'iterationsPerSample': iterations,
      'nanosecondsPerCreateDispose': median,
      'ownedCleanupResidual': 0,
      'runningCommandsResidual': 0,
      'queuedCommandsResidual': 0,
      'gate': failures.isEmpty ? 'PASS' : 'FAIL',
    }),
  );
  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
  }
}

Future<int> _measure(int iterations) async {
  var cleanupCalls = 0;
  final stopwatch = Stopwatch()..start();
  for (var iteration = 0; iteration < iterations; iteration += 1) {
    final owner = ResourceOwner();
    owner.own<int>(iteration, (_) => cleanupCalls += 1);
    final command = CommandLane<int, String>(
      action: (_) async => const Ok<int>(1),
    );
    final outcome = await command.execute();
    if (outcome is! CommandSucceeded<int, String>) {
      throw StateError('Lifecycle benchmark command did not succeed.');
    }
    await command.dispose();
    await owner.disposeAsync();
    if (!owner.isDisposed ||
        command.runningCount != 0 ||
        command.queuedCount != 0) {
      throw StateError('Lifecycle benchmark retained resources.');
    }
  }
  stopwatch.stop();
  if (cleanupCalls != iterations) {
    throw StateError('Lifecycle benchmark missed owned cleanup.');
  }
  return (stopwatch.elapsedMicroseconds * 1000) ~/ iterations;
}
