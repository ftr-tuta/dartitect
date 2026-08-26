import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final contract = _object(
    jsonDecode(
      File('${root.path}/tool/runtime_hardening_contract.json')
          .readAsStringSync(),
    ),
  );
  final errors = <String>[];
  if (contract['schemaVersion'] != 1 || contract['goal'] != 'V1S-12') {
    errors.add('Unsupported runtime hardening contract.');
  }

  _validateCommandRace(root, contract['commandRace'], errors);
  await _validatePersistedCompatibility(
    root,
    contract['persistedCompatibility'],
    errors,
  );

  final evidence = _objects(contract['runtimeEvidence'], errors);
  final names = <String>{};
  for (final suite in evidence) {
    final name = suite['name'];
    final files = _strings(suite['files'], errors);
    final markers = _strings(suite['requiredMarkers'], errors);
    if (name is! String || name.isEmpty || !names.add(name)) {
      errors.add('Invalid or duplicate runtime evidence suite: $name.');
      continue;
    }
    _requireMarkers(root, files, markers, errors, label: name);
  }
  if (!names.containsAll(const <String>{
    'command-lanes',
    'reactive-runtime',
    'offline-first',
    'objectbox-restart',
    'isolate-supervision',
  })) {
    errors.add('Runtime hardening evidence matrix is incomplete.');
  }

  _validateZeroResidual(root, contract['zeroResidual'], errors);
  if (contract['isolateProtocolVersion'] != 1 ||
      contract['nativeGate'] !=
          'dart run tool/verify.dart --skip-get --native-objectbox') {
    errors.add('Runtime protocol or native gate changed unexpectedly.');
  }
  final isolateSource = _source(
    root,
    'packages/dartitect_isolates/lib/src/isolate_worker.dart',
    errors,
  );
  if (!isolateSource.contains(
    'const int currentIsolateWorkerProtocolVersion = 1;',
  )) {
    errors.add('Isolate worker protocol does not match the contract.');
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Runtime hardening contract passed deterministic races, persisted v1 '
    'compatibility, ${evidence.length} runtime suites, native restart, and '
    'zero-residual evidence.',
  );
}

void _validateCommandRace(Directory root, Object? value, List<String> errors) {
  final race = _map(value, errors);
  final file = race['file'];
  final seed = race['seed'];
  final iterations = race['iterations'];
  final policies = _strings(race['policies'], errors);
  if (file is! String ||
      seed != 12001 ||
      iterations is! int ||
      iterations < 200 ||
      policies.toSet().length != 6 ||
      !policies.toSet().containsAll(const <String>{
        'reject',
        'join',
        'drop',
        'sequential',
        'restartLatest',
        'concurrent',
      })) {
    errors.add('Deterministic command race matrix is incomplete.');
    return;
  }
  final source = _source(root, file, errors);
  if (!source.contains('const _seed = $seed;') ||
      !source.contains('const _iterations = $iterations;')) {
    errors.add('Command race seed/iteration constants changed.');
  }
  for (final policy in policies) {
    if (!source.contains('CommandConcurrency.$policy(')) {
      errors.add('Command race does not exercise $policy.');
    }
  }
}

