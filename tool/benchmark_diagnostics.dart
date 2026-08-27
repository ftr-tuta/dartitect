import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      (arguments.single != 'debug' && arguments.single != 'profile')) {
    stderr.writeln(
      'Usage: dart [--enable-asserts] run '
      'tool/benchmark_diagnostics.dart <debug|profile>',
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
    stderr.writeln(
      '$mode mode does not match assertion state $assertionsEnabled.',
    );
    exitCode = 64;
    return;
  }

  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final contract = jsonDecode(
    File('${root.path}/tool/diagnostics_benchmark_contract.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  if (contract['schemaVersion'] != 1) {
    throw const FormatException('Unsupported diagnostics benchmark schema.');
  }
  final samples = contract['samples']! as int;
  final warmupIterations = contract['warmupIterations']! as int;
  final measuredIterations = contract['measuredIterations']! as int;
  final capacity = contract['bufferCapacity']! as int;
  final budgets =
      (contract['budgets']! as Map<String, Object?>)[mode]!
          as Map<String, Object?>;

  _measure(
    iterations: warmupIterations,
    detail: DartitectDiagnosticDetail.off,
    capacity: capacity,
  );
  _measure(
    iterations: warmupIterations,
    detail: DartitectDiagnosticDetail.topology,
    capacity: capacity,
  );

  final offSamples = <int>[];
  final topologySamples = <int>[];
  for (var sample = 0; sample < samples; sample += 1) {
    offSamples.add(
      _measure(
        iterations: measuredIterations,
        detail: DartitectDiagnosticDetail.off,
        capacity: capacity,
      ),
    );
    topologySamples.add(
      _measure(
        iterations: measuredIterations,
        detail: DartitectDiagnosticDetail.topology,
        capacity: capacity,
      ),
    );
  }
  offSamples.sort();
  topologySamples.sort();
  final offMedian = offSamples[offSamples.length ~/ 2];
  final topologyMedian = topologySamples[topologySamples.length ~/ 2];
  final maxOff = budgets['maxOffNanosecondsPerEvent']! as int;
  final maxTopology = budgets['maxTopologyNanosecondsPerEvent']! as int;
  final retained = DartitectDiagnosticBuffer(capacity: capacity);
  final emitter = DartitectDiagnosticsEmitter(
    reporter: DartitectDiagnosticReporterRegistration.borrowed(retained),
    idGenerator: _DiagnosticIds(),
    detail: DartitectDiagnosticDetail.topology,
  );
  final subject = emitter.subject(DartitectDiagnosticSubjectKind.resource);
  for (var index = 0; index < capacity * 4; index += 1) {
    subject.emit(DartitectDiagnosticPhase.updated, revision: index);
  }
  final retainedAtCapacity = retained.length;
  retained.dispose();
  final retainedAfterDispose = retained.length;
  final failures = <String>[
    if (offMedian > maxOff)
      'off median $offMedian ns/event exceeded $maxOff ns/event',
    if (topologyMedian > maxTopology)
      'topology median $topologyMedian ns/event exceeded $maxTopology ns/event',
    if (retainedAtCapacity != capacity)
      'bounded retention was $retainedAtCapacity instead of $capacity',
    if (retainedAfterDispose != 0)
      'disposed buffer retained $retainedAfterDispose events',
  ];
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'mode': mode,
      'assertionsEnabled': assertionsEnabled,
      'samples': samples,
      'iterationsPerSample': measuredIterations,
      'offNanosecondsPerEvent': offMedian,
      'topologyNanosecondsPerEvent': topologyMedian,
      'topologyOverheadNanosecondsPerEvent': topologyMedian - offMedian,
      'boundedCapacity': capacity,
      'retainedAtCapacity': retainedAtCapacity,
      'retainedAfterDispose': retainedAfterDispose,
      'gate': failures.isEmpty ? 'PASS' : 'FAIL',
    }),
  );
  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
  }
}

int _measure({
  required int iterations,
  required DartitectDiagnosticDetail detail,
  required int capacity,
}) {
  final buffer = DartitectDiagnosticBuffer(capacity: capacity);
  final emitter = DartitectDiagnosticsEmitter(
    reporter: DartitectDiagnosticReporterRegistration.borrowed(buffer),
    idGenerator: _DiagnosticIds(),
    detail: detail,
  );
  final subject = emitter.subject(DartitectDiagnosticSubjectKind.resource);
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index += 1) {
    subject.emit(DartitectDiagnosticPhase.updated, revision: index);
  }
  stopwatch.stop();
  buffer.dispose();
  return (stopwatch.elapsedMicroseconds * 1000) ~/ iterations;
}

final class _DiagnosticIds implements IdGenerator {
  var _next = 0;

  @override
  String nextId() {
    _next += 1;
    return '00000000-0000-4000-8000-${_next.toString().padLeft(12, '0')}';
  }
}
