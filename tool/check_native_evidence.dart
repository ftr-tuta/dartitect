import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _requiredCellIds = <String>{
  'android-media-floor-build',
  'android-media-current-emulator',
  'ios-media-floor-build',
  'ios-privacy-floor-build',
  'ios-current-simulator',
};
const _allowedKinds = <String>{'build', 'emulator', 'simulator'};
final _gitSha = RegExp(r'^[0-9a-f]{40}$');

Future<void> main(List<String> arguments) async {
  try {
    await _main(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Native evidence could not be validated: $error');
    exitCode = 1;
  }
}

Future<void> _main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final root = options.root ?? File.fromUri(Platform.script).parent.parent;
  final errors = <String>[];
  final contract = _readObject(
    File('${root.path}/tool/native_evidence_contract.json'),
  );
  final cells = _validateContract(root, contract, errors);
  if (options.contractOnly) {
    _finish(
      errors,
      'Native evidence schema v3 passed exactly five hosted '
      'build/emulator/simulator cells; local validation cannot declare '
      'formal evidence.',
    );
    return;
  }

  final context = _ActionsContext.fromEnvironment(Platform.environment);
  final head = (await _git(root, const <String>['rev-parse', 'HEAD'])).trim();
  final tree = (await _git(root, const <String>[
    'show',
    '-s',
    '--format=%T',
    'HEAD',
  ])).trim();
  if (head != context.sourceSha) {
    errors.add('GITHUB_SHA does not match the checked-out source SHA.');
  }

  final files = _manifestFiles(root, contract, options.manifests, errors);
  final byCell = <String, Map<String, Object?>>{};
  for (final file in files) {
    try {
      final manifest = _readObject(file);
      final id = manifest['cellId'];
      if (id is! String || !cells.containsKey(id)) {
        errors.add('${_relative(root, file)} names an unknown native cell.');
        continue;
      }
      if (byCell.containsKey(id)) {
        errors.add('Duplicate native manifest for $id.');
        continue;
      }
      _validateManifest(manifest, cells[id]!, context, tree, errors);
      byCell[id] = manifest;
      stdout.writeln(
        '$id manifest sha256 '
        '${(await sha256.bind(file.openRead()).first)}',
      );
    } on FormatException catch (error) {
      errors.add('${_relative(root, file)} is invalid: ${error.message}');
    }
  }
  for (final id in _requiredCellIds) {
    if (!byCell.containsKey(id)) {
      errors.add('Missing native evidence manifest for $id.');
    }
  }
  if (files.length != _requiredCellIds.length) {
    errors.add(
      'Native manifest set is not exact: expected '
      '${_requiredCellIds.length}, found ${files.length}.',
    );
  }

  final dirty = await _git(root, const <String>[
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]);
  if (dirty.trim().isNotEmpty) {
    errors.add('Source tree is dirty while validating native manifests.');
  }
  _finish(
    errors,
    'Native evidence passed all five hosted cells for ${context.sourceSha}, '
    'tree $tree, run ${context.runId}/${context.runAttempt}.',
  );
}

