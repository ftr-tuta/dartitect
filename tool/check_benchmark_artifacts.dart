import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final workspace = Directory('${root.path}/tool/benchmark_workspace');
  final rawFile = File('${workspace.path}/artifacts/raw.json');
  final environmentFile = File('${workspace.path}/artifacts/environment.json');
  final reportFile = File('${workspace.path}/artifacts/report.adoc');
  final errors = <String>[];
  for (final file in <File>[rawFile, environmentFile, reportFile]) {
    if (!file.existsSync()) errors.add('Missing ${_relative(root, file)}.');
  }
  if (errors.isNotEmpty) _finish(errors);

  final rawSource = rawFile.readAsStringSync();
  final raw = _object(jsonDecode(rawSource));
  final environment = _object(jsonDecode(environmentFile.readAsStringSync()));
  final report = reportFile.readAsStringSync();
  _validateMetadata(
    root,
    workspace,
    rawSource,
    raw,
    environment,
    report,
    errors,
  );
  _validateFanout(raw, errors);
  _validateCollections(raw, errors);
  _validateWorkloads(raw, errors);
  _validateCommands(raw, errors);
  _validateCausalityRacesAndLeaks(raw, errors);
  _finish(errors);
}

void _validateMetadata(
  Directory root,
  Directory workspace,
  String rawSource,
  Map<String, Object?> raw,
  Map<String, Object?> environment,
  String report,
  List<String> errors,
) {
  if (raw['schemaVersion'] != 1 || environment['schemaVersion'] != 2) {
    errors.add('Benchmark raw/environment schemas must be versions 1/2.');
  }
  if (raw['seed'] != 140013 ||
      raw['warmupSamples'] != 3 ||
      raw['repetitions'] != 15) {
    errors.add('Benchmark seed/warm-up/repetition policy changed.');
  }
  final comparators = _object(raw['comparators']);
  const expected = <String, String>{
    'dartitect_flutter': '1.0.0-rc.1',
    'flutter_riverpod': '3.4.2',
    'flutter_bloc': '9.1.1',
    'bloc_concurrency': '0.3.0',
  };
  if (comparators.length != expected.length ||
      expected.entries.any((entry) => comparators[entry.key] != entry.value)) {
    errors.add('Comparator versions do not match the reviewed exact pins.');
  }
  final lock = File('${workspace.path}/pubspec.lock').readAsStringSync();
  if (environment['comparatorLockFnv1a'] != _fnv1a(lock)) {
    errors.add('Comparator lockfile hash does not match the environment.');
  }
  if (environment['rawFnv1a'] != _fnv1a(rawSource)) {
    errors.add('Raw benchmark hash does not match the environment.');
  }
  _validateSourceRevision(root, environment, report, errors);
  final generatedAt = environment['generatedAtUtc'];
  if (generatedAt is! String || DateTime.tryParse(generatedAt) == null) {
    errors.add('Environment generation timestamp is invalid.');
  }
  final memory = _object(environment['memory']);
  for (final name in const <String>[
    'rssBeforeBytes',
    'rssAfterBytes',
    'maxRssBytes',
    'heapBeforeBytes',
    'heapAfterBytes',
    'heapCapacityAfterBytes',
  ]) {
    if (memory[name] is! int || (memory[name]! as int) <= 0) {
      errors.add('Memory census field $name must be positive.');
    }
  }
  final encodedEnvironment = jsonEncode(environment);
  if (encodedEnvironment.contains('flutterRoot') ||
      encodedEnvironment.contains(root.path) ||
      rawSource.contains(root.path)) {
    errors.add('Benchmark artifacts must not expose local filesystem paths.');
  }
  if (!report.contains('Gate:: PASS') ||
      !report.contains('Residual listeners, nodes, timers, isolates') ||
      report.contains('== Failed gates')) {
    errors.add('Human-readable benchmark report is stale or failed.');
  }
  final rootPubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
  if (rootPubspec.contains('flutter_riverpod:') ||
      rootPubspec.contains('flutter_bloc:') ||
      rootPubspec.contains('bloc_concurrency:')) {
    errors.add('Comparator dependencies leaked into the runtime workspace.');
  }
}

