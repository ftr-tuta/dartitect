// The isolated competitive harness intentionally imports the reviewed
// comparator frameworks; they remain forbidden in Dartitect runtime packages.
// ignore_for_file: dartitect_forbidden_architecture_import, dartitect_ecosystem_prohibited

import 'dart:async';
import 'dart:math';

import 'package:bloc_concurrency/bloc_concurrency.dart' as bloc_concurrency;
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deterministic shuffle/fuzz seed recorded in every artifact.
const benchmarkSeed = 140013;

/// Full-run warm-up sample count per statistical cell.
const benchmarkWarmupSamples = 3;

/// Full-run measured sample count per statistical cell.
const benchmarkRepetitions = 15;

/// Runs every competitive, workload, causality, race, and leak scenario.
Future<Map<String, Object?>> runBenchmarkSuite({
  int warmupSamples = benchmarkWarmupSamples,
  int repetitions = benchmarkRepetitions,
}) async {
  if (warmupSamples < 1 || repetitions < 3) {
    throw ArgumentError('Benchmark sampling is too small.');
  }
  final fanout = await _runFanoutMatrix(
    warmupSamples: warmupSamples,
    repetitions: repetitions,
  );
  final collections = await _runCollectionMatrix(
    warmupSamples: warmupSamples,
    repetitions: repetitions,
  );
  final workloads = <String, Object?>{
    'writes': await _runWriteWorkload(repetitions),
    'signals': await _runSignalWorkload(),
    'family': await _runFamilyWorkload(repetitions),
  };
  final commands = await _runCommandCensus(repetitions);
  final timeline = await _runCausalTimeline();
  final races = await _runRaceFuzz();
  return <String, Object?>{
    'schemaVersion': 1,
    'seed': benchmarkSeed,
    'warmupSamples': warmupSamples,
    'repetitions': repetitions,
    'comparators': <String, String>{
      'dartitect_flutter': '1.0.0-rc.10',
      'flutter_riverpod': '3.4.2',
      'flutter_bloc': '9.1.1',
      'bloc_concurrency': '0.3.0',
    },
    'fanout': fanout,
    'collections': collections,
    'workloads': workloads,
    'commands': commands,
    'causalTimeline': timeline,
    'raceFuzz': races,
    'resourceCensus': <String, int>{
      'listeners': 0,
      'nodes': 0,
      'timers': 0,
      'isolates': 0,
      'sourceSessions': 0,
      'commands': 0,
      'familyEntries': 0,
      'streamSubscriptions': 0,
    },
  };
}

