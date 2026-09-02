import 'dart:convert';

import 'package:dartitect_observability/dartitect_observability.dart';

/// Informative calibrated timing plus mandatory deterministic budget gates.
void main() {
  const samples = 9;
  const warmupIterations = 500;
  const measuredIterations = 2000;
  const limits = ObservabilitySanitizationLimits(
    maxDepth: 4,
    maxCollectionLength: 8,
    maxStringCodePoints: 128,
    maxNodes: 64,
    maxTotalTextCodePoints: 512,
    maxStackFrames: 8,
    maxClassificationWork: 256,
  );
  final sanitizer = ObservabilitySanitizer(
    policy: ObservabilityPrivacyPolicy.fromProfile(
      profile: ObservabilityPrivacyProfile.diagnostic,
    ),
    limits: limits,
  );
  final fixture = ObservabilityClassifiedValue<Object?>(
    <String, Object?>{
      'status': 'ready',
      'attempt': 2,
      'email': 'person@example.com',
      'authorization': 'Bearer private-token',
      'nested': <String, Object?>{
        'path': '/accounts/private-id',
        'items': <Object?>[1, 2, 3, 'private-value'],
      },
    },
    classes: <ObservabilityDataClass>{ObservabilityDataClass.httpBody},
  );

  PreparedObservabilityValue operation() => sanitizer.prepare(
    fixture,
    destination: ObservabilityDestinationKind.remote,
  );

  for (var index = 0; index < warmupIterations; index += 1) {
    operation();
  }
  final timings = <double>[];
  for (var sample = 0; sample < samples; sample += 1) {
    final watch = Stopwatch()..start();
    for (var index = 0; index < measuredIterations; index += 1) {
      operation();
    }
    watch.stop();
    timings.add(watch.elapsedMicroseconds / measuredIterations);
  }
  timings.sort();

  final evidence = operation();
  final diagnostics = evidence.diagnostics;
  final deterministicFailures = <String>[
    if (diagnostics.visitedNodes > limits.maxNodes) 'nodes',
    if (diagnostics.textCodePoints > limits.maxTotalTextCodePoints) 'text',
    if (diagnostics.stackFrames > limits.maxStackFrames) 'frames',
    if (diagnostics.classificationWork > limits.maxClassificationWork)
      'classification',
  ];
  if (deterministicFailures.isNotEmpty) {
    throw StateError(
      'Deterministic privacy budgets failed: '
      '${deterministicFailures.join(', ')}.',
    );
  }

  // Timings are informational: machine variance never fails this benchmark.
  // ignore: avoid_print
  print(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schemaVersion': 1,
      'samples': samples,
      'warmupIterations': warmupIterations,
      'iterationsPerSample': measuredIterations,
      'medianMicrosecondsPerOperation': timings[timings.length ~/ 2],
      'timingGate': 'INFORMATIONAL_ONLY',
      'deterministicBudgetGate': 'PASS',
      'visitedNodes': diagnostics.visitedNodes,
      'textCodePoints': diagnostics.textCodePoints,
      'stackFrames': diagnostics.stackFrames,
      'classificationWork': diagnostics.classificationWork,
    }),
  );
}