void _validateSourceRevision(
  Directory root,
  Map<String, Object?> environment,
  String report,
  List<String> errors,
) {
  final rawSource = environment['sourceRevision'];
  if (rawSource is! Map<String, Object?> || rawSource.length != 2) {
    errors.add('Environment source revision is missing or invalid.');
    return;
  }
  const cohort = '1.0.0-rc.1';
  const status = 'REFERENCE_ONLY_REPRODUCTION_REQUIRED';
  if (rawSource['candidateCohort'] != cohort ||
      rawSource['evidenceStatus'] != status ||
      !report.contains('Candidate cohort:: `$cohort`') ||
      !report.contains('Evidence status:: `$status`')) {
    errors.add('Benchmark report source provenance is stale.');
  }
}

void _validateFanout(Map<String, Object?> raw, List<String> errors) {
  final rows = _objects(raw['fanout']);
  if (rows.length != 36) errors.add('Fan-out matrix must contain 36 rows.');
  for (final row in rows) {
    final samples = _numbers(row['samplesUsPerOperation']);
    if (samples.length != 15) {
      errors.add('${row['framework']} ${row['id']} must contain 15 samples.');
      continue;
    }
    _checkStatistics(row, samples, 'medianUs', 'p95Us', errors);
  }
  for (final listeners in const <int>[1, 10, 100, 1000]) {
    for (final changePercent in const <int>[0, 10, 100]) {
      final cell = rows
          .where(
            (row) =>
                row['listeners'] == listeners &&
                row['changePercent'] == changePercent,
          )
          .toList();
      if (cell.length != 3) {
        errors.add('Fan-out $listeners/$changePercent is incomplete.');
        continue;
      }
      final names = cell.map((row) => row['framework']).toSet();
      if (!names.containsAll(const <String>['dartitect', 'riverpod', 'bloc'])) {
        errors.add('Fan-out $listeners/$changePercent misses a comparator.');
        continue;
      }
      final dartitect = cell.singleWhere(
        (row) => row['framework'] == 'dartitect',
      );
      final comparators = cell.where((row) => row['framework'] != 'dartitect');
      final bestMedian = comparators
          .map((row) => (row['medianUs']! as num).toDouble())
          .reduce(min);
      final bestP95 = comparators
          .map((row) => (row['p95Us']! as num).toDouble())
          .reduce(min);
      if ((dartitect['medianUs']! as num) >
          max(bestMedian * 1.10, bestMedian + 5)) {
        errors.add('Fan-out $listeners/$changePercent median gate failed.');
      }
      if ((dartitect['p95Us']! as num) > max(bestP95 * 1.15, bestP95 + 10)) {
        errors.add('Fan-out $listeners/$changePercent p95 gate failed.');
      }
      final changed = changePercent == 0
          ? 0
          : max(1, listeners * changePercent ~/ 100);
      for (final row in cell) {
        if (row['selectionEvaluationsPerOperation'] != listeners ||
            row['callbacksPerOperation'] != changed ||
            row['residualResources'] != 0) {
          errors.add('${row['framework']} ${row['id']} did extra work.');
        }
      }
    }
  }
}

void _validateCollections(Map<String, Object?> raw, List<String> errors) {
  final rows = _objects(raw['collections']);
  const expected = <String, int>{
    'one-change': 1,
    'hundred-change': 100,
    'reorder': 0,
  };
  if (rows.length != expected.length) {
    errors.add('Collection matrix must contain three rows.');
  }
  for (final row in rows) {
    final name = row['scenario'];
    final changed = expected[name];
    final samples = _numbers(row['samplesUs']);
    if (changed == null ||
        samples.length != 15 ||
        row['entities'] != 10000 ||
        row['projectionCount'] != changed ||
        row['replaceAllProjectionCount'] != 10000 ||
        (row['projectionReduction']! as num) < 0.9 ||
        row['nodesAfterDispose'] != 0 ||
        row['timersAfterDispose'] != 0) {
      errors.add('Collection scenario $name failed matrix/work/leak gates.');
      continue;
    }
    _checkStatistics(row, samples, 'medianUs', 'p95Us', errors);
  }
}

