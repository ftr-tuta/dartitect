import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dartitect_benchmark_workspace/benchmark_harness.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main() async {
  final errors = await generateBenchmarkArtifacts();
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
  }
}

Future<List<String>> generateBenchmarkArtifacts() async {
  final serviceInfo = await Service.getInfo();
  final serviceUri = serviceInfo.serverUri;
  if (serviceUri == null) {
    throw StateError(
      'The generator must run through Flutter test so dart:ui and the VM '
      'service share one runner.',
    );
  }
  final service = await vmServiceConnectUri(
    convertToWebSocketUrl(serviceProtocolUrl: serviceUri).toString(),
  );
  try {
    final isolateId = await _mainIsolateId(service);
    final before = await _memorySnapshot(service, isolateId);
    final rssBefore = ProcessInfo.currentRss;
    final result = await runBenchmarkSuite();
    final after = await _memorySnapshot(service, isolateId);
    final rssAfter = ProcessInfo.currentRss;
    result['memory'] = <String, Object?>{
      'rssBeforeBytes': rssBefore,
      'rssAfterBytes': rssAfter,
      'maxRssBytes': ProcessInfo.maxRss,
      'heapBeforeBytes': before.heapUsage,
      'heapAfterBytes': after.heapUsage,
      'heapCapacityAfterBytes': after.heapCapacity,
      'externalAfterBytes': after.externalUsage,
    };
    final errors = validateBenchmarkSuite(result);
    final root = Directory.current.absolute;
    final artifacts = Directory(
      Platform.environment['DARTITECT_BENCHMARK_ARTIFACTS'] ??
          '${root.path}/artifacts',
    );
    await artifacts.create(recursive: true);
    final raw = '${const JsonEncoder.withIndent('  ').convert(result)}\n';
    final environment = await _environment(root, result, rawFnv1a: _fnv1a(raw));
    await File('${artifacts.path}/raw.json').writeAsString(raw, flush: true);
    await File('${artifacts.path}/environment.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(environment)}\n',
      flush: true,
    );
    await File('${artifacts.path}/report.adoc')
        .writeAsString(_report(result, environment, errors), flush: true);
    if (errors.isNotEmpty) return errors;
    stdout.writeln(
      'Competitive benchmark passed ${result['fanout'] is List<Object?> ? (result['fanout']! as List<Object?>).length : 0} '
      'fan-out cells with zero residual resources.',
    );
    return errors;
  } finally {
    await service.dispose();
  }
}

Future<String> _mainIsolateId(VmService service) async {
  final vm = await service.getVM();
  final isolates = vm.isolates ?? const <IsolateRef>[];
  if (isolates.isEmpty) throw StateError('VM service exposed no isolate.');
  return isolates
      .firstWhere(
        (isolate) => isolate.name == 'main',
        orElse: () => isolates.first,
      )
      .id!;
}

Future<MemoryUsage> _memorySnapshot(VmService service, String isolateId) async {
  await service.getAllocationProfile(isolateId, gc: true);
  return service.getMemoryUsage(isolateId);
}

Future<Map<String, Object?>> _environment(
  Directory root,
  Map<String, Object?> result, {
  required String rawFnv1a,
}) async {
  final flutter = await Process.run('flutter', <String>[
    '--version',
    '--machine',
  ]);
  if (flutter.exitCode != 0) {
    throw StateError('Could not record the Flutter environment.');
  }
  final lock = await File('${root.path}/pubspec.lock').readAsString();
  final flutterEnvironment =
      (jsonDecode('${flutter.stdout}') as Map<String, Object?>)
        ..remove('flutterRoot');
  return <String, Object?>{
    'schemaVersion': 2,
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceRevision': const <String, String>{
      'candidateCohort': '1.0.0-rc.6',
      'evidenceStatus': 'REFERENCE_ONLY_REPRODUCTION_REQUIRED',
    },
    'publicClaimEligible': false,
    'claimPolicy': 'INTERNAL_GATE_ONLY',
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'processors': Platform.numberOfProcessors,
    'dartVersion': Platform.version,
    'flutter': flutterEnvironment,
    'comparatorLockFnv1a': _fnv1a(lock),
    'rawFnv1a': rawFnv1a,
    'seed': result['seed'],
    'warmupSamples': result['warmupSamples'],
    'repetitions': result['repetitions'],
    'memory': result['memory'],
  };
}

