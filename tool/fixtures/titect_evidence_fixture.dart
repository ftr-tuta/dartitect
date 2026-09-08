import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../titect_evidence.dart';

/// Synthetic evidence for negative readiness/asset tests in disposable roots.
Future<List<Map<String, Object?>>> createTitectEvidenceFixture({
  required Directory root,
  required Directory artifactRoot,
  required String sha,
  required String tree,
  int runId = 123,
  int runAttempt = 1,
}) async {
  Future<File> write(String path, Object? value) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(value));
    return file;
  }

  final sourcePin = jsonDecode(
    File('tool/titect_fixture/pin.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final pin = {...sourcePin, 'integrated': true};
  await write('tool/titect_fixture/pin.json', pin);
  for (final name in [
    'vectors.json',
    'expectations.json',
    'corpus-manifest.json',
  ]) {
    final source = File('tool/titect_fixture/$name');
    final target = File('${root.path}/tool/titect_fixture/$name');
    await target.parent.create(recursive: true);
    if (source.absolute.path != target.absolute.path)
      await source.copy(target.path);
  }
  final vectors = File('${root.path}/tool/titect_fixture/vectors.json');
  final expectations = jsonDecode(
    File('tool/titect_fixture/expectations.json').readAsStringSync(),
  ) as List<Object?>;
  final accepted = expectations
      .where((v) => (v! as Map<String, Object?>)['accepted'] == true)
      .length;
  final evidence = Directory('${artifactRoot.path}/titect');
  await evidence.create(recursive: true);
  final hashes = <String, String>{};
  Future<void> report(String name, Object? value) async {
    final file = File('${evidence.path}/$name');
    await file.writeAsString(jsonEncode(value));
    hashes[name] = sha256.convert(file.readAsBytesSync()).toString();
  }

  for (final target in ['python', 'vm', 'chrome']) {
    await report('$target.json', expectations);
  }
  final reference = {
    'schemaVersion': 1,
    'executionId': 'a' * 32,
    'mode': 'integrated',
    'releaseEligible': false,
    'dartSha': sha,
    'dartTree': tree,
    'pythonSha': pin['pythonSha'],
    'pythonTree': 'b' * 40,
    'sourceVersions': pin['sourceVersions'],
    'bundles': pin['bundles'],
    'executionModes': ['python', 'vm', 'chrome'],
    'corpusSha256': (pin['corpus']! as Map<String, Object?>)['vectors.json'],
    'expectationsSha256':
        (pin['corpus']! as Map<String, Object?>)['expectations.json'],
    'corpusManifestSha256':
        (pin['corpus']! as Map<String, Object?>)['manifest.json'],
  };
  await report('reference.json', reference);
  final identity = {
    'schemaVersion': 1,
    'status': 'passed',
    'preliminary': false,
    'releaseEligible': true,
    'reference': reference,
    'referenceSha256': hashes['reference.json'],
    'nativeActorSha256': 'c' * 64,
    'trackedTreeDirty': false,
    'dartitectSha': sha,
    'sourceTree': tree,
    'runId': runId,
    'runAttempt': runAttempt,
    'pythonSha': pin['pythonSha'],
    'dartitectVersion':
        (pin['sourceVersions']! as Map<String, Object?>)['dartitect'],
    'pytitectVersion':
        (pin['sourceVersions']! as Map<String, Object?>)['pytitect'],
    'pythonMainSha': pin['pythonSha'],
    'bundles': pin['bundles'],
    'pythonVersion': 'fixture',
    'dartVersion': 'fixture',
    'chromeVersion': 'fixture',
    'platform': 'fixture',
  };
  await report('conformance.json', {
    ...identity,
    'vectorsSha256': sha256.convert(vectors.readAsBytesSync()).toString(),
    'vectorCount': expectations.length,
    'unresolvedContracts': <Object?>[],
    'residualResources': {'runnerSubprocesses': 0},
    'pythonOutcomesSha256': hashes['python.json'],
    'targets': {
      for (final target in ['vm', 'chrome'])
        target: {
          'accepted': accepted,
          'rejected': expectations.length - accepted,
          'divergences': <Object?>[],
          'outcomesSha256': hashes['$target.json'],
        },
    },
  });
  final web = {
    'status': 'passed',
    'browserClosed': true,
    'serverClosed': true,
    'profiles': [
      for (final profile in ['portable', 'isolated'])
        {
          'profile': profile,
          'reloads': 2,
          'reopened': true,
          'staleWriterRejected': true,
        },
    ],
  };
  await report('web.json', web);
  await report('recovery.json', {
    ...identity,
    'unverified': <Object?>[],
    'scenarios': [
      for (final name in titectRecoveryScenarios)
        {'name': name, 'passed': true},
    ],
    'residualResources': {
      'childProcesses': 0,
      'postgresConnections': 0,
      'activeAuthorities': 0,
      'runningTasks': 0,
      'queuedTasks': 0,
      'openDatabases': 0,
      'openHttpClients': 0,
    },
    'parameters': {
      'concurrency': 2,
      'queue': 4,
      'maxAttempts': 30,
      'maxPages': 10,
      'maxReceivedBytes': 1048576,
      'maxRetainedRows': 100,
      'maxScopeSeconds': 30,
    },
    'maxima': {
      'running': 2,
      'queued': 4,
      'attempts': 6,
      'admittedBytes': 2048,
      'appliedPages': 2,
      'retainedRows': 9,
      'elapsedMicros': 1000000,
    },
    'serverMaxima': {'active': 2, 'connections': 2},
    'storm': {
      'offered': 30,
      'outcomes': [
        for (var i = 0; i < 30; i++)
          {
            'role': ['refresh', 'reconnect', 'outbox', 'background'][i % 4],
            'disposition': i < 6 ? 'succeeded' : 'refused',
          },
      ],
    },
    'web': web,
    'webSha256': hashes['web.json'],
  });
  final results = <Map<String, Object?>>[];
  for (final name in ['offered', 'saturation', 'recovery']) {
    final offered = name == 'saturation' ? 800 : 100;
    final offers = [
      for (var i = 0; i < offered; i++)
        {
          'index': i,
          'id': 'item-$i',
          'status': '201',
          'state': 'committed',
          'latencyMicros': 1,
          'offeredMicros': i,
          'wireSha256': 'd' * 64,
        },
    ];
    final native = {
      'scenario': name,
      'seed': 41,
      'offered': offered,
      'offerMicros': 2000000,
      'elapsedMicros': 2000001,
      'attempts': offered,
      'receivedBytes': offered * 100,
      'sentBytes': offered * 100,
      'peakRunning': 2,
      'peakQueued': 4,
      'retainedRecords': offered,
      'reconciliations': name == 'recovery' ? 1 : 0,
      'disconnects': name == 'recovery' ? 1 : 0,
      'reconnects': name == 'recovery' ? 1 : 0,
      'outcomes': offers,
    };
    final durable = {
      'receipts': offered,
      'outbox': offered,
      'inbox': offered,
      'publication_retries': 0,
      'pending_outbox': 0,
      'byte_mismatches': 0,
    };
    final peaks = {
      'rss_kib': 1024,
      'tasks': 10,
      'connections': 2,
      'database_lock_waiters': 0,
      'backlog_age_seconds': 0,
    };
    await report('$name.offers.json', offers);
    await report('$name.native.json', native);
    await report('$name.samples.json', [
      {
        ...peaks,
        'elapsed_seconds': 2,
        'background_ok': true,
        'durable': durable,
      },
    ]);
    results.add({
      'scenario': name,
      'seed': 41,
      'passed': true,
      'failures': <Object?>[],
      'offered': offered,
      'statuses': {'201': offered},
      'duration_seconds': 2.000001,
      'useful_operations': offered,
      'useful_throughput': offered / 2.000001,
      'latency_seconds': {
        'p50': .000001,
        'p95': .000001,
        'p99': .000001,
        'max': .000001,
      },
      'peak_observations': peaks,
      'recovery_seconds': 0,
      'durable': durable,
      'load_generator': {
        'workers': 2,
        'queue_capacity': 4,
        'offered_rate': name == 'saturation' ? 400 : 50,
      },
      'client': {...native}..remove('outcomes'),
      'restart_delay_ms': name == 'recovery' ? 200 : 0,
      'residualResources': {
        'activeAuthorities': 0,
        'childProcesses': 0,
        'openDatabases': 0,
        'openHttpClients': 0,
        'postgresConnections': 0,
        'queuedTasks': 0,
        'runningTasks': 0,
      },
      'artifacts': {
        for (final kind in ['offers', 'native', 'samples'])
          '$name.$kind.json': hashes['$name.$kind.json'],
      },
    });
  }
  await report('capacity.json', {
    ...identity,
    'results': results,
    'parameters': {
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
    },
    'residualResources': {
      'activeAuthorities': 0,
      'childProcesses': 0,
      'openDatabases': 0,
      'openHttpClients': 0,
      'postgresConnections': 0,
      'queuedTasks': 0,
      'runningTasks': 0,
    },
  });
  final soak = File('${evidence.path}/python-soak.json');
  await File('tool/titect_fixture/python-soak.json').copy(soak.path);
  hashes['python-soak.json'] = sha256
      .convert(soak.readAsBytesSync())
      .toString();
  for (final name in titectEvidenceFiles.where(
    (name) => name.endsWith('.json'),
  )) {
    final checksumName = name.replaceFirst(RegExp(r'\.json$'), '.sha256');
    final checksum = File('${evidence.path}/$checksumName');
    await checksum.writeAsString('${hashes[name]}  $name\n');
    hashes[checksumName] = sha256
        .convert(checksum.readAsBytesSync())
        .toString();
  }
  return [
    for (final name in titectEvidenceFiles)
      {
        'path': 'titect/$name',
        'kind': 'paired-evidence',
        'sha256': hashes[name],
      },
  ];
}