void _validateWorkloads(Map<String, Object?> raw, List<String> errors) {
  final workloads = _object(raw['workloads']);
  final writes = _object(workloads['writes']);
  final signals = _object(workloads['signals']);
  final family = _object(workloads['family']);
  if (writes['writes'] != 1000 ||
      writes['computes'] != 1000 ||
      writes['notifications'] != 1000 ||
      writes['nodesAfterDispose'] != 0 ||
      writes['listenersAfterDispose'] != 0) {
    errors.add('1,000-write exact-work/leak gate failed.');
  }
  if (signals['signals'] != 100 ||
      signals['queryEntities'] != 10000 ||
      signals['signalReads'] != 2 ||
      signals['coalescedSignals'] != 98 ||
      signals['sourceSessionsAfterDispose'] != 0) {
    errors.add('100-signal/10k-query backpressure gate failed.');
  }
  if (family['keys'] != 1000 ||
      family['peakEntries'] != 64 ||
      family['entriesAfterDispose'] != 0 ||
      family['timersAfterDispose'] != 0) {
    errors.add('1,000-key family bound/leak gate failed.');
  }
  if (_numbers(writes['samplesUsPerWrite']).length != 15 ||
      _numbers(family['samplesUsPerAcquireRelease']).length != 15) {
    errors.add('Workload statistical samples are incomplete.');
  }
}

void _validateCommands(Map<String, Object?> raw, List<String> errors) {
  final commands = _object(raw['commands']);
  final dartitect = _objects(commands['dartitectPatterns']);
  final bloc = _objects(commands['blocConcurrencyPatterns']);
  const dartitectNames = <Object?>{
    'reject',
    'join',
    'drop',
    'sequential',
    'restartLatest',
    'concurrent',
    'keyed',
  };
  const blocNames = <Object?>{
    'concurrent',
    'sequential',
    'droppable',
    'restartable',
  };
  if (!_sameSet(
        dartitect.map((row) => row['pattern']).toSet(),
        dartitectNames,
      ) ||
      dartitect.any(
        (row) =>
            _numbers(row['samplesUsPerOperation']).length != 15 ||
            row['runningAfterDispose'] != 0 ||
            row['queuedAfterDispose'] != 0,
      )) {
    errors.add('Dartitect command pattern census is incomplete.');
  }
  if (!_sameSet(bloc.map((row) => row['pattern']).toSet(), blocNames) ||
      bloc.any((row) => row['handled'] != 50 || row['closed'] != true)) {
    errors.add('bloc_concurrency pattern census is incomplete.');
  }
}

void _validateCausalityRacesAndLeaks(
  Map<String, Object?> raw,
  List<String> errors,
) {
  final timeline = _object(raw['causalTimeline']);
  if (jsonEncode(timeline['phases']) !=
          jsonEncode(<String>[
            'requestStarted',
            'responseReceived',
            'localWriteCommitted',
            'localObserved',
            'completed',
          ]) ||
      timeline['nodesAfterDispose'] != 0 ||
      timeline['timersAfterDispose'] != 0 ||
      timeline['sourceSessionsAfterDispose'] != 0) {
    errors.add('Causal timeline or cleanup gate failed.');
  }
  final races = _object(raw['raceFuzz']);
  if (races['seed'] != 140015 ||
      races['steps'] != 1000 ||
      races['cancelledGenerations'] != 400 ||
      races['successfulGenerations'] != 100 ||
      races['latePublications'] != 0 ||
      races['nodesAfterDispose'] != 0 ||
      races['timersAfterDispose'] != 0 ||
      races['commandsAfterDispose'] != 0) {
    errors.add('Deterministic race-fuzz gate failed.');
  }
  final census = _object(raw['resourceCensus']);
  if (census.length != 8 || census.values.any((value) => value != 0)) {
    errors.add('Terminal resource census is not exactly zero.');
  }
}

void _checkStatistics(
  Map<String, Object?> row,
  List<double> samples,
  String medianName,
  String p95Name,
  List<String> errors,
) {
  final ordered = List<double>.of(samples)..sort();
  final median = ordered[(ordered.length * 0.5).ceil() - 1];
  final p95 = ordered[(ordered.length * 0.95).ceil() - 1];
  if ((row[medianName]! as num).toDouble() != median ||
      (row[p95Name]! as num).toDouble() != p95) {
    errors.add('${row['id'] ?? row['scenario']} statistics are stale.');
  }
}

bool _sameSet(Set<Object?> left, Set<Object?> right) =>
    left.length == right.length && left.containsAll(right);

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>();

List<double> _numbers(Object? value) => (value! as List<Object?>)
    .map((item) => (item! as num).toDouble())
    .toList(growable: false);

String _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _relative(Directory root, File file) => file.path
    .substring(root.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

Never _finish(List<String> errors) {
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exit(1);
  }
  stdout.writeln(
    'Competitive benchmark artifacts pass statistical, exact-work, '
    'incremental, race, memory, isolation, and zero-resource gates.',
  );
  exit(0);
}