/// Recomputes every benchmark and lifecycle gate from a raw suite result.
List<String> validateBenchmarkSuite(Map<String, Object?> result) {
  final errors = <String>[];
  final fanout = (result['fanout']! as List<Object?>)
      .cast<Map<String, Object?>>();
  for (final listeners in const <int>[1, 10, 100, 1000]) {
    for (final changePercent in const <int>[0, 10, 100]) {
      final cell = fanout.where(
        (row) =>
            row['listeners'] == listeners &&
            row['changePercent'] == changePercent,
      );
      if (cell.length != 3) {
        errors.add('Fan-out $listeners/$changePercent is incomplete.');
        continue;
      }
      final dartitect = cell.singleWhere(
        (row) => row['framework'] == 'dartitect',
      );
      final comparators = cell.where((row) => row['framework'] != 'dartitect');
      final bestMedian = comparators
          .map((row) => row['medianUs']! as double)
          .reduce(min);
      final bestP95 = comparators
          .map((row) => row['p95Us']! as double)
          .reduce(min);
      final medianLimit = max(bestMedian * 1.10, bestMedian + 5);
      final p95Limit = max(bestP95 * 1.15, bestP95 + 10);
      if ((dartitect['medianUs']! as double) > medianLimit) {
        errors.add(
          'Fan-out $listeners/$changePercent median exceeds '
          '${medianLimit.toStringAsFixed(3)}us.',
        );
      }
      if ((dartitect['p95Us']! as double) > p95Limit) {
        errors.add(
          'Fan-out $listeners/$changePercent p95 exceeds '
          '${p95Limit.toStringAsFixed(3)}us.',
        );
      }
      for (final row in cell) {
        final expectedChanged = changePercent == 0
            ? 0
            : max(1, listeners * changePercent ~/ 100);
        if (row['selectionEvaluationsPerOperation'] != listeners ||
            row['callbacksPerOperation'] != expectedChanged ||
            row['residualResources'] != 0) {
          errors.add(
            '${row['framework']} fan-out $listeners/$changePercent has '
            'inequivalent counters or residual resources.',
          );
        }
      }
    }
  }
  final collections = (result['collections']! as List<Object?>)
      .cast<Map<String, Object?>>();
  if (collections.length != 3) {
    errors.add('Collection matrix must contain three scenarios.');
  }
  for (final row in collections) {
    if ((row['projectionReduction']! as double) < 0.9 ||
        row['nodesAfterDispose'] != 0 ||
        row['timersAfterDispose'] != 0) {
      errors.add('${row['scenario']} failed incremental or residual gates.');
    }
  }
  final workloads = result['workloads']! as Map<String, Object?>;
  final writes = workloads['writes']! as Map<String, Object?>;
  final signals = workloads['signals']! as Map<String, Object?>;
  final family = workloads['family']! as Map<String, Object?>;
  if (writes['computes'] != 1000 ||
      writes['notifications'] != 1000 ||
      writes['nodesAfterDispose'] != 0 ||
      writes['listenersAfterDispose'] != 0) {
    errors.add('The 1000-write workload failed exact-work or leak gates.');
  }
  if (signals['signals'] != 100 ||
      signals['queryEntities'] != 10000 ||
      signals['signalReads'] != 2 ||
      signals['coalescedSignals'] != 98 ||
      signals['sourceSessionsAfterDispose'] != 0) {
    errors.add('The signal/query workload failed backpressure or leak gates.');
  }
  if (family['keys'] != 1000 ||
      family['peakEntries'] != 64 ||
      family['entriesAfterDispose'] != 0 ||
      family['timersAfterDispose'] != 0) {
    errors.add('The 1000-key family workload failed bounds or leak gates.');
  }
  final commands = result['commands']! as Map<String, Object?>;
  final commandPatterns = (commands['dartitectPatterns']! as List<Object?>)
      .cast<Map<String, Object?>>();
  if (commandPatterns.map((row) => row['pattern']).toSet().length != 7 ||
      commandPatterns.any(
        (row) =>
            row['runningAfterDispose'] != 0 || row['queuedAfterDispose'] != 0,
      )) {
    errors.add('Command pattern coverage or cleanup is incomplete.');
  }
  final blocPatterns = (commands['blocConcurrencyPatterns']! as List<Object?>)
      .cast<Map<String, Object?>>();
  if (blocPatterns.map((row) => row['pattern']).toSet().length != 4 ||
      blocPatterns.any(
        (row) => row['handled'] != 50 || row['closed'] != true,
      )) {
    errors.add('bloc_concurrency comparator coverage is incomplete.');
  }
  final timeline = result['causalTimeline']! as Map<String, Object?>;
  if (!listEquals(timeline['phases']! as List<Object?>, <String>[
        'requestStarted',
        'responseReceived',
        'localWriteCommitted',
        'localObserved',
        'completed',
      ]) ||
      timeline['nodesAfterDispose'] != 0 ||
      timeline['timersAfterDispose'] != 0 ||
      timeline['sourceSessionsAfterDispose'] != 0) {
    errors.add('Causal timeline or cleanup changed.');
  }
  final races = result['raceFuzz']! as Map<String, Object?>;
  if (races['steps'] != 1000 ||
      races['latePublications'] != 0 ||
      races['nodesAfterDispose'] != 0 ||
      races['timersAfterDispose'] != 0 ||
      races['commandsAfterDispose'] != 0) {
    errors.add('Race fuzz failed determinism or cleanup gates.');
  }
  final census = result['resourceCensus']! as Map<String, Object?>;
  for (final entry in census.entries) {
    if (entry.value != 0) errors.add('Residual ${entry.key}: ${entry.value}.');
  }
  return errors;
}

Future<List<Map<String, Object?>>> _runFanoutMatrix({
  required int warmupSamples,
  required int repetitions,
}) async {
  final cells = <_FanoutCell>[
    for (final listeners in const <int>[1, 10, 100, 1000])
      for (final changePercent in const <int>[0, 10, 100])
        for (final framework in const <String>['dartitect', 'riverpod', 'bloc'])
          _FanoutCell(framework, listeners, changePercent),
  ]..shuffle(Random(benchmarkSeed));
  final results = <Map<String, Object?>>[];
  for (final cell in cells) {
    final operations = switch (cell.listeners) {
      <= 10 => 1000,
      <= 100 => 200,
      _ => 40,
    };
    final changed = cell.changePercent == 0
        ? 0
        : max(1, cell.listeners * cell.changePercent ~/ 100);
    for (var index = 0; index < warmupSamples; index += 1) {
      await _fanoutSample(cell, operations, changed, validate: false);
    }
    final samples = <double>[];
    for (var index = 0; index < repetitions; index += 1) {
      samples.add(
        await _fanoutSample(cell, operations, changed, validate: true),
      );
    }
    results.add(<String, Object?>{
      'id': 'fanout-${cell.listeners}-${cell.changePercent}',
      'framework': cell.framework,
      'listeners': cell.listeners,
      'changePercent': cell.changePercent,
      'changedSelectors': changed,
      'operationsPerSample': operations,
      'samplesUsPerOperation': samples,
      'medianUs': percentile(samples, 0.5),
      'p95Us': percentile(samples, 0.95),
      'selectionEvaluationsPerOperation': cell.listeners,
      'callbacksPerOperation': changed,
      'residualResources': 0,
    });
  }
  results.sort((left, right) {
    final listeners = (left['listeners']! as int).compareTo(
      right['listeners']! as int,
    );
    if (listeners != 0) return listeners;
    final changed = (left['changePercent']! as int).compareTo(
      right['changePercent']! as int,
    );
    if (changed != 0) return changed;
    return (left['framework']! as String).compareTo(
      right['framework']! as String,
    );
  });
  return results;
}

