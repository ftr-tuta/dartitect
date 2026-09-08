import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

import 'titect_capacity_evidence.dart';

/// Exact paired artifact inventory, retained by readiness and Release.
const titectEvidenceFiles = <String>[
  'conformance.json',
  'recovery.json',
  'web.json',
  'python.json',
  'vm.json',
  'chrome.json',
  'capacity.json',
  'reference.json',
  'python-soak.json',
  'offered.offers.json',
  'offered.native.json',
  'offered.samples.json',
  'saturation.offers.json',
  'saturation.native.json',
  'saturation.samples.json',
  'recovery.offers.json',
  'recovery.native.json',
  'recovery.samples.json',
  'conformance.sha256',
  'recovery.sha256',
  'capacity.sha256',
  'reference.sha256',
  'web.sha256',
  'python.sha256',
  'vm.sha256',
  'chrome.sha256',
  'python-soak.sha256',
  'offered.offers.sha256',
  'offered.native.sha256',
  'offered.samples.sha256',
  'saturation.offers.sha256',
  'saturation.native.sha256',
  'saturation.samples.sha256',
  'recovery.offers.sha256',
  'recovery.native.sha256',
  'recovery.samples.sha256',
];

const titectRecoveryScenarios = <String>{
  'local_before_commit',
  'local_after_commit',
  'remote_before_commit',
  'remote_after_commit',
  'response_received',
  'bootstrap_before_commit',
  'bootstrap_after_commit',
  'page_during_apply',
  'page_before_commit',
  'page_after_commit',
  'checkpoint_before_commit',
  'checkpoint_after_commit',
  'fencing/page_before_apply/acquire',
  'fencing/checkpoint_before_commit/acquire',
  'fencing/checkpoint_before_commit/expire',
  'storage-failure-rollback',
  'paired-storm',
  'persistent-chrome-recovery',
  'pending-shadow-retention-and-expired-cursor',
  'django-persistent-mutations',
  'corrupted-page-rejection',
  'negotiated-policy-mismatch',
  'exact-number-persistence',
  'integrity-failure-state-and-checkpoint-unchanged',
};

