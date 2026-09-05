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
  final vectors = await write('tool/titect_fixture/vectors.json', [
    <String, Object?>{},
    <String, Object?>{},
  ]);
  final evidence = Directory('${artifactRoot.path}/titect');
  await evidence.create(recursive: true);
  final hashes = <String, String>{};
  Future<void> report(String name, Object? value) async {
    final file = File('${evidence.path}/$name');
    await file.writeAsString(jsonEncode(value));
    hashes[name] = sha256.convert(file.readAsBytesSync()).toString();
  }

  for (final target in ['python', 'vm', 'chrome']) {
    await report('$target.json', [
      {'name': 'positive', 'accepted': true},
      {'name': 'negative', 'accepted': false},
    ]);
  }
  final identity = {
    'schemaVersion': 1,
    'status': 'passed',
    'preliminary': false,
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
    'vectorCount': 2,
    'unresolvedContracts': <Object?>[],
    'residualResources': {'runnerSubprocesses': 0},
    'pythonOutcomesSha256': hashes['python.json'],
    'targets': {
      for (final target in ['vm', 'chrome'])
        target: {
          'accepted': 1,
          'rejected': 1,
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
  return [
    for (final name in titectEvidenceFiles)
      {
        'path': 'titect/$name',
        'kind': 'paired-evidence',
        'sha256': hashes[name],
      },
  ];
}