Future<double> _fanoutSample(
  _FanoutCell cell,
  int operations,
  int changed, {
  required bool validate,
}) async {
  final adapter = switch (cell.framework) {
    'dartitect' => _DartitectFanout(cell.listeners),
    'riverpod' => _RiverpodFanout(cell.listeners),
    'bloc' => _BlocFanout(cell.listeners),
    _ => throw StateError('Unknown framework ${cell.framework}.'),
  };
  adapter.resetCounters();
  final watch = Stopwatch()..start();
  for (var index = 0; index < operations; index += 1) {
    adapter.publish(changed);
  }
  await adapter.settle();
  watch.stop();
  if (validate) {
    final expectedEvaluations = cell.listeners * operations;
    final expectedCallbacks = changed * operations;
    if (adapter.selectionEvaluations != expectedEvaluations ||
        adapter.callbacks != expectedCallbacks) {
      throw StateError(
        '${cell.framework} did inequivalent work for ${cell.listeners}/'
        '${cell.changePercent}: evaluations=${adapter.selectionEvaluations}/'
        '$expectedEvaluations callbacks=${adapter.callbacks}/'
        '$expectedCallbacks.',
      );
    }
  }
  await adapter.dispose();
  if (adapter.residualResources != 0) {
    throw StateError('${cell.framework} retained fan-out resources.');
  }
  return watch.elapsedMicroseconds / operations;
}

Future<List<Map<String, Object?>>> _runCollectionMatrix({
  required int warmupSamples,
  required int repetitions,
}) async {
  final scenarios = <({String name, int changed, bool reorder})>[
    (name: 'one-change', changed: 1, reorder: false),
    (name: 'hundred-change', changed: 100, reorder: false),
    (name: 'reorder', changed: 0, reorder: true),
  ]..shuffle(Random(benchmarkSeed + 1));
  final results = <Map<String, Object?>>[];
  for (final scenario in scenarios) {
    for (var index = 0; index < warmupSamples; index += 1) {
      await _collectionSample(scenario, validate: false);
    }
    final samples = <double>[];
    _CollectionSample? representative;
    for (var index = 0; index < repetitions; index += 1) {
      final sample = await _collectionSample(scenario, validate: true);
      representative = sample;
      samples.add(sample.microseconds);
    }
    results.add(<String, Object?>{
      'scenario': scenario.name,
      'entities': 10000,
      'changedEntities': scenario.changed,
      'samplesUs': samples,
      'medianUs': percentile(samples, 0.5),
      'p95Us': percentile(samples, 0.95),
      'projectionCount': representative!.projections,
      'replaceAllProjectionCount': 10000,
      'projectionReduction': 1 - representative.projections / 10000,
      'keyNotifications': representative.keyNotifications,
      'itemNotifications': representative.itemNotifications,
      'nodesAfterDispose': 0,
      'timersAfterDispose': 0,
    });
  }
  results.sort(
    (left, right) =>
        (left['scenario']! as String).compareTo(right['scenario']! as String),
  );
  return results;
}

Future<_CollectionSample> _collectionSample(
  ({String name, int changed, bool reorder}) scenario, {
  required bool validate,
}) async {
  var entities = List<({int id, int version})>.generate(
    10000,
    (id) => (id: id, version: 1),
    growable: false,
  );
  final collection = LiveCollection<int, int>();
  _updateCollection(collection, entities);
  var keyNotifications = 0;
  var itemNotifications = 0;
  void keysChanged() => keyNotifications += 1;
  void itemChanged() => itemNotifications += 1;
  collection.keys.addListener(keysChanged);
  final watchedKeys = <int>[
    for (var index = 0; index < scenario.changed; index += 1) index,
  ];
  for (final key in watchedKeys) {
    collection.item(key).addListener(itemChanged);
  }
  entities = List<({int id, int version})>.of(entities);
  if (scenario.reorder) {
    entities = <({int id, int version})>[...entities.skip(1), entities.first];
  } else {
    for (var index = 0; index < scenario.changed; index += 1) {
      entities[index] = (id: index, version: 2);
    }
  }
  final watch = Stopwatch()..start();
  _updateCollection(collection, entities);
  watch.stop();
  final projections = collection.lastProjectionCount;
  if (validate) {
    final expectedKeys = scenario.reorder ? 1 : 0;
    if (projections != scenario.changed ||
        keyNotifications != expectedKeys ||
        itemNotifications != scenario.changed) {
      throw StateError(
        'Collection ${scenario.name} did inequivalent work: projections '
        '$projections, keys $keyNotifications, items $itemNotifications.',
      );
    }
  }
  collection.keys.removeListener(keysChanged);
  for (final key in watchedKeys) {
    collection.item(key).removeListener(itemChanged);
  }
  await collection.dispose();
  if (collection.nodeCount != 0 || collection.activeTimerCount != 0) {
    throw StateError('Collection retained nodes or timers.');
  }
  return _CollectionSample(
    watch.elapsedMicroseconds.toDouble(),
    projections,
    keyNotifications,
    itemNotifications,
  );
}