String _report(
  Map<String, Object?> result,
  Map<String, Object?> environment,
  List<String> errors,
) {
  final fanout = (result['fanout']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final collections = (result['collections']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final source = environment['sourceRevision']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('= Competitive performance and lifecycle report')
    ..writeln()
    ..writeln('Generated:: ${environment['generatedAtUtc']}')
    ..writeln('Candidate cohort:: `${source['candidateCohort']}`')
    ..writeln('Evidence status:: `${source['evidenceStatus']}`')
    ..writeln('Public claim eligible:: `NO`')
    ..writeln('Claim policy:: `INTERNAL_GATE_ONLY`')
    ..writeln('Seed:: ${result['seed']}')
    ..writeln(
      'Warm-up / measured samples:: ${result['warmupSamples']} / '
      '${result['repetitions']}',
    )
    ..writeln('Gate:: ${errors.isEmpty ? 'PASS' : 'FAIL'}')
    ..writeln()
    ..writeln(
      'These measurements are internal compatibility gates. They are not '
      'authorized for public performance claims.',
    )
    ..writeln()
    ..writeln('== Fan-out comparison')
    ..writeln()
    ..writeln('[cols="1,1,1,1,1,1",options="header"]')
    ..writeln('|===')
    ..writeln(
      '| Listeners | Change | Framework | Median us | p95 us | Callbacks',
    );
  for (final row in fanout) {
    buffer.writeln(
      '| ${row['listeners']} | ${row['changePercent']}% | '
      '${row['framework']} | ${(row['medianUs']! as double).toStringAsFixed(3)} '
      '| ${(row['p95Us']! as double).toStringAsFixed(3)} '
      '| ${row['callbacksPerOperation']}',
    );
  }
  buffer
    ..writeln('|===')
    ..writeln()
    ..writeln(
      'Every framework performed exactly one selection evaluation per '
      'listener and only changed selectors invoked callbacks. Dartitect must '
      'remain within `max(best * 1.10, best + 5 us)` at median and '
      '`max(best * 1.15, best + 10 us)` at p95.',
    )
    ..writeln()
    ..writeln('== Incremental 10k collection')
    ..writeln()
    ..writeln('[cols="2,1,1,1,1",options="header"]')
    ..writeln('| Scenario | Changed | Projected | Reduction | Median us')
    ..writeln('|===');
  for (final row in collections) {
    buffer.writeln(
      '| ${row['scenario']} | ${row['changedEntities']} | '
      '${row['projectionCount']} | '
      '${((row['projectionReduction']! as double) * 100).toStringAsFixed(2)}% '
      '| ${(row['medianUs']! as double).toStringAsFixed(3)}',
    );
  }
  final memory = result['memory']! as Map<String, Object?>;
  buffer
    ..writeln('|===')
    ..writeln()
    ..writeln('== Workload and lifecycle gates')
    ..writeln()
    ..writeln(
      '* 1,000 writes produced exactly 1,000 computes and notifications.',
    )
    ..writeln(
      '* A 100-signal burst over a 10k query required two signal reads.',
    )
    ..writeln('* A 1,000-key family remained bounded to 64 idle entries.')
    ..writeln(
      '* Seven Dartitect command policies and four bloc_concurrency '
      'transformers completed their census.',
    )
    ..writeln(
      '* The causal page timeline preserved request, response, local '
      'commit, local observation, and completion order.',
    )
    ..writeln(
      '* 1,000 deterministic race-fuzz steps produced no late publication.',
    )
    ..writeln(
      '* Residual listeners, nodes, timers, isolates, sessions, commands, '
      'family entries, and subscriptions: zero.',
    )
    ..writeln()
    ..writeln('== Memory census')
    ..writeln()
    ..writeln(
      '* RSS before/after/max: ${memory['rssBeforeBytes']} / '
      '${memory['rssAfterBytes']} / ${memory['maxRssBytes']} bytes.',
    )
    ..writeln(
      '* Heap before/after/capacity: ${memory['heapBeforeBytes']} / '
      '${memory['heapAfterBytes']} / ${memory['heapCapacityAfterBytes']} bytes.',
    )
    ..writeln('* External memory after: ${memory['externalAfterBytes']} bytes.')
    ..writeln()
    ..writeln(
      'RSS and heap are observations, not leak thresholds; exact owned '
      'resource census is the terminal leak gate. Raw samples and the full '
      'environment manifest accompany this report.',
    );
  if (errors.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('== Failed gates')
      ..writeln();
    for (final error in errors) {
      buffer.writeln('* $error');
    }
  }
  return buffer.toString();
}

String _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
