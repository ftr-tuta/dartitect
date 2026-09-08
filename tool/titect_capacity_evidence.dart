import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

/// Validates complete real-client measurements, including rejected offers.
void validateTitectCapacity(Map<String, Object?> report, Directory evidence) {
  void require(bool condition, String message) {
    if (!condition)
      throw StateError('Titect capacity evidence rejected: $message.');
  }

  Map<String, Object?> object(Object? value) => value! as Map<String, Object?>;
  List<Map<String, Object?>> objects(Object? value) =>
      (value! as List<Object?>).map(object).toList();
  bool equal(Object? a, Object? b) =>
      const DeepCollectionEquality().equals(a, b);
  double number(Object? value) {
    require(
      value is num && value.isFinite && value >= 0,
      'invalid finite measurement',
    );
    return (value! as num).toDouble();
  }

  int count(Object? value) {
    require(value is int && value >= 0, 'invalid resource or operation count');
    return value! as int;
  }

  Object? read(String name, Map<String, Object?> hashes) {
    final bytes = File('${evidence.path}/$name').readAsBytesSync();
    require(
      sha256.convert(bytes).toString() == hashes[name],
      'altered raw $name',
    );
    return jsonDecode(utf8.decode(bytes));
  }

  const resources = {
    'activeAuthorities',
    'childProcesses',
    'openDatabases',
    'openHttpClients',
    'postgresConnections',
    'queuedTasks',
    'runningTasks',
  };
  void zero(Object? value) {
    final counts = object(value);
    require(
      const SetEquality<String>().equals(counts.keys.toSet(), resources) &&
          counts.values.every((v) => v is int && v == 0),
      'missing or residual owned resources',
    );
  }

  zero(report['residualResources']);
  require(
    equal(report['parameters'], {
      'seed': 41,
      'offerSeconds': 2,
      'rates': [50, 400, 50],
      'offers': [100, 800, 100],
      'concurrency': 2,
      'queue': 4,
      'maxAttempts': 2400,
      'maxReceivedBytes': 8388608,
      'maxSentBytes': 8388608,
      'maxRetainedRecords': 800,
      'maxScopeSeconds': 22,
      'maxDrainSeconds': 20,
      'restartDelayMs': 200,
      'maxServerRssMiB': 512,
      'maxServerTasks': 100,
      'maxServerConnections': 8,
    }),
    'finite capacity controls differ',
  );
  final results = objects(report['results']);
  require(
    equal(results.map((row) => row['scenario']).toList(), [
      'offered',
      'saturation',
      'recovery',
    ]),
    'scenario inventory differs',
  );
  for (final row in results) {
    final name = row['scenario']! as String;
    final offered = name == 'saturation' ? 800 : 100;
    final rate = name == 'saturation' ? 400 : 50;
    require(
      row['passed'] == true &&
          equal(row['failures'], []) &&
          row['seed'] == 41 &&
          row['offered'] == offered,
      'scenario failed or changed',
    );
    zero(row['residualResources']);
    final hashes = object(row['artifacts']);
    final offers = objects(read('$name.offers.json', hashes));
    final native = object(read('$name.native.json', hashes));
    final samples = objects(read('$name.samples.json', hashes));
    require(
      offers.length == offered &&
          samples.isNotEmpty &&
          samples.length <= 440 &&
          equal(native['outcomes'], offers) &&
          equal({...native}..remove('outcomes'), row['client']),
      'raw measurements are incomplete or substituted',
    );
    final indices = offers.map((o) => o['index']).toSet();
    require(
      indices.length == offered &&
          indices.containsAll(List.generate(offered, (i) => i)) &&
          offers.map((o) => o['id']).toSet().length == offered,
      'offered identities differ',
    );
    final statuses = <String, int>{};
    for (final offer in offers) {
      final status = offer['status']! as String;
      statuses.update(status, (count) => count + 1, ifAbsent: () => 1);
      require(
        const {
          'committed',
          'refused',
          'not_committed',
        }.contains(offer['state']),
        'unreconciled or failed request',
      );
      number(offer['offeredMicros']);
      number(offer['latencyMicros']);
    }
    require(
      equal(statuses, row['statuses']),
      'statuses omit rejected or failed offers',
    );
    require(
      equal(row['load_generator'], {
        'workers': 2,
        'queue_capacity': 4,
        'offered_rate': rate,
      }),
      'client admission controls changed',
    );
    require(
      native['scenario'] == name &&
          native['seed'] == 41 &&
          native['offered'] == offered &&
          count(native['peakRunning']) > 0 &&
          count(native['peakRunning']) <= 2 &&
          count(native['peakQueued']) <= 4 &&
          count(native['attempts']) > 0 &&
          count(native['attempts']) <= 2400 &&
          count(native['receivedBytes']) <= 8388608 &&
          count(native['sentBytes']) <= 8388608 &&
          count(native['retainedRecords']) <= 800 &&
          count(native['offerMicros']) >= 2000000 &&
          count(native['elapsedMicros']) >= count(native['offerMicros']) &&
          count(native['elapsedMicros']) <= 22000000,
      'client attempt, queue, retention, byte or time budget exceeded',
    );
    if (name == 'recovery') {
      require(
        count(native['disconnects']) > 0 &&
            count(native['reconnects']) > 0 &&
            count(native['reconciliations']) > 0 &&
            number(row['restart_delay_ms']) >= 200,
        'missing server restart or client reconnect/reconciliation',
      );
    }
    final latency =
        offers.map((o) => count(o['latencyMicros']) / 1000000).toList()..sort();
    final observedLatency = object(row['latency_seconds']);
    for (final entry in {
      'p50': .5,
      'p95': .95,
      'p99': .99,
      'max': 1.0,
    }.entries) {
      require(
        number(observedLatency[entry.key]) ==
            latency[((latency.length - 1) * entry.value).floor()],
        'latency omits offers or differs from raw results',
      );
    }
    final peaks = object(row['peak_observations']);
    for (final key in [
      'rss_kib',
      'tasks',
      'connections',
      'database_lock_waiters',
      'backlog_age_seconds',
    ]) {
      final maximum = samples.map((s) => number(s[key])).reduce(max);
      require(
        number(peaks[key]) == maximum,
        'resource maxima differ from samples',
      );
    }
    require(
      number(peaks['rss_kib']) > 0 &&
          number(peaks['rss_kib']) <= 512 * 1024 &&
          count(peaks['tasks']) <= 100 &&
          count(peaks['connections']) <= 8 &&
          samples.every((s) => s['background_ok'] == true),
      'Python process resource budget exceeded or background failed',
    );
    final durable = object(row['durable']);
    require(
      durable.values.every((v) => v is int && v >= 0) &&
          durable['pending_outbox'] == 0 &&
          durable['byte_mismatches'] == 0 &&
          durable['receipts'] == durable['outbox'] &&
          durable['outbox'] == durable['inbox'] &&
          count(durable['inbox']) > 0 &&
          durable['inbox'] ==
              offers.where((o) => o['state'] == 'committed').length &&
          row['useful_operations'] == durable['inbox'] &&
          equal(samples.last['durable'], durable),
      'durable receipts/outbox/inbox do not reconcile',
    );
    final duration = number(row['duration_seconds']);
    final recovery = number(row['recovery_seconds']);
    require(
      duration == count(native['elapsedMicros']) / 1000000 &&
          duration > 0 &&
          recovery <= 20 &&
          duration + recovery <= 22 &&
          (number(row['useful_throughput']) -
                      count(durable['inbox']) / (duration + recovery))
                  .abs() <
              1e-9,
      'throughput or finite recovery interval differs',
    );
  }
}