Map<String, Map<String, Object?>> _validateContract(
  Directory root,
  Map<String, Object?> contract,
  List<String> errors,
) {
  if (contract['schemaVersion'] != 3 ||
      contract['manifestSchemaVersion'] != 3 ||
      contract['goal'] != 'V1S-13' ||
      contract['authority'] != 'github-actions-current-run' ||
      contract['manifestDirectory'] != 'build/native-evidence' ||
      contract['manifestDigest'] != 'sha256' ||
      contract['trackedTreeMustRemainClean'] != true ||
      contract['hostedRunnersOnly'] != true ||
      !_sameStrings(
        _strings(contract['allowedEvidenceKinds'], errors),
        const <String>['build', 'emulator', 'simulator'],
      )) {
    errors.add('Unsupported or weakened native evidence contract.');
  }
  final encoded = jsonEncode(contract).toLowerCase();
  for (final forbidden in const <String>[
    'physical',
    'self-hosted',
    'adb_server_socket',
    'installed-app',
  ]) {
    if (encoded.contains(forbidden)) {
      errors.add(
        'Native evidence contract contains forbidden policy: $forbidden.',
      );
    }
  }

  final harness = contract['harness'];
  if (harness is! String ||
      !File('${root.path}/$harness/lib/main.dart').existsSync() ||
      !File('${root.path}/$harness/integration_test/android_media_test.dart')
          .existsSync() ||
      !File('${root.path}/$harness/lib/ios_ci_harness.dart').existsSync() ||
      !File('${root.path}/tool/run_native_ci_evidence.dart').existsSync()) {
    errors.add('Native capability Actions harness is incomplete.');
  }
  _validateAndroid(root, contract['android'], errors);
  _validateIos(root, contract['ios'], errors);

  final cells = <String, Map<String, Object?>>{};
  for (final cell in _objects(contract['requiredCells'], errors)) {
    final id = cell['id'];
    final kind = cell['evidenceKind'];
    final capabilities = _strings(cell['capabilities'], errors);
    final versions = _strings(cell['requiredVersionKeys'], errors);
    final scenarios = _strings(cell['requiredScenarios'], errors);
    if (id is! String ||
        id.isEmpty ||
        cells.containsKey(id) ||
        (cell['platform'] != 'android' && cell['platform'] != 'ios') ||
        kind is! String ||
        !_allowedKinds.contains(kind) ||
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
  if (!_sameSets(cells.keys.toSet(), _requiredCellIds) ||
      cells.values.where((cell) => cell['evidenceKind'] == 'build').length !=
          3 ||
      cells.values.where((cell) => cell['evidenceKind'] == 'emulator').length !=
          1 ||
      cells.values
              .where((cell) => cell['evidenceKind'] == 'simulator')
              .length !=
          1) {
    errors.add('Native evidence matrix must contain the exact five v3 cells.');
  }
  return cells;
}

void _validateAndroid(Directory root, Object? value, List<String> errors) {
  final android = _map(value, errors);
  if (android['floorApi'] != 24 ||
      android['emulatorApi'] != 34 ||
      android['systemImage'] != 'system-images;android-34;google_apis;x86_64' ||
      android['avdName'] != 'dartitect-api-34' ||
      android['applicationId'] !=
          'dev.dartitect.dartitect_native_capabilities_harness') {
    errors.add('Android floor or hosted emulator policy changed.');
  }
  final paths = <String>[];
  for (final key in const <String>['manifest', 'plugin']) {
    final path = android[key];
    if (path is String) {
      paths.add(path);
    } else {
      errors.add('Android source path $key is invalid.');
    }
  }
  final source = paths.map((path) => _source(root, path, errors)).join('\n');
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
    if (path is String) {
      paths.add(path);
    } else {
      errors.add('iOS source path $key is invalid.');
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
    if (!source.contains(marker)) errors.add('iOS podspec is missing $marker.');
  }
}

void _validateManifest(
  Map<String, Object?> manifest,
  Map<String, Object?> cell,
  _ActionsContext context,
  String sourceTree,
  List<String> errors,
) {
  final id = cell['id']! as String;
  final kind = cell['evidenceKind']! as String;
  if (!_sameSets(manifest.keys.toSet(), const <String>{
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
    'treeClean',
    'scenarios',
    'workflow',
  })) {
    errors.add('$id manifest fields do not match schema v3.');
  }
  if (manifest['schemaVersion'] != 3 ||
      manifest['goal'] != 'V1S-13' ||
      manifest['cellId'] != id ||
      manifest['sourceSha'] != context.sourceSha ||
      manifest['sourceTree'] != sourceTree ||
      manifest['result'] != 'success' ||
      manifest['platform'] != cell['platform'] ||
      manifest['evidenceKind'] != kind ||
      manifest['treeClean'] != true) {
    errors.add('$id identity, conclusion, or tree binding is invalid.');
  }
  if (!_sameStrings(
    _strings(manifest['capabilities'], errors),
    _strings(cell['capabilities'], errors),
  )) {
    errors.add('$id capabilities changed.');
  }
  if (!_sameStrings(
    _strings(manifest['scenarios'], errors),
    _strings(cell['requiredScenarios'], errors),
  )) {
    errors.add('$id does not cover the exact required scenarios.');
  }

  final versions = _map(manifest['versions'], errors);
  final versionKeys = _strings(cell['requiredVersionKeys'], errors);
  if (!_sameSets(versions.keys.toSet(), versionKeys.toSet()) ||
      versionKeys.any((key) => !_exactVersion(versions[key]))) {
    errors.add('$id exact version set is invalid.');
  }
  _validateEnvironment(id, kind, manifest['environment'], errors);

  final started = _utc(manifest['startedAt']);
  final completed = _utc(manifest['completedAt']);
  if (started == null || completed == null || completed.isBefore(started)) {
    errors.add('$id must record an ordered UTC interval.');
  }
  final workflow = _map(manifest['workflow'], errors);
  if (!_sameSets(workflow.keys.toSet(), const <String>{
        'name',
        'runId',
        'runAttempt',
        'repository',
        'event',
        'url',
        'sourceSha',
        'sourceTree',
      }) ||
      workflow['name'] != 'CI' ||
      workflow['runId'] != context.runId ||
      workflow['runAttempt'] != context.runAttempt ||
      workflow['repository'] != context.repository ||
      workflow['sourceSha'] != context.sourceSha ||
      workflow['sourceTree'] != sourceTree ||
      !_nonEmpty(workflow['event']) ||
      workflow['url'] !=
          'https://github.com/${context.repository}/actions/runs/${context.runId}') {
    errors.add('$id is not from the current GitHub Actions run.');
  }
  final forbidden = _forbiddenField(manifest);
  if (forbidden != null) errors.add('$id contains forbidden field $forbidden.');
}

void _validateEnvironment(
  String id,
  String kind,
  Object? value,
  List<String> errors,
) {
  final environment = _map(value, errors);
  final common = const <String>{
    'kind',
    'provider',
    'runnerName',
    'runnerOs',
    'runnerImage',
  };
  final expected = switch (kind) {
    'build' => common,
    'emulator' => <String>{
      ...common,
      'apiLevel',
      'systemImage',
      'avdName',
      'osVersion',
      'model',
      'bootCompleted',
      'cleanShutdown',
    },
    'simulator' => <String>{...common, 'runtime', 'model', 'cleanupCompleted'},
    _ => const <String>{},
  };
  if (!_sameSets(environment.keys.toSet(), expected) ||
      environment['kind'] != kind ||
      environment['provider'] != 'github-hosted' ||
      !_nonEmpty(environment['runnerName']) ||
      !_nonEmpty(environment['runnerOs']) ||
      !_nonEmpty(environment['runnerImage'])) {
    errors.add('$id hosted runner environment is incomplete.');
    return;
  }
  if (kind == 'emulator' &&
      (environment['apiLevel'] != 34 ||
          environment['systemImage'] !=
              'system-images;android-34;google_apis;x86_64' ||
          environment['avdName'] != 'dartitect-api-34' ||
          !_nonEmpty(environment['osVersion']) ||
          !_nonEmpty(environment['model']) ||
          environment['bootCompleted'] != true ||
          environment['cleanShutdown'] != true)) {
    errors.add('$id Android emulator environment is invalid.');
  }
  if (kind == 'simulator' &&
      (!_nonEmpty(environment['runtime']) ||
          !_nonEmpty(environment['model']) ||
          environment['cleanupCompleted'] != true)) {
    errors.add('$id iOS simulator environment is invalid.');
  }
}

String? _forbiddenField(Object? value, [String path = r'$']) {
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('serial') ||
          key == 'udid' ||
          key == 'deviceid' ||
          key == 'deviceidentifier' ||
          key == 'identifier' ||
          key == 'retention' ||
          key == 'receipt') {
        return '$path.${entry.key}';
      }
      final nested = _forbiddenField(entry.value, '$path.${entry.key}');
      if (nested != null) return nested;
    }
  } else if (value is List<Object?>) {
    for (var index = 0; index < value.length; index += 1) {
      final nested = _forbiddenField(value[index], '$path[$index]');
      if (nested != null) return nested;
    }
  }
  return null;
}

