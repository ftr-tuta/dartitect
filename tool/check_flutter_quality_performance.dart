import 'dart:convert';
import 'dart:io';

const _collectors = <String>[
  'firstFrameMicros',
  'usefulStateMicros',
  'firstSearchResultMicros',
  'buildP50Micros',
  'buildP95Micros',
  'rasterP50Micros',
  'rasterP95Micros',
  'framesAboveBudget',
  'rebuilds',
  'materializedRows',
  'totalRows',
  'maxQueuedCommands',
  'cancellations',
  'disposals',
  'frameworkErrors',
  'overflows',
  'latePublications',
  'residualResources',
  'rssDeltaBytes',
];
const _blockers = <String>[
  'zero-overflow',
  'zero-framework-error',
  'zero-late-publication',
  'zero-residual-resource',
  'rows-materialized-under-100-of-10000',
  'state-preserved-on-resize',
  'no-heavy-ui-work',
  'no-preview-network-or-plugin',
  'images-constrained',
];
const _informative = <String>[
  'frame-time',
  'memory',
  'rebuild-counts',
  'queue-depth',
  'cancellation-and-disposal-counts',
];
const _equivalence = <String>[
  'runner',
  'flutterVersion',
  'buildMode',
  'fixture',
  'observationWindow',
];

Future<void> main(List<String> arguments) async {
  try {
    final root = _root(arguments);
    final contract = _map(
      jsonDecode(
        File('${root.path}/tool/flutter_quality_performance_contract.json')
            .readAsStringSync(),
      ),
    );
    final failures = <String>[];
    void require(bool condition, String message) {
      if (!condition) failures.add(message);
    }

    require(contract['schemaVersion'] == 1, 'Unsupported performance schema.');
    require(
      contract['artifact'] == 'flutter-quality-performance-v1',
      'Wrong performance artifact.',
    );
    require(
      contract['scope'] == 'test-only-canary-support',
      'Collectors must stay in test-only canary support.',
    );
    require(
      _same(_strings(contract['collectors']), _collectors),
      'Performance collectors are incomplete or reordered.',
    );
    require(
      _same(_strings(contract['structuralBlockers']), _blockers),
      'Structural performance blockers differ from UI quality v2.',
    );
    require(
      _same(_strings(contract['informative']), _informative),
      'Informative evidence fields changed.',
    );
    require(
      _same(_strings(contract['baselineEquivalence']), _equivalence),
      'Baseline equivalence is incomplete.',
    );
    final thresholds = _map(contract['thresholds']);
    require(
      thresholds.length == 2 &&
          thresholds.values.every((value) => value == false),
      'Frame-time and memory thresholds must remain disabled.',
    );

    final staticEvidence = _map(contract['staticEvidence']);
    require(
      staticEvidence['noHeavyUiWork'] == 'dartitect ui audit --strict',
      'Heavy UI work must use the strict audit.',
    );
    require(
      staticEvidence['noPreviewNetworkOrPlugin'] ==
          'dartitect inspect flutter-quality',
      'Preview isolation must use the Flutter quality inspector.',
    );
    require(
      staticEvidence['imagesConstrained'] == 'DT3144',
      'Image constraints must use DT3144.',
    );

    final canaries = _map(contract['canaries']);
    require(
      canaries.keys.toList().join(',') == 'pavedRoad,referenceApp',
      'Expected exactly the paved-road and reference-app canaries.',
    );
    for (final entry in canaries.entries) {
      final canary = _map(entry.value);
      final testPath = '${canary['test']}';
      final probePath = '${canary['probe']}';
      final testSource = _read(root, testPath, failures);
      final probeSource = _read(root, probePath, failures);
      require(
        probePath.contains('/test/support/'),
        '${entry.key} probe is not test-only support.',
      );
      for (final token in const <String>[
        'addTimingsCallback',
        'buildP50Micros',
        'rasterP95Micros',
        'ProcessInfo.currentRss',
        'structuralFailures',
        'residualResources',
      ]) {
        require(
          probeSource.contains(token),
          '${entry.key} probe lacks $token.',
        );
      }
      for (final token in const <String>[
        'recordStatePreserved',
        'recordResourceCensus',
        'recordDisposal',
        'structuralFailures',
      ]) {
        require(
          testSource.contains(token),
          '${entry.key} workload lacks $token.',
        );
      }
    }

    final referenceTest = _read(
      root,
      'examples/reference_app/test/flutter_quality_performance_test.dart',
      failures,
    );
    for (final token in const <String>[
      'totalRows: 10000',
      'lessThan(100)',
      'recordCancellation',
      'activeTimerCount',
      'observationWaiterCount',
    ]) {
      require(
        referenceTest.contains(token),
        'Reference workload lacks $token.',
      );
    }
    final pavedTest = _read(
      root,
      'examples/paved_road_canary/test/flutter_quality_performance_test.dart',
      failures,
    );
    require(
      pavedTest.contains('NavigationRail') &&
          pavedTest.contains("find.text('value 1')"),
      'Paved-road workload does not prove responsive command state.',
    );

    for (final path in const <String>[
      'packages/dartitect_flutter_testing/lib/src/dev/preview_fixture.dart',
      'examples/paved_road_canary/lib/src/dev/ui_quality_previews.dart',
      'examples/reference_app/lib/src/dev/tasks_previews.dart',
    ]) {
      final source = _read(root, path, failures);
      for (final prohibited in const <String>[
        'dart:io',
        'dart:ffi',
        'package:dio/',
        'package:dartitect_drift/',
        'package:dartitect_objectbox/',
      ]) {
        require(
          !source.contains(prohibited),
          '$path reaches prohibited $prohibited.',
        );
      }
    }

    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
    stdout.writeln(
      'flutter-quality-performance-v1 passed: two real canary workloads, '
      'nine structural blockers, and threshold-free timing/memory evidence.',
    );
  } on Object catch (error) {
    stderr.writeln('Flutter quality performance validation failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

Directory _root(List<String> arguments) {
  Directory? root;
  for (final argument in arguments) {
    if (argument.startsWith('--root=')) {
      if (root != null) throw const FormatException('Duplicate root.');
      root = Directory(argument.substring('--root='.length)).absolute;
    } else {
      throw FormatException('Unknown argument: $argument');
    }
  }
  return root ?? File.fromUri(Platform.script).parent.parent.absolute;
}

String _read(Directory root, String path, List<String> failures) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    failures.add('Missing $path.');
    return '';
  }
  return file.readAsStringSync();
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);