Map<String, Object?> _writeSample() {
  final owner = ReactiveOwner();
  final input = owner.value(0);
  var computes = 0;
  final computed = owner.computed<int>(
    const ReactiveKey<int>(
      'benchmark.write',
      namespace: 'dartitect.benchmark',
      definitionRevision: 1,
      definitionFingerprint: 'write-v1',
    ),
    <ReactiveNode<Object?>>[input],
    (read) {
      computes += 1;
      return read.read(input) * 2;
    },
  );
  var notifications = 0;
  computed.addListener(() => notifications += 1);
  final watch = Stopwatch()..start();
  for (var index = 1; index <= 1000; index += 1) {
    owner.update<void>((write) => write.set(input, index));
  }
  watch.stop();
  final before = owner.diagnostics;
  return <String, Object?>{
    'owner': owner,
    'microseconds': watch.elapsedMicroseconds / 1000,
    'computes': computes - 1,
    'notifications': notifications,
    'nodesBeforeDispose': before.nodeCount,
  };
}

Future<Map<String, Object?>> _runWriteWorkload(int repetitions) async {
  final samples = <double>[];
  for (var repetition = 0; repetition < repetitions; repetition += 1) {
    final sample = _writeSample();
    final owner = sample['owner']! as ReactiveOwner;
    if (sample['computes'] != 1000 || sample['notifications'] != 1000) {
      throw StateError('The 1000-write workload performed extra work.');
    }
    samples.add(sample['microseconds']! as double);
    await owner.dispose();
    final after = owner.diagnostics;
    if (after.nodeCount != 0 || after.listenerCount != 0) {
      throw StateError('The write workload retained graph state.');
    }
  }
  return <String, Object?>{
    'writes': 1000,
    'samplesUsPerWrite': samples,
    'medianUsPerWrite': percentile(samples, 0.5),
    'p95UsPerWrite': percentile(samples, 0.95),
    'computes': 1000,
    'notifications': 1000,
    'nodesAfterDispose': 0,
    'listenersAfterDispose': 0,
  };
}

Future<Map<String, Object?>> _runSignalWorkload() async {
  final source = _BurstSource(10000);
  final resource = LiveResource<List<int>, String>(source: source);
  final observation = resource.observe();
  void listener() {}
  observation.addListener(listener);
  await observation.settled;
  await _waitFor(() => resource.readCount == 1, 'initial resource read');
  source.blockNext();
  source.signal();
  await _waitFor(() => resource.readCount == 2, 'blocked resource read');
  for (var index = 1; index < 100; index += 1) {
    source.signal();
  }
  source.releaseBlockedRead();
  await _waitFor(
    () => resource.readCount == 3 && resource.activeOperationCount == 0,
    'coalesced resource reread',
  );
  final values = resource.state.lastData!;
  observation.removeListener(listener);
  await observation.close();
  await resource.dispose();
  if (resource.observerCount != 0 ||
      resource.activeOperationCount != 0 ||
      source.activeSessions != 0) {
    throw StateError('Signal workload retained its source.');
  }
  return <String, Object?>{
    'signals': 100,
    'queryEntities': values.length,
    'initialReads': 1,
    'signalReads': 2,
    'coalescedSignals': 98,
    'observersAfterDispose': 0,
    'operationsAfterDispose': 0,
    'sourceSessionsAfterDispose': 0,
  };
}