List<File> _manifestFiles(
  Directory root,
  Map<String, Object?> contract,
  List<String> explicit,
  List<String> errors,
) {
  if (explicit.isNotEmpty) {
    final files = <File>[];
    for (final path in explicit) {
      final file = File(path).absolute;
      if (file.existsSync()) {
        files.add(file);
      } else {
        errors.add('Native manifest is missing: $path.');
      }
    }
    return files;
  }
  final path = contract['manifestDirectory'];
  if (path is! String) return const <File>[];
  final directory = Directory('${root.path}/$path');
  if (!directory.existsSync()) return const <File>[];
  return directory
      .listSync(followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
}

Map<String, Object?> _readObject(File file) {
  if (!file.existsSync()) throw FormatException('${file.path} is missing.');
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected one JSON object.');
  }
  return value;
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

String _source(Directory root, String path, List<String> errors) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    errors.add('Native evidence source is missing: $path.');
    return '';
  }
  return file.readAsStringSync();
}

Map<String, Object?> _map(Object? value, List<String> errors) {
  if (value is! Map<String, Object?>) {
    errors.add('Expected a JSON object field.');
    return const <String, Object?>{};
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value, List<String> errors) {
  if (value is! List<Object?> ||
      value.any((item) => item is! Map<String, Object?>)) {
    errors.add('Expected a JSON object list.');
    return const <Map<String, Object?>>[];
  }
  return value.cast<Map<String, Object?>>();
}

List<String> _strings(Object? value, List<String> errors) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    errors.add('Expected a JSON string list.');
    return const <String>[];
  }
  return value.cast<String>();
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length && _sameSets(left.toSet(), right.toSet());