/// Fails closed before readiness creation, validation and asset build.
/// Callers check hosted execution authority; this checks reports against that
/// exact execution and committed source.
void validateTitectEvidence({
  required Directory root,
  required Directory evidence,
  required String sourceSha,
  required String sourceTree,
  required int runId,
  required int runAttempt,
}) {
  final pin = _read(File('${root.path}/tool/titect_fixture/pin.json'));
  _require(pin['integrated'] == true, 'Python pin is preliminary');
  _require(runId > 0 && runAttempt > 0, 'hosted CI run identity is missing');
  for (final name in titectEvidenceFiles) {
    _require(File('${evidence.path}/$name').existsSync(), 'missing $name');
  }
  final conformance = _read(File('${evidence.path}/conformance.json'));
  final recovery = _read(File('${evidence.path}/recovery.json'));
  final capacity = _read(File('${evidence.path}/capacity.json'));
  final referenceFile = File('${evidence.path}/reference.json');
  final reference = _read(referenceFile);
  _require(
    reference['schemaVersion'] == 1 &&
        reference['mode'] == 'integrated' &&
        reference['releaseEligible'] == false &&
        reference['dartSha'] == sourceSha &&
        reference['dartTree'] == sourceTree &&
        reference['pythonSha'] == pin['pythonSha'] &&
        RegExp(r'^[0-9a-f]{40}$')
            .hasMatch(reference['pythonTree'] as String? ?? '') &&
        RegExp(r'^[0-9a-f]{32}$')
            .hasMatch(reference['executionId'] as String? ?? '') &&
        const DeepCollectionEquality().equals(
          reference['sourceVersions'],
          pin['sourceVersions'],
        ) &&
        const DeepCollectionEquality().equals(
          reference['bundles'],
          pin['bundles'],
        ) &&
        const DeepCollectionEquality().equals(reference['executionModes'], [
          'python',
          'vm',
          'chrome',
        ]),
    'reference is candidate, substituted or incomplete',
  );
  for (final name in titectEvidenceFiles.where(
    (name) => name.endsWith('.json'),
  )) {
    final file = File('${evidence.path}/$name');
    _require(
      File('${evidence.path}/${name.replaceFirst(RegExp(r'\.json$'), '.sha256')}')
              .readAsStringSync() ==
          '${_digest(file)}  $name\n',
      'evidence checksum differs for $name',
    );
  }
  for (final report in [conformance, recovery, capacity]) {
    _require(
      report['schemaVersion'] == 1 &&
          report['status'] == 'passed' &&
          report['preliminary'] == false &&
          report['releaseEligible'] == true &&
          report['referenceSha256'] == _digest(referenceFile) &&
          const DeepCollectionEquality().equals(
            report['reference'],
            reference,
          ) &&
          report['trackedTreeDirty'] == false &&
          report['dartitectSha'] == sourceSha &&
          report['sourceTree'] == sourceTree &&
          report['runId'] == runId &&
          report['runAttempt'] == runAttempt &&
          report['pythonSha'] == pin['pythonSha'] &&
          report['dartitectVersion'] ==
              _object(pin['sourceVersions'])['dartitect'] &&
          report['pytitectVersion'] ==
              _object(pin['sourceVersions'])['pytitect'] &&
          RegExp(r'^[0-9a-f]{40}$').hasMatch(
            report['pythonMainSha'] is String
                ? report['pythonMainSha']! as String
                : '',
          ) &&
          const DeepCollectionEquality().equals(
            report['bundles'],
            pin['bundles'],
          ),
      'report is preliminary, failed, dirty, or from another source/run',
    );
    for (final key in [
      'pythonVersion',
      if (!identical(report, capacity)) 'dartVersion',
      if (!identical(report, capacity)) 'chromeVersion',
      'platform',
    ]) {
      _require(
        report[key] is String && (report[key]! as String).isNotEmpty,
        'missing runtime version or platform',
      );
    }
  }
  final vectorsFile = File('${root.path}/tool/titect_fixture/vectors.json');
  final vectors = jsonDecode(vectorsFile.readAsStringSync()) as List<Object?>;
  final expectationsFile = File(
    '${root.path}/tool/titect_fixture/expectations.json',
  );
  final expectations =
      jsonDecode(expectationsFile.readAsStringSync()) as List<Object?>;
  final corpus = _object(pin['corpus']);
  _require(
    vectors.length == 232 &&
        expectations.length == 232 &&
        _digest(vectorsFile) == corpus['vectors.json'] &&
        _digest(expectationsFile) == corpus['expectations.json'] &&
        _digest(
              File('${root.path}/tool/titect_fixture/corpus-manifest.json'),
            ) ==
            corpus['manifest.json'] &&
        reference['corpusSha256'] == corpus['vectors.json'] &&
        reference['expectationsSha256'] == corpus['expectations.json'] &&
        reference['corpusManifestSha256'] == corpus['manifest.json'],
    'official corpus or expectation identity differs',
  );
  for (final target in ['python', 'vm', 'chrome']) {
    _require(
      const DeepCollectionEquality().equals(
        jsonDecode(File('${evidence.path}/$target.json').readAsStringSync()),
        expectations,
      ),
      '$target differs from exact official bytes or errors',
    );
  }
  _require(
    conformance['vectorsSha256'] == _digest(vectorsFile) &&
        conformance['vectorCount'] == vectors.length &&
        const DeepCollectionEquality().equals(
          conformance['unresolvedContracts'],
          [],
        ),
    'vectors differ or contracts remain unresolved',
  );
  _zero(conformance['residualResources'], {'runnerSubprocesses'});
  final targets = _object(conformance['targets']);
  _require(
    const SetEquality<String>().equals(targets.keys.toSet(), {'vm', 'chrome'}),
    'both Dart targets are required',
  );
  _require(
    conformance['pythonOutcomesSha256'] ==
        _digest(File('${evidence.path}/python.json')),
    'Python outcomes altered',
  );
  for (final target in ['vm', 'chrome']) {
    final result = _object(targets[target]);
    final accepted = result['accepted'];
    final rejected = result['rejected'];
    _require(
      accepted is int &&
          rejected is int &&
          accepted > 0 &&
          rejected > 0 &&
          accepted + rejected == vectors.length &&
          const DeepCollectionEquality().equals(result['divergences'], []) &&
          result['outcomesSha256'] ==
              _digest(File('${evidence.path}/$target.json')),
      '$target has missing, altered, or divergent outcomes',
    );
  }
  final scenarios = _objects(recovery['scenarios']);
  _require(
    scenarios.length == titectRecoveryScenarios.length &&
        scenarios.every((row) => row['passed'] == true) &&
        const SetEquality<Object?>().equals(
          scenarios.map((row) => row['name']).toSet(),
          titectRecoveryScenarios,
        ),
    'recovery scenarios are missing, duplicated, or failed',
  );
  _require(
    const DeepCollectionEquality().equals(recovery['unverified'], []),
    'recovery contains unverified requirements',
  );
  _require(
    RegExp(r'^[0-9a-f]{64}$')
            .hasMatch(recovery['nativeActorSha256'] as String? ?? '') &&
        recovery['nativeActorSha256'] == capacity['nativeActorSha256'],
    'native actor identity differs',
  );
  validateTitectCapacity(capacity, evidence);
  final soakFile = File('${evidence.path}/python-soak.json');
  final soak = _read(soakFile);
  final soakPin = _object(pin['soakEvidence']);
  _require(
    _digest(soakFile) == soakPin['sha256'] &&
        soak['commit'] == soakPin['pythonSha'] &&
        _object(soak['parameters'])['duration'] == 1800 &&
        _objects(soak['results']).single['passed'] == true,
    'separate historical Python soak is missing, altered or relabelled',
  );
  _zero(recovery['residualResources'], {
    'childProcesses',
    'postgresConnections',
    'activeAuthorities',
    'runningTasks',
    'queuedTasks',
    'openDatabases',
    'openHttpClients',
  });
  _require(
    const DeepCollectionEquality().equals(recovery['parameters'], {
      'concurrency': 2,
      'queue': 4,
      'maxAttempts': 30,
      'maxPages': 10,
      'maxReceivedBytes': 1048576,
      'maxRetainedRows': 100,
      'maxScopeSeconds': 30,
    }),
    'recovery bounds differ from the control',
  );
  final maxima = _object(recovery['maxima']);
  for (final entry in {
    'running': 2,
    'queued': 4,
    'attempts': 30,
    'admittedBytes': 1048576,
    'appliedPages': 10,
    'retainedRows': 100,
    'elapsedMicros': 30000000,
  }.entries) {
    final observed = maxima[entry.key];
    _require(
      observed is int && observed > 0 && observed <= entry.value,
      'admission maximum ${entry.key} is absent or exceeds its bound',
    );
  }
  final serverMaxima = _object(recovery['serverMaxima']);
  for (final key in ['active', 'connections']) {
    final observed = serverMaxima[key];
    _require(
      observed is int && observed > 0 && observed <= 2,
      'server admission maximum $key is absent or exceeds its bound',
    );
  }
  final storm = _object(recovery['storm']);
  final outcomes = _objects(storm['outcomes']);
  _require(
    storm['offered'] == 30 &&
        outcomes.length == 30 &&
        outcomes.any((row) => row['disposition'] == 'refused') &&
        const SetEquality<Object?>().equals(
          outcomes.map((row) => row['role']).toSet(),
          {'refresh', 'reconnect', 'outbox', 'background'},
        ),
    'storm accounting is incomplete',
  );
  final webFile = File('${evidence.path}/web.json');
  final web = _read(webFile);
  _require(
    recovery['webSha256'] == _digest(webFile) &&
        const DeepCollectionEquality().equals(recovery['web'], web) &&
        web['status'] == 'passed' &&
        web['browserClosed'] == true &&
        web['serverClosed'] == true,
    'web evidence is altered or incomplete',
  );
  final profiles = _objects(web['profiles']);
  _require(
    profiles.length == 2 &&
        const SetEquality<Object?>().equals(
          profiles.map((row) => row['profile']).toSet(),
          {'portable', 'isolated'},
        ) &&
        profiles.every(
          (row) =>
              row['reloads'] == 2 &&
              row['reopened'] == true &&
              row['staleWriterRejected'] == true,
        ),
    'persistent Chrome recovery profiles are incomplete',
  );
}

void _zero(Object? value, Set<String> keys) {
  final counts = _object(value);
  _require(
    const SetEquality<String>().equals(counts.keys.toSet(), keys) &&
        counts.values.every((value) => value == 0),
    'owned resources remain or lack evidence',
  );
}

String _digest(File file) => sha256.convert(file.readAsBytesSync()).toString();
Map<String, Object?> _read(File file) =>
    _object(jsonDecode(file.readAsStringSync()));
Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>)
    throw StateError('Titect evidence: expected object');
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?>)
    throw StateError('Titect evidence: expected list');
  return value.map(_object).toList();
}

void _require(bool condition, String reason) {
  if (!condition) throw StateError('Titect evidence rejected: $reason.');
}