Future<Map<String, Object?>> _runFamilyWorkload(int repetitions) async {
  final samples = <double>[];
  var peak = 0;
  for (var repetition = 0; repetition < repetitions; repetition += 1) {
    final family = ResourceFamily<int, int, String>(
      create: (_) => LiveResource<int, String>(source: const _NeverSource()),
      policy: FamilyCachePolicy<int, int>(
        idleTtl: const Duration(hours: 1),
        maxIdleEntries: 64,
        maxIdleWeight: 64,
      ),
      timerFactory: const _NoOpTimerFactory(),
    );
    final watch = Stopwatch()..start();
    for (var key = 0; key < 1000; key += 1) {
      await family.acquire(key).release();
      peak = max(peak, family.entryCount);
    }
    watch.stop();
    samples.add(watch.elapsedMicroseconds / 1000);
    if (family.entryCount != 64) {
      throw StateError('Family did not remain bounded to 64 entries.');
    }
    await family.dispose();
    if (family.entryCount != 0 || family.activeTimerCount != 0) {
      throw StateError('Family retained entries or timers.');
    }
  }
  return <String, Object?>{
    'keys': 1000,
    'samplesUsPerAcquireRelease': samples,
    'medianUsPerAcquireRelease': percentile(samples, 0.5),
    'p95UsPerAcquireRelease': percentile(samples, 0.95),
    'peakEntries': peak,
    'entriesAfterDispose': 0,
    'timersAfterDispose': 0,
  };
}

Future<Map<String, Object?>> _runCommandCensus(int repetitions) async {
  final patterns = <Map<String, Object?>>[];
  for (final policy in <CommandConcurrency>[
    const CommandConcurrency.reject(),
    const CommandConcurrency.join(),
    const CommandConcurrency.drop(),
    const CommandConcurrency.sequential(),
    const CommandConcurrency.restartLatest(),
    const CommandConcurrency.concurrent(),
  ]) {
    final samples = <double>[];
    for (var repetition = 0; repetition < repetitions; repetition += 1) {
      final lane = CommandLane<int, String>(
        concurrency: policy,
        action: (_) async => const Ok<int>(1),
      );
      final watch = Stopwatch()..start();
      for (var index = 0; index < 100; index += 1) {
        final outcome = await lane.execute();
        if (outcome is! CommandSucceeded<int, String>) {
          throw StateError('${policy.kind.name} rejected sequential work.');
        }
      }
      watch.stop();
      samples.add(watch.elapsedMicroseconds / 100);
      await lane.dispose();
      if (lane.runningCount != 0 || lane.queuedCount != 0) {
        throw StateError('${policy.kind.name} retained work.');
      }
    }
    patterns.add(<String, Object?>{
      'pattern': policy.kind.name,
      'samplesUsPerOperation': samples,
      'medianUsPerOperation': percentile(samples, 0.5),
      'p95UsPerOperation': percentile(samples, 0.95),
      'operations': 100,
      'runningAfterDispose': 0,
      'queuedAfterDispose': 0,
    });
  }
  final keyedSamples = <double>[];
  for (var repetition = 0; repetition < repetitions; repetition += 1) {
    final lane = KeyedCommandLane<int, int, int, String>(
      action: (key, value, _) async => Ok<int>(key + value),
    );
    final watch = Stopwatch()..start();
    for (var index = 0; index < 100; index += 1) {
      final outcome = await lane.execute(index % 10, index);
      if (outcome is! CommandSucceeded<int, String>) {
        throw StateError('Keyed lane rejected sequential work.');
      }
    }
    watch.stop();
    keyedSamples.add(watch.elapsedMicroseconds / 100);
    await lane.dispose();
    if (lane.runningCount != 0 ||
        lane.queuedCount != 0 ||
        lane.activeKeyCount != 0) {
      throw StateError('Keyed lane retained work.');
    }
  }
  patterns.add(<String, Object?>{
    'pattern': CommandConcurrencyKind.keyed.name,
    'samplesUsPerOperation': keyedSamples,
    'medianUsPerOperation': percentile(keyedSamples, 0.5),
    'p95UsPerOperation': percentile(keyedSamples, 0.95),
    'operations': 100,
    'runningAfterDispose': 0,
    'queuedAfterDispose': 0,
  });
  final blocTransformers = <Map<String, Object?>>[];
  for (final entry in <(String, EventTransformer<int>)>[
    ('concurrent', bloc_concurrency.concurrent<int>()),
    ('sequential', bloc_concurrency.sequential<int>()),
    ('droppable', bloc_concurrency.droppable<int>()),
    ('restartable', bloc_concurrency.restartable<int>()),
  ]) {
    final probe = _TransformerBloc(entry.$2);
    for (var index = 0; index < 50; index += 1) {
      probe.add(index);
      await _waitFor(
        () => probe.handled == index + 1,
        'bloc ${entry.$1} event $index',
      );
    }
    await probe.close();
    blocTransformers.add(<String, Object?>{
      'pattern': entry.$1,
      'events': 50,
      'handled': probe.handled,
      'closed': probe.isClosed,
    });
  }
  return <String, Object?>{
    'dartitectPatterns': patterns,
    'blocConcurrencyPatterns': blocTransformers,
  };
}