bool _sameSets(Set<Object?> left, Set<Object?> right) =>
    left.length == right.length && left.containsAll(right);

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

bool _exactVersion(Object? value) =>
    value is String &&
    value.trim().isNotEmpty &&
    !const <String>{
      'current',
      'floor',
      'latest',
    }.contains(value.trim().toLowerCase());

DateTime? _utc(Object? value) {
  if (value is! String || !value.endsWith('Z')) return null;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.isUtc ? parsed : null;
}

String _relative(Directory root, File file) => file.path.startsWith(root.path)
    ? file.path.substring(root.path.length + 1)
    : file.path;

void _finish(List<String> errors, String success) {
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
  } else {
    stdout.writeln(success);
  }
}

final class _ActionsContext {
  const _ActionsContext({
    required this.sourceSha,
    required this.runId,
    required this.runAttempt,
    required this.repository,
  });

  factory _ActionsContext.fromEnvironment(Map<String, String> environment) {
    String required(String key) {
      final value = environment[key];
      if (value == null || value.trim().isEmpty) {
        throw StateError('Required GitHub Actions environment $key is absent.');
      }
      return value;
    }

    if (environment['GITHUB_ACTIONS'] != 'true' ||
        environment['RUNNER_ENVIRONMENT'] != 'github-hosted') {
      throw StateError(
        'Formal native evidence is restricted to GitHub-hosted Actions.',
      );
    }
    final sha = required('GITHUB_SHA');
    final runId = int.tryParse(required('GITHUB_RUN_ID'));
    final attempt = int.tryParse(required('GITHUB_RUN_ATTEMPT'));
    if (!_gitSha.hasMatch(sha) ||
        runId == null ||
        runId <= 0 ||
        attempt == null ||
        attempt <= 0) {
      throw StateError('GitHub Actions run identity is invalid.');
    }
    return _ActionsContext(
      sourceSha: sha,
      runId: runId,
      runAttempt: attempt,
      repository: required('GITHUB_REPOSITORY'),
    );
  }

  final String sourceSha;
  final int runId;
  final int runAttempt;
  final String repository;
}

final class _Options {
  const _Options({
    required this.contractOnly,
    required this.manifests,
    this.root,
  });

  factory _Options.parse(List<String> arguments) {
    var contractOnly = false;
    Directory? root;
    final manifests = <String>[];
    for (final argument in arguments) {
      if (argument == '--contract-only') {
        if (contractOnly)
          throw const FormatException('Duplicate --contract-only.');
        contractOnly = true;
      } else if (argument.startsWith('--root=')) {
        if (root != null || argument.substring(7).trim().isEmpty) {
          throw const FormatException('Invalid or duplicate --root=.');
        }
        root = Directory(argument.substring(7)).absolute;
      } else if (argument.startsWith('--manifest=')) {
        final value = argument.substring('--manifest='.length);
        if (value.trim().isEmpty) {
          throw const FormatException('--manifest= must not be empty.');
        }
        manifests.add(value);
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    if (contractOnly && manifests.isNotEmpty) {
      throw const FormatException(
        '--contract-only cannot consume formal manifests.',
      );
    }
    return _Options(
      contractOnly: contractOnly,
      manifests: manifests,
      root: root,
    );
  }

  final bool contractOnly;
  final List<String> manifests;
  final Directory? root;
}
