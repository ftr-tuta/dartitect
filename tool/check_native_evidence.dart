import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  try {
    await _main(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  }
}

Future<void> _main(List<String> arguments) async {
  final rootArgument = _singleArgument(arguments, '--root=');
  final root = rootArgument == null
      ? File.fromUri(Platform.script).parent.parent.absolute
      : Directory(rootArgument).absolute;
  final errors = <String>[];
  final contractOnly = arguments.contains('--contract-only');
  final unknown = arguments.where(
    (argument) =>
        argument != '--contract-only' &&
        !argument.startsWith('--root=') &&
        !argument.startsWith('--source-sha=') &&
        !argument.startsWith('--source-tree=') &&
        !argument.startsWith('--receipt='),
  );
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown arguments: ${unknown.join(', ')}');
  }

  final contractFile = File('${root.path}/tool/native_evidence_contract.json');
  if (!contractFile.existsSync()) {
    _finish(<String>['Native evidence contract is missing.'], '');
    return;
  }
  final contract = _object(jsonDecode(contractFile.readAsStringSync()));
  final cells = _validateContract(root, contract, errors);
  if (contractOnly) {
    _finish(
      errors,
      'Native evidence v2 contract passed exactly ${cells.length} '
      'fail-closed build/simulator/physical cells; receipts were not '
      'evaluated.',
    );
    return;
  }

  final sourceSha =
      _singleArgument(arguments, '--source-sha=') ??
      (await _git(root, const <String>['rev-parse', 'HEAD'])).trim();
  if (!_shaPattern.hasMatch(sourceSha)) {
    errors.add('Native evidence source SHA is invalid.');
  }
  final expectedTree = _shaPattern.hasMatch(sourceSha)
      ? (await _git(root, <String>[
          'show',
          '-s',
          '--format=%T',
          sourceSha,
        ])).trim()
      : '';
  final requestedTree = _singleArgument(arguments, '--source-tree=');
  if (requestedTree != null && requestedTree != expectedTree) {
    errors.add('Native evidence source tree does not match the source SHA.');
  }

  final receiptFiles = await _receiptFiles(root, contract, arguments, errors);
  final receiptsByCell = <String, Map<String, Object?>>{};
  for (final file in receiptFiles) {
    try {
      final receipt = _object(jsonDecode(await file.readAsString()));
      final id = receipt['cellId'];
      if (id is! String || !cells.containsKey(id)) {
        errors.add('${_relative(root, file)} names an unknown native cell.');
        continue;
      }
      if (receiptsByCell.containsKey(id)) {
        errors.add('Duplicate native receipt for $id.');
        continue;
      }
      _validateReceipt(
        receipt,
        cells[id]!,
        contract,
        sourceSha,
        expectedTree,
        errors,
      );
      receiptsByCell[id] = receipt;
      stdout.writeln(
        '$id receipt sha256 '
        '${(await sha256.bind(file.openRead()).first).toString()}',
      );
    } on FormatException catch (error) {
      errors.add('${_relative(root, file)} is invalid: $error.');
    }
  }
  for (final id in cells.keys) {
    if (!receiptsByCell.containsKey(id)) {
      errors.add('Missing native evidence receipt for $id at $sourceSha.');
    }
  }
  if (receiptFiles.length != cells.length) {
    errors.add(
      'Native receipt set is not exact: expected ${cells.length}, '
      'found ${receiptFiles.length}.',
    );
  }

  final dirty = await _git(root, const <String>[
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  if (dirty.trim().isNotEmpty) {
    errors.add('Source tree is dirty while validating native receipts.');
  }
  _finish(
    errors,
    'Native evidence passed all five build/simulator/physical cells at '
    '$sourceSha with source tree $expectedTree.',
  );
}

Map<String, Map<String, Object?>> _validateContract(
  Directory root,
  Map<String, Object?> contract,
  List<String> errors,
) {
  if (contract['schemaVersion'] != 2 ||
      contract['receiptSchemaVersion'] != 2 ||
      contract['goal'] != 'V1S-13') {
    errors.add('Unsupported native evidence contract.');
  }
  final harness = contract['harness'];
  if (harness is! String ||
      !File('${root.path}/$harness/lib/main.dart').existsSync() ||
      !File('${root.path}/$harness/integration_test/android_media_test.dart')
          .existsSync() ||
      !File('${root.path}/$harness/lib/ios_ci_harness.dart').existsSync() ||
      !File('${root.path}/$harness/test/native_qa_panel_test.dart')
          .existsSync() ||
      !File('${root.path}/$harness/ios/RunnerTests/RunnerTests.swift')
          .existsSync() ||
      !File('${root.path}/tool/run_native_evidence.dart').existsSync() ||
      !File('${root.path}/tool/run_native_ci_evidence.dart').existsSync()) {
    errors.add('Native capability integration harness is incomplete.');
  }
  _validateAndroid(root, contract['android'], errors);
  _validateIos(root, contract['ios'], errors);
  if (contract['receiptDirectory'] != 'build/native-evidence' ||
      contract['receiptDigest'] != 'sha256' ||
      contract['trackedTreeMustRemainClean'] != true ||
      contract['rawDeviceIdentifiersForbidden'] != true ||
      !_sameStrings(
        _strings(contract['ciEvidenceKinds'], errors),
        const <String>['build', 'simulator'],
      )) {
    errors.add('Native receipt, identifier, or cleanliness policy changed.');
  }
  final retention = _map(contract['physicalRetention'], errors);
  if (retention['kind'] != 'installed-app' ||
      retention['applicationId'] !=
          'dev.dartitect.dartitect_native_capabilities_harness' ||
      retention['dataClean'] != true ||
      retention['mediaClean'] != true ||
      retention['apkDigest'] != 'sha256') {
    errors.add('Physical Android retention policy is invalid.');
  }

  final cells = <String, Map<String, Object?>>{};
  for (final cell in _objects(contract['requiredCells'], errors)) {
    final id = cell['id'];
    final platform = cell['platform'];
    final kind = cell['evidenceKind'];
    final capabilities = _strings(cell['capabilities'], errors);
    final versions = _strings(cell['requiredVersionKeys'], errors);
    final scenarios = _strings(cell['requiredScenarios'], errors);
    if (id is! String ||
        id.isEmpty ||
        cells.containsKey(id) ||
        platform != 'android' && platform != 'ios' ||
        kind != 'build' && kind != 'simulator' && kind != 'physical' ||
        cell['floor'] is! bool ||
        capabilities.isEmpty ||
        capabilities.any(
          (capability) => capability != 'media' && capability != 'privacy',
        ) ||
        capabilities.toSet().length != capabilities.length ||
        versions.isEmpty ||
        versions.toSet().length != versions.length ||
        scenarios.isEmpty ||
        scenarios.toSet().length != scenarios.length ||
        !scenarios.contains('tree-clean')) {
      errors.add('Invalid native evidence cell: $id.');
      continue;
    }
    cells[id] = cell;
  }
  const requiredIds = <String>{
    'android-media-floor-build',
    'android-media-current-physical',
    'ios-media-floor-build',
    'ios-privacy-floor-build',
    'ios-current-simulator',
  };
  if (cells.length != requiredIds.length ||
      !_sameSets(cells.keys.toSet(), requiredIds) ||
      cells.values.where((cell) => cell['evidenceKind'] == 'physical').length !=
          1 ||
      cells.values
              .where((cell) => cell['evidenceKind'] == 'simulator')
              .length !=
          1 ||
      cells.values.where((cell) => cell['evidenceKind'] == 'build').length !=
          3 ||
      cells.values.any(
        (cell) =>
            '${cell['id']}'.contains('emulator') ||
            cell['evidenceKind'] == 'emulator',
      )) {
    errors.add('Native evidence matrix must contain exactly five RC.3 cells.');
  }
  return cells;
}

void _validateAndroid(Directory root, Object? value, List<String> errors) {
  final android = _map(value, errors);
  if (android['floorApi'] != 24 ||
      android['physicalApi'] != 34 ||
      android['requiredAdbServerSocket'] != 'tcp:127.0.0.1:5038' ||
      android['applicationId'] !=
          'dev.dartitect.dartitect_native_capabilities_harness') {
    errors.add('Android floor, physical runtime, socket, or app changed.');
  }
  final manifest = android['manifest'];
  final plugin = android['plugin'];
  if (manifest is! String || plugin is! String) {
    errors.add('Android native source paths are invalid.');
    return;
  }
  final source =
      '${_source(root, manifest, errors)}\n'
      '${_source(root, plugin, errors)}';
  for (final marker in _strings(android['requiredSourceMarkers'], errors)) {
    if (!source.contains(marker)) {
      errors.add('Android native contract is missing: $marker.');
    }
  }
}

void _validateIos(Directory root, Object? value, List<String> errors) {
  final ios = _map(value, errors);
  if (ios['mediaFloor'] != '14.0' || ios['privacyFloor'] != '12.0') {
    errors.add('iOS media/privacy floors changed.');
  }
  final paths = <String>[];
  for (final key in const <String>[
    'mediaPodspec',
    'privacyPodspec',
    'mediaPlugin',
    'privacyPlugin',
  ]) {
    final path = ios[key];
    if (path is! String) {
      errors.add('iOS source path $key is invalid.');
    } else {
      paths.add(path);
    }
  }
  final source = paths.map((path) => _source(root, path, errors)).join('\n');
  for (final marker in _strings(ios['requiredSourceMarkers'], errors)) {
    if (!source.contains(marker)) {
      errors.add('iOS native contract is missing: $marker.');
    }
  }
  for (final marker in const <String>[
    "s.platform = :ios, '14.0'",
    "s.platform = :ios, '12.0'",
  ]) {
    if (!source.contains(marker)) {
      errors.add('iOS podspec is missing $marker.');
    }
  }
}

void _validateReceipt(
  Map<String, Object?> receipt,
  Map<String, Object?> cell,
  Map<String, Object?> contract,
  String sourceSha,
  String sourceTree,
  List<String> errors,
) {
  final id = cell['id']! as String;
  final kind = cell['evidenceKind']! as String;
  final expectedTopLevel = <String>{
    'schemaVersion',
    'goal',
    'cellId',
    'sourceSha',
    'sourceTree',
    'result',
    'platform',
    'capabilities',
    'evidenceKind',
    'versions',
    'environment',
    'startedAt',
    'completedAt',
    'sourceDirty',
    'treeClean',
    'scenarios',
    if (kind == 'physical') 'retention' else 'workflow',
  };
  if (!_sameSets(receipt.keys.toSet(), expectedTopLevel)) {
    errors.add('$id receipt fields do not match schema v2.');
  }
  if (receipt['schemaVersion'] != 2 ||
      receipt['goal'] != 'V1S-13' ||
      receipt['cellId'] != id ||
      receipt['sourceSha'] != sourceSha ||
      receipt['sourceTree'] != sourceTree ||
      receipt['result'] != 'passed' ||
      receipt['platform'] != cell['platform'] ||
      receipt['evidenceKind'] != kind ||
      receipt['treeClean'] != true ||
      receipt['sourceDirty'] != false) {
    errors.add('$id receipt identity/result/cleanliness is invalid.');
  }
  if (!_sameStrings(
    _strings(receipt['capabilities'], errors),
    _strings(cell['capabilities'], errors),
  )) {
    errors.add('$id receipt capabilities changed.');
  }

  final versions = _map(receipt['versions'], errors);
  final requiredVersions = _strings(cell['requiredVersionKeys'], errors);
  if (!_sameSets(versions.keys.toSet(), requiredVersions.toSet())) {
    errors.add('$id exact version set is invalid.');
  }
  for (final key in requiredVersions) {
    final value = versions[key];
    if (value is! String ||
        value.trim().isEmpty ||
        const <String>{
          'current',
          'floor',
          'latest',
        }.contains(value.trim().toLowerCase())) {
      errors.add('$id version $key must be exact.');
    }
  }

  final environment = _map(receipt['environment'], errors);
  if (environment['kind'] != kind) {
    errors.add('$id environment kind is invalid.');
  }
  if (kind == 'build') {
    if (!_sameSets(environment.keys.toSet(), const <String>{
          'kind',
          'runnerOs',
          'runnerImage',
        }) ||
        !_nonEmpty(environment['runnerOs']) ||
        !_nonEmpty(environment['runnerImage'])) {
      errors.add('$id build environment is incomplete.');
    }
  } else if (kind == 'simulator') {
    if (!_sameSets(environment.keys.toSet(), const <String>{
          'kind',
          'runnerOs',
          'runnerImage',
          'deviceModel',
          'deviceIdSha256',
        }) ||
        !_nonEmpty(environment['runnerOs']) ||
        !_nonEmpty(environment['runnerImage']) ||
        !_nonEmpty(environment['deviceModel']) ||
        !_digest(environment['deviceIdSha256'])) {
      errors.add('$id simulator environment is incomplete.');
    }
  } else {
    if (!_sameSets(environment.keys.toSet(), const <String>{
          'kind',
          'osVersion',
          'apiLevel',
          'deviceModel',
          'deviceIdSha256',
          'bootCompleted',
          'availableDataKb',
          'batteryLevel',
          'batteryStatus',
        }) ||
        environment['apiLevel'] != 34 ||
        environment['bootCompleted'] != true ||
        !_nonEmpty(environment['osVersion']) ||
        !_nonEmpty(environment['deviceModel']) ||
        !_digest(environment['deviceIdSha256']) ||
        environment['availableDataKb'] is! int ||
        (environment['availableDataKb']! as int) <= 0 ||
        environment['batteryLevel'] is! int ||
        (environment['batteryLevel']! as int) < 0 ||
        (environment['batteryLevel']! as int) > 100 ||
        !_nonEmpty(environment['batteryStatus'])) {
      errors.add('$id physical environment/preflight is incomplete.');
    }
  }

  final startedAt = _utc(receipt['startedAt']);
  final completedAt = _utc(receipt['completedAt']);
  if (startedAt == null ||
      completedAt == null ||
      completedAt.isBefore(startedAt)) {
    errors.add('$id must record an ordered UTC interval.');
  }
  if (!_sameStrings(
    _strings(receipt['scenarios'], errors),
    _strings(cell['requiredScenarios'], errors),
  )) {
    errors.add('$id does not cover the exact required scenario set.');
  }

  if (kind == 'physical') {
    if (receipt.containsKey('workflow')) {
      errors.add('$id physical receipt must not claim a CI workflow.');
    }
    final retention = _map(receipt['retention'], errors);
    final policy = _map(contract['physicalRetention'], errors);
    if (!_sameSets(retention.keys.toSet(), const <String>{
          'kind',
          'applicationId',
          'dataClean',
          'mediaClean',
          'apkSha256',
        }) ||
        retention['kind'] != policy['kind'] ||
        retention['applicationId'] != policy['applicationId'] ||
        retention['dataClean'] != true ||
        retention['mediaClean'] != true ||
        !_digest(retention['apkSha256'])) {
      errors.add('$id authorized installed-app retention is invalid.');
    }
  } else {
    final workflow = _map(receipt['workflow'], errors);
    if (!_sameSets(workflow.keys.toSet(), const <String>{
          'workflow',
          'runId',
          'runAttempt',
          'repository',
          'event',
          'url',
          'sourceSha',
        }) ||
        !_nonEmpty(workflow['workflow']) ||
        workflow['runId'] is! int ||
        (workflow['runId']! as int) <= 0 ||
        workflow['runAttempt'] is! int ||
        (workflow['runAttempt']! as int) <= 0 ||
        !_nonEmpty(workflow['repository']) ||
        !_nonEmpty(workflow['event']) ||
        workflow['sourceSha'] != sourceSha ||
        !_workflowUrl(
          workflow['url'],
          workflow['repository'],
          workflow['runId'],
        )) {
      errors.add('$id CI workflow/run receipt is invalid.');
    }
  }

  final forbiddenPath = _forbiddenIdentifierPath(receipt);
  if (forbiddenPath != null) {
    errors.add('$id contains a raw device identifier field at $forbiddenPath.');
  }
}

String? _forbiddenIdentifierPath(Object? value, [String path = r'$']) {
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      final lower = entry.key.toLowerCase();
      if (lower.contains('serial') ||
          lower == 'udid' ||
          lower == 'deviceid' ||
          lower == 'deviceidentifier' ||
          lower == 'identifier') {
        return '$path.${entry.key}';
      }
      final nested = _forbiddenIdentifierPath(
        entry.value,
        '$path.${entry.key}',
      );
      if (nested != null) return nested;
    }
  } else if (value is List<Object?>) {
    for (var index = 0; index < value.length; index += 1) {
      final nested = _forbiddenIdentifierPath(value[index], '$path[$index]');
      if (nested != null) return nested;
    }
  }
  return null;
}