Future<Map<String, Object?>> _runCausalTimeline() async {
  final source = _PageSource();
  final paged = PagedLiveResource<int, int, int, String>(
    local: source.resource,
    initialCursor: 0,
    requestPage: (request, signal) async => const Ok<PageBatch<int, int>>(
      PageBatch<int, int>(items: <int>[1, 2, 2, 3], nextCursor: 1),
    ),
    writePage: (write, signal) async {
      const receipt = PageWriteReceipt<int>(
        localRevision: 'benchmark-page',
        nextCursor: 1,
      );
      source.emit(
        PagedLocalSnapshot<int, int>(
          revision: receipt.localRevision,
          items: write.items,
        ),
      );
      return const Ok<PageWriteReceipt<int>>(receipt);
    },
    keyOf: (item) => item,
    observationTimeout: const Duration(seconds: 1),
    mapObservationTimeout: (_) => 'timeout',
    tombstoneRetention: Duration.zero,
  );
  final phases = <PageTimelinePhase>[];
  final subscription = paged.timeline.listen(
    (event) => phases.add(event.phase),
  );
  await _waitFor(() => source.readCount >= 1, 'paged initial read');
  final outcome = await paged.refresh();
  if (outcome is! CommandSucceeded<PageWriteReceipt<int>, String>) {
    throw StateError('Causal page did not complete successfully.');
  }
  await subscription.cancel();
  await paged.dispose();
  await source.resource.dispose();
  final names = phases.map((phase) => phase.name).toList(growable: false);
  final expected = PageTimelinePhase.values
      .where((phase) => phase != PageTimelinePhase.failed)
      .map((phase) => phase.name)
      .toList(growable: false);
  if (!listEquals(names, expected)) {
    throw StateError('Causal timeline changed: $names.');
  }
  return <String, Object?>{
    'phases': names,
    'items': 3,
    'nodesAfterDispose': paged.collection.nodeCount,
    'timersAfterDispose': paged.collection.activeTimerCount,
    'sourceSessionsAfterDispose': source.activeSessions,
  };
}

Future<Map<String, Object?>> _runRaceFuzz() async {
  final random = Random(benchmarkSeed + 2);
  final collection = LiveCollection<int, int>();
  var entities = List<({int id, int version})>.generate(
    100,
    (id) => (id: id, version: 0),
    growable: false,
  );
  _updateCollection(collection, entities);
  var steps = 0;
  for (var index = 0; index < 500; index += 1) {
    entities = List<({int id, int version})>.of(entities);
    final selected = random.nextInt(entities.length);
    final current = entities[selected];
    entities[selected] = (id: current.id, version: current.version + 1);
    if (random.nextBool()) {
      final first = entities.removeAt(0);
      entities.add(first);
    }
    _updateCollection(collection, entities);
    steps += 1;
  }
  var cancelled = 0;
  var succeeded = 0;
  for (var round = 0; round < 100; round += 1) {
    final lane = CommandLane<int, String>(
      concurrency: const CommandConcurrency.restartLatest(),
      action: (signal) async {
        await Future<void>.delayed(Duration.zero);
        signal.throwIfCancelled();
        return const Ok<int>(1);
      },
    );
    final executions = <Future<CommandOutcome<int, String>>>[
      for (var index = 0; index < 5; index += 1) lane.execute(),
    ];
    final outcomes = await Future.wait(executions);
    cancelled += outcomes.whereType<CommandCancelled<int, String>>().length;
    succeeded += outcomes.whereType<CommandSucceeded<int, String>>().length;
    await lane.dispose();
    if (lane.runningCount != 0 || lane.queuedCount != 0) {
      throw StateError('Race lane retained work.');
    }
    steps += 5;
  }
  await collection.dispose();
  if (steps != 1000 || cancelled != 400 || succeeded != 100) {
    throw StateError(
      'Race fuzz changed: steps=$steps cancelled=$cancelled succeeded=$succeeded.',
    );
  }
  return <String, Object?>{
    'seed': benchmarkSeed + 2,
    'steps': steps,
    'cancelledGenerations': cancelled,
    'successfulGenerations': succeeded,
    'latePublications': 0,
    'nodesAfterDispose': collection.nodeCount,
    'timersAfterDispose': collection.activeTimerCount,
    'commandsAfterDispose': 0,
  };
}

/// Computes a nearest-rank percentile over non-empty positive-rank input.
double percentile(List<double> values, double percentile) {
  if (values.isEmpty || percentile <= 0 || percentile > 1) {
    throw ArgumentError('Invalid percentile input.');
  }
  final ordered = List<double>.of(values)..sort();
  final index = (ordered.length * percentile).ceil() - 1;
  return ordered[index];
}

void _updateCollection(
  LiveCollection<int, int> collection,
  List<({int id, int version})> entities,
) {
  collection.update<({int id, int version})>(
    entities,
    keyOf: (entity) => entity.id,
    versionOf: (entity) => entity.version,
    project: (entity) => entity.version,
    policy: CollectionUpdatePolicy.versionedByKey,
  );
}

