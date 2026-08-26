import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  final contractOnly = arguments.contains('--contract-only');
  final unknown = arguments.where(
    (argument) =>
        argument != '--contract-only' &&
        !argument.startsWith('--source-sha=') &&
        !argument.startsWith('--receipt='),
  );
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown arguments: ${unknown.join(', ')}');
    exitCode = 64;
    return;
  }
  final contract = _object(
    jsonDecode(
      File('${root.path}/tool/native_evidence_contract.json')
          .readAsStringSync(),
    ),
  );
  final cells = _validateContract(root, contract, errors);
  if (contractOnly) {
    _finish(
      errors,
      'Native evidence contract passed ${cells.length} fail-closed cells; '
      'device receipts were not evaluated.',
    );
    return;
  }

  final sourceSha =
      _singleArgument(arguments, '--source-sha=') ??
      (await _git(root, const <String>['rev-parse', 'HEAD'])).trim();
  if (!_shaPattern.hasMatch(sourceSha)) {
    errors.add('Native evidence source SHA is invalid.');
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
      _validateReceipt(receipt, cells[id]!, sourceSha, errors);
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
      errors.add('Missing native device receipt for $id at $sourceSha.');
    }
  }

  final dirty = await _git(root, const <String>[
    'status',
    '--porcelain',
    '--untracked-files=no',
  ]);
  if (dirty.trim().isNotEmpty) {
    errors.add('Tracked tree is dirty while validating native receipts.');
  }
  _finish(
    errors,
    'Native evidence passed all ${cells.length} floor/current, '
    'simulator/emulator, physical-device, lifecycle, and cleanliness cells '
    'at $sourceSha.',
  );
}

Map<String, Map<String, Object?>> _validateContract(
  Directory root,
  Map<String, Object?> contract,
  List<String> errors,
) {
  if (contract['schemaVersion'] != 1 || contract['goal'] != 'V1S-13') {
    errors.add('Unsupported native evidence contract.');
  }
  final harness = contract['harness'];
  if (harness is! String ||
      !File('${root.path}/$harness/lib/main.dart').existsSync() ||
      !File('${root.path}/$harness/integration_test/android_media_test.dart')
          .existsSync()) {
    errors.add('Native capability integration harness is incomplete.');
  }
  _validateAndroid(root, contract['android'], errors);
  _validateIos(root, contract['ios'], errors);
  if (contract['receiptDirectory'] != 'build/native-evidence' ||
      contract['receiptDigest'] != 'sha256' ||
      contract['trackedTreeMustRemainClean'] != true) {
    errors.add('Native receipt or tree-cleanliness policy changed.');
  }

  final cells = <String, Map<String, Object?>>{};
  for (final cell in _objects(contract['requiredCells'], errors)) {
    final id = cell['id'];
    final platform = cell['platform'];
    final capability = cell['capability'];
    final deviceKind = cell['deviceKind'];
    final scenarios = _strings(cell['requiredScenarios'], errors);
    if (id is! String ||
        id.isEmpty ||
        cells.containsKey(id) ||
        platform != 'android' && platform != 'ios' ||
        capability != 'media' && capability != 'privacy' ||
        deviceKind != 'emulator' &&
            deviceKind != 'simulator' &&
            deviceKind != 'physical' ||
        cell['floor'] is! bool ||
        scenarios.isEmpty ||
        scenarios.toSet().length != scenarios.length ||
        !scenarios.contains('tree-clean')) {
      errors.add('Invalid native evidence cell: $id.');
      continue;
    }
    cells[id] = cell;
  }
  if (cells.length != 9 ||
      cells.values.where((cell) => cell['deviceKind'] == 'physical').length !=
          3 ||
      cells.values.where((cell) => cell['floor'] == true).length != 3 ||
      !cells.keys.toSet().containsAll(const <String>{
        'android-media-floor-emulator',
        'android-media-current-emulator',
        'android-media-current-physical',
        'ios-media-floor-simulator',
        'ios-media-current-simulator',
        'ios-media-current-physical',
        'ios-privacy-floor-simulator',
        'ios-privacy-current-simulator',
        'ios-privacy-current-physical',
      })) {
    errors.add(
      'Native floor/current and physical-device matrix is incomplete.',
    );
  }
  return cells;
}

void _validateAndroid(Directory root, Object? value, List<String> errors) {
  final android = _map(value, errors);
  if (android['floorApi'] != 24) {
    errors.add('Android floor must remain API 24.');
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
    if (!source.contains(marker)) errors.add('iOS podspec is missing $marker.');
  }
}

void _validateReceipt(
  Map<String, Object?> receipt,
  Map<String, Object?> cell,
  String sourceSha,
  List<String> errors,
) {
  final id = cell['id']! as String;
  if (receipt['schemaVersion'] != 1 ||
      receipt['goal'] != 'V1S-13' ||
      receipt['cellId'] != id ||
      receipt['sourceSha'] != sourceSha ||
      receipt['result'] != 'passed' ||
      receipt['platform'] != cell['platform'] ||
      receipt['capability'] != cell['capability'] ||
      receipt['deviceKind'] != cell['deviceKind'] ||
      receipt['treeClean'] != true ||
      receipt['sourceDirty'] != false) {
    errors.add('$id receipt identity/result/cleanliness is invalid.');
  }
  for (final key in const <String>[
    'osVersion',
    'sdkVersion',
    'flutterVersion',
    'dartVersion',
    'deviceModel',
    'deviceIdSha256',
    'startedAt',
    'completedAt',
  ]) {
    final value = receipt[key];
    if (value is! String || value.trim().isEmpty) {
      errors.add('$id receipt field $key is missing.');
    }
  }
  final deviceDigest = receipt['deviceIdSha256'];
  if (deviceDigest is! String || !_sha256Pattern.hasMatch(deviceDigest)) {
    errors.add('$id device identifier digest is invalid.');
  }
  for (final key in const <String>['startedAt', 'completedAt']) {
    final parsed = DateTime.tryParse('${receipt[key]}');
    if (parsed == null || !parsed.isUtc) {
      errors.add('$id $key must be a UTC timestamp.');
    }
  }
  final scenarios = _strings(receipt['scenarios'], errors).toSet();
  if (!scenarios.containsAll(_strings(cell['requiredScenarios'], errors))) {
    errors.add('$id does not cover every required native scenario.');
  }
  final osVersion = '${receipt['osVersion']}';
  if (osVersion.toLowerCase() == 'current' ||
      osVersion.toLowerCase() == 'floor') {
    errors.add('$id must record an exact OS version.');
  }
  if (cell['platform'] == 'android') {
    final api = receipt['apiLevel'];
    if (api is! int || api < 24) {
      errors.add('$id has an invalid Android API level.');
    } else if (cell['floor'] == true && api != 24) {
      errors.add('$id must execute exactly on Android API 24.');
    } else if (cell['floor'] == false && api <= 24) {
      errors.add('$id current Android receipt did not advance beyond floor.');
    }
  } else {
    final floor = cell['capability'] == 'media' ? 14 : 12;
    final major = int.tryParse(osVersion.split('.').first);
    if (major == null ||
        cell['floor'] == true && major != floor ||
        cell['floor'] == false && major <= floor) {
      errors.add('$id has an invalid iOS floor/current version.');
    }
  }
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

String _relative(Directory root, File file) => file.path.startsWith(root.path)
    ? file.path.substring(root.path.length + 1)
    : file.path;

final _shaPattern = RegExp(r'^[0-9a-f]{40}$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