Future<List<File>> _receiptFiles(
  Directory root,
  Map<String, Object?> contract,
  List<String> arguments,
  List<String> errors,
) async {
  final explicit = arguments
      .where((argument) => argument.startsWith('--receipt='))
      .map((argument) => argument.substring('--receipt='.length))
      .toList();
  if (explicit.isNotEmpty) {
    final files = <File>[];
    for (final path in explicit) {
      final file = File(path).absolute;
      if (!file.existsSync()) {
        errors.add('Native receipt is missing: $path.');
      } else {
        files.add(file);
      }
    }
    return files;
  }
  final path = contract['receiptDirectory'];
  if (path is! String) return <File>[];
  final directory = Directory('${root.path}/$path');
  if (!directory.existsSync()) return <File>[];
  return directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
}

String? _singleArgument(List<String> arguments, String prefix) {
  final values = arguments
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => argument.substring(prefix.length))
      .toList();
  if (values.length > 1) {
    throw FormatException('Argument $prefix may appear only once.');
  }
  if (values case [final value] when value.trim().isEmpty) {
    throw FormatException('Argument $prefix must not be empty.');
  }
  return values.isEmpty ? null : values.single;
}

Future<String> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}

void _finish(List<String> errors, String success) {
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(success);
}

String _source(Directory root, String path, List<String> errors) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    errors.add('Native evidence source is missing: $path.');
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

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.toSet().length == left.length &&
    right.toSet().length == right.length &&
    _sameSets(left.toSet(), right.toSet());

bool _sameSets(Set<Object?> left, Set<Object?> right) =>
    left.length == right.length && left.containsAll(right);

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

bool _digest(Object? value) =>
    value is String && _sha256Pattern.hasMatch(value);

DateTime? _utc(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || !value.endsWith('Z')) return null;
  return parsed;
}

bool _workflowUrl(Object? value, Object? repository, Object? runId) {
  if (value is! String || repository is! String || runId is! int) return false;
  return value == 'https://github.com/$repository/actions/runs/$runId';
}

String _relative(Directory root, File file) => file.path.startsWith(root.path)
    ? file.path.substring(root.path.length + 1)
    : file.path;

final _shaPattern = RegExp(r'^[0-9a-f]{40}$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