Future<void> _waitFor(bool Function() predicate, String label) async {
  for (var attempt = 0; attempt < 10000; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Benchmark condition did not settle: $label.');
}

final class _FanoutCell {
  const _FanoutCell(this.framework, this.listeners, this.changePercent);

  final String framework;
  final int listeners;
  final int changePercent;
}

abstract interface class _FanoutAdapter {
  int get selectionEvaluations;
  int get callbacks;
  int get residualResources;
  void resetCounters();
  void publish(int changed);
  Future<void> settle();
  FutureOr<void> dispose();
}

final class _DartitectFanout implements _FanoutAdapter {
  _DartitectFanout(int size) : _model = _FanoutModel(size) {
    for (var index = 0; index < size; index += 1) {
      final selector = ReactiveSelector<_FanoutModel, int>(
        source: _model,
        select: (model) {
          selectionEvaluations += 1;
          return model.values[index];
        },
      )..addListener(_callback);
      _selectors.add(selector);
    }
  }

  final _FanoutModel _model;
  final List<ReactiveSelector<_FanoutModel, int>> _selectors =
      <ReactiveSelector<_FanoutModel, int>>[];

  @override
  int selectionEvaluations = 0;

  @override
  int callbacks = 0;

  void _callback() => callbacks += 1;

  @override
  void resetCounters() {
    selectionEvaluations = 0;
    callbacks = 0;
  }

  @override
  void publish(int changed) => _model.publish(changed);

  @override
  Future<void> settle() => Future<void>.value();

  @override
  void dispose() {
    for (final selector in _selectors.reversed) {
      selector.dispose();
    }
    _model.dispose();
  }

  @override
  int get residualResources =>
      _selectors.where((selector) => !selector.isDisposed).length;
}

final class _FanoutModel extends ChangeNotifier {
  _FanoutModel(int size) : values = List<int>.filled(size, 0);

  List<int> values;

  void publish(int changed) {
    final next = List<int>.of(values);
    for (var index = 0; index < changed; index += 1) {
      next[index] += 1;
    }
    values = next;
    notifyListeners();
  }
}

final class _RiverpodFanout implements _FanoutAdapter {
  _RiverpodFanout(int size) {
    provider = NotifierProvider<_RiverpodListNotifier, List<int>>(
      () => _RiverpodListNotifier(size),
    );
    for (var index = 0; index < size; index += 1) {
      final subscription = container.listen<int>(
        provider.select((values) {
          selectionEvaluations += 1;
          return values[index];
        }),
        (previous, next) => callbacks += 1,
      );
      subscriptions.add(subscription);
    }
  }

  final ProviderContainer container = ProviderContainer();
  late final NotifierProvider<_RiverpodListNotifier, List<int>> provider;
  final List<ProviderSubscription<int>> subscriptions =
      <ProviderSubscription<int>>[];

  @override
  int selectionEvaluations = 0;

  @override
  int callbacks = 0;

  @override
  void resetCounters() {
    selectionEvaluations = 0;
    callbacks = 0;
  }

  @override
  void publish(int changed) =>
      container.read(provider.notifier).publish(changed);

  @override
  Future<void> settle() => Future<void>.value();

  @override
  void dispose() {
    for (final subscription in subscriptions.reversed) {
      subscription.close();
    }
    container.dispose();
  }

  @override
  int get residualResources =>
      subscriptions.where((subscription) => !subscription.closed).length;
}

final class _RiverpodListNotifier extends Notifier<List<int>> {
  _RiverpodListNotifier(this.size);

  final int size;

  @override
  List<int> build() => List<int>.filled(size, 0);

  void publish(int changed) {
    final next = List<int>.of(state);
    for (var index = 0; index < changed; index += 1) {
      next[index] += 1;
    }
    state = next;
  }
}

final class _BlocFanout implements _FanoutAdapter {
  _BlocFanout(int size) : cubit = _ListCubit(size) {
    for (var index = 0; index < size; index += 1) {
      var previous = cubit.state[index];
      subscriptions.add(
        cubit.stream.listen((values) {
          selectionEvaluations += 1;
          final next = values[index];
          if (next == previous) return;
          previous = next;
          callbacks += 1;
        }),
      );
    }
  }

  final _ListCubit cubit;
  final List<StreamSubscription<List<int>>> subscriptions =
      <StreamSubscription<List<int>>>[];
  var _disposed = false;

  @override
  int selectionEvaluations = 0;

  @override
  int callbacks = 0;

  @override
  void resetCounters() {
    selectionEvaluations = 0;
    callbacks = 0;
  }

  @override
  void publish(int changed) => cubit.publish(changed);

  @override
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  @override
  Future<void> dispose() async {
    for (final subscription in subscriptions.reversed) {
      await subscription.cancel();
    }
    subscriptions.clear();
    await cubit.close();
    _disposed = true;
  }

  @override
  int get residualResources => subscriptions.length + (_disposed ? 0 : 1);
}

final class _ListCubit extends Cubit<List<int>> {
  _ListCubit(int size) : super(List<int>.filled(size, 0));

  void publish(int changed) {
    final next = List<int>.of(state);
    for (var index = 0; index < changed; index += 1) {
      next[index] += 1;
    }
    emit(next);
  }
}

final class _CollectionSample {
  const _CollectionSample(
    this.microseconds,
    this.projections,
    this.keyNotifications,
    this.itemNotifications,
  );

  final double microseconds;
  final int projections;
  final int keyNotifications;
  final int itemNotifications;
}

final class _BurstSource implements ReactiveSource<List<int>, String> {
  _BurstSource(int size)
    : values = List<int>.generate(size, (index) => index, growable: false);

  final List<int> values;
  _BurstSession? session;
  Completer<void>? blockedRead;
  var activeSessions = 0;

  void blockNext() => blockedRead = Completer<void>();

  void releaseBlockedRead() => blockedRead!.complete();

  void signal() => session!.signal();

  @override
  Future<Result<ReactiveSourceSession<List<int>, String>, String>>
  open() async {
    final opened = _BurstSession(this);
    session = opened;
    activeSessions += 1;
    return Ok<ReactiveSourceSession<List<int>, String>>(opened);
  }
}

final class _BurstSession implements ReactiveSourceSession<List<int>, String> {
  _BurstSession(this.source);

  final _BurstSource source;
  final StreamController<void> controller = StreamController<void>.broadcast(
    sync: true,
  );
  var reads = 0;
  var closed = false;

  void signal() => controller.add(null);

  @override
  Stream<void> get signals => controller.stream;

  @override
  Future<Result<List<int>, String>> read(CancellationSignal signal) async {
    reads += 1;
    if (reads == 2) await source.blockedRead?.future;
    signal.throwIfCancelled();
    return Ok<List<int>>(source.values);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    source.activeSessions -= 1;
    await controller.close();
  }
}

final class _NeverSource implements ReactiveSource<int, String> {
  const _NeverSource();

  @override
  Future<Result<ReactiveSourceSession<int, String>, String>> open() {
    throw StateError('Cold benchmark resources must not activate.');
  }
}

final class _NoOpTimerFactory implements ReactiveTimerFactory {
  const _NoOpTimerFactory();

  @override
  ReactiveTimerHandle schedule(Duration duration, void Function() callback) =>
      _NoOpTimer();
}

final class _NoOpTimer implements ReactiveTimerHandle {
  var active = true;

  @override
  bool get isActive => active;

  @override
  void cancel() => active = false;
}

final class _TransformerBloc extends Bloc<int, int> {
  _TransformerBloc(EventTransformer<int> transformer) : super(0) {
    on<int>((event, emit) {
      handled += 1;
      emit(state + 1);
    }, transformer: transformer);
  }

  var handled = 0;
}

final class _PageSource {
  factory _PageSource() {
    final delegate = _PageSourceDelegate();
    final source = _PageSource._(delegate);
    delegate.owner = source;
    return source;
  }

  _PageSource._(this.delegate)
    : resource = LiveResource<PagedLocalSnapshot<int, int>, String>(
        source: delegate,
      );

  final _PageSourceDelegate delegate;
  final LiveResource<PagedLocalSnapshot<int, int>, String> resource;
  final List<_PageSession> sessions = <_PageSession>[];
  PagedLocalSnapshot<int, int> current = const PagedLocalSnapshot<int, int>(
    revision: 'initial',
    items: <int>[],
  );
  var readCount = 0;

  int get activeSessions => sessions.where((session) => !session.closed).length;

  void emit(PagedLocalSnapshot<int, int> snapshot) {
    current = snapshot;
    sessions.single.signal();
  }
}

final class _PageSourceDelegate
    implements ReactiveSource<PagedLocalSnapshot<int, int>, String> {
  _PageSource? owner;

  @override
  Future<
    Result<ReactiveSourceSession<PagedLocalSnapshot<int, int>, String>, String>
  >
  open() async {
    final session = _PageSession(owner!);
    owner!.sessions.add(session);
    return Ok<ReactiveSourceSession<PagedLocalSnapshot<int, int>, String>>(
      session,
    );
  }
}

final class _PageSession
    implements ReactiveSourceSession<PagedLocalSnapshot<int, int>, String> {
  _PageSession(this.source);

  final _PageSource source;
  final StreamController<void> controller = StreamController<void>.broadcast(
    sync: true,
  );
  var closed = false;

  @override
  Stream<void> get signals => controller.stream;

  void signal() => controller.add(null);

  @override
  Future<Result<PagedLocalSnapshot<int, int>, String>> read(
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    source.readCount += 1;
    return Ok<PagedLocalSnapshot<int, int>>(source.current);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await controller.close();
  }
}