Future<void> _validatePersistedCompatibility(
  Directory root,
  Object? value,
  List<String> errors,
) async {
  final compatibility = _map(value, errors);
  final fixturePath = compatibility['fixture'];
  final expectedDigest = compatibility['fixtureSha256'];
  final evidencePath = compatibility['evidenceFile'];
  if (fixturePath is! String ||
      expectedDigest is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedDigest) ||
      evidencePath is! String) {
    errors.add('Persisted compatibility paths or digest are invalid.');
    return;
  }
  final fixture = File('${root.path}/$fixturePath');
  if (!fixture.existsSync()) {
    errors.add('Persisted compatibility fixture is missing.');
  } else {
    final actualDigest = (await sha256.bind(fixture.openRead()).first)
        .toString();
    if (actualDigest != expectedDigest) {
      errors.add('Persisted compatibility fixture digest changed.');
    }
    try {
      final decoded = _object(jsonDecode(await fixture.readAsString()));
      if (decoded['schemaVersion'] != 1) {
        errors.add('Persisted fixture schema is not v1.');
      }
    } on FormatException catch (error) {
      errors.add('Persisted fixture is invalid JSON: $error.');
    }
  }

  if (!_exactIntegers(compatibility['acceptedSchemas'], const <int>[1]) ||
      !_exactIntegers(compatibility['rejectedSchemas'], const <int>[0, 2]) ||
      compatibility['enumEncoding'] != 'name' ||
      !_exactStrings(compatibility['entitySyncStates'], const <String>[
        'synced',
        'pending',
        'syncing',
        'rejected',
        'conflicted',
        'uncertain',
      ]) ||
      !_exactStrings(compatibility['journalFacts'], const <String>[
        'attemptStarted',
        'datasetStarted',
        'datasetSucceeded',
        'datasetFailed',
        'datasetSkipped',
        'attemptCompleted',
        'attemptCrashed',
      ])) {
    errors.add('Persisted semantic compatibility matrix changed.');
  }
  final source = _source(root, evidencePath, errors);
  for (final marker in const <String>[
    'operation.syncState.name',
    'entry.fact.name',
    '_enumByName',
    'throwsFormatException',
    'futureField',
  ]) {
    if (!source.contains(marker)) {
      errors.add('Persisted compatibility test is missing $marker.');
    }
  }
}

void _validateZeroResidual(Directory root, Object? value, List<String> errors) {
  final residual = _map(value, errors);
  final kinds = _strings(residual['resourceKinds'], errors);
  if (!_exactStrings(kinds, const <String>[
    'listeners',
    'timers',
    'subscriptions',
    'queries',
    'lanes',
    'isolates',
    'stores',
  ])) {
    errors.add('Zero-residual resource census is incomplete.');
  }
  _requireMarkers(
    root,
    _strings(residual['evidenceFiles'], errors),
    _strings(residual['requiredMarkers'], errors),
    errors,
    label: 'zero-residual',
  );
}

void _requireMarkers(
  Directory root,
  List<String> paths,
  List<String> markers,
  List<String> errors, {
  required String label,
}) {
  if (paths.isEmpty || markers.isEmpty) {
    errors.add('$label evidence paths or markers are empty.');
    return;
  }
  final combined = StringBuffer();
  for (final path in paths) {
    combined.write(_source(root, path, errors));
  }
  final source = combined.toString().toLowerCase();
  for (final marker in markers) {
    if (!source.contains(marker.toLowerCase())) {
      errors.add('$label evidence is missing coverage marker: $marker.');
    }
  }
}

bool _exactIntegers(Object? actual, List<int> expected) =>
    actual is List<Object?> &&
    actual.length == expected.length &&
    actual.every((value) => value is int) &&
    actual.cast<int>().toSet().containsAll(expected);

bool _exactStrings(Object? actual, List<String> expected) =>
    actual is List<Object?> &&
    actual.length == expected.length &&
    actual.every((value) => value is String) &&
    actual.cast<String>().toSet().containsAll(expected);

String _source(Directory root, String path, List<String> errors) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    errors.add('Evidence file is missing: $path.');
    return '';
  }
  return file.readAsStringSync();
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

Map<String, Object?> _map(Object? value, List<String> errors) {
  if (value is! Map<String, Object?>) {
    errors.add('Expected a JSON object field.');
    return <String, Object?>{};
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value, List<String> errors) {
  if (value is! List<Object?> ||
      value.any((item) => item is! Map<String, Object?>)) {
    errors.add('Expected a JSON object list.');
    return <Map<String, Object?>>[];
  }
  return value.cast<Map<String, Object?>>();
}

List<String> _strings(Object? value, List<String> errors) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    errors.add('Expected a JSON string list.');
    return <String>[];
  }
  return value.cast<String>();
}
