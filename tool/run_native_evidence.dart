import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'src/native_evidence_device.dart';
import 'src/native_evidence_harness.dart';

const _physicalCell = 'android-media-current-physical';
const _applicationId = 'dev.dartitect.dartitect_native_capabilities_harness';

Future<void> main(List<String> arguments) async {
  String? deviceId;
  try {
    deviceId = _argument(arguments, '--device=');
    await _main(arguments);
  } on Object catch (error) {
    final message = deviceId == null
        ? '$error'
        : redactDeviceId('$error', deviceId);
    stderr.writeln(message);
    exitCode = error is FormatException ? 64 : 1;
  }
}

Future<void> _main(List<String> arguments) async {
  final cellId = _argument(arguments, '--cell=');
  final deviceId = _argument(arguments, '--device=');
  if (arguments.length != 2 ||
      arguments.any(
        (argument) =>
            !argument.startsWith('--cell=') &&
            !argument.startsWith('--device='),
      )) {
    throw const FormatException(
      'Usage: dart run tool/run_native_evidence.dart '
      '--cell=android-media-current-physical --device=<physical-device-id>',
    );
  }
  if (cellId != _physicalCell) {
    throw const FormatException(
      'The local runner supports only android-media-current-physical.',
    );
  }
  final environment = nativeEvidenceEnvironment(Platform.environment);
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final contract = _object(
    jsonDecode(
      File('${root.path}/tool/native_evidence_contract.json')
          .readAsStringSync(),
    ),
  );
  final cell = _objects(contract['requiredCells'])
      .singleWhere((candidate) => candidate['id'] == cellId);
  final sourceSha = (await _run(root, 'git', const <String>[
    'rev-parse',
    'HEAD',
  ], environment: environment)).stdout.trim();
  final sourceTree = (await _run(root, 'git', const <String>[
    'show',
    '-s',
    '--format=%T',
    'HEAD',
  ], environment: environment)).stdout.trim();
  final dirtyBefore = (await _run(root, 'git', const <String>[
    'status',
    '--porcelain',
    '--untracked-files=all',
  ], environment: environment)).stdout;
  if (dirtyBefore.trim().isNotEmpty) {
    throw StateError('Commit or revert changes before physical evidence.');
  }

  final adb = await _discoverAdb(root, deviceId, environment);
  final adbDevices = await adb.server(const <String>['devices', '-l']);
  final flutter = _object(
    jsonDecode(
      (await _run(root, 'flutter', const <String>[
        '--version',
        '--machine',
      ], environment: environment)).stdout,
    ),
  );
  final flutterDevices = _objects(
    jsonDecode(
      (await _run(
        root,
        'flutter',
        const <String>['devices', '--machine'],
        environment: environment,
        redact: deviceId,
      )).stdout,
    ),
  );
  final selected = selectPhysicalAndroidDevice(
    requestedId: deviceId,
    adbDevicesOutput: adbDevices,
    flutterDevices: flutterDevices,
  );

  final apiLevel = int.parse(
    (await adb.run(const <String>['shell', 'getprop', 'ro.build.version.sdk']))
        .trim(),
  );
  requireAndroidApi34(apiLevel);
  final bootCompleted = (await adb.run(const <String>[
    'shell',
    'getprop',
    'sys.boot_completed',
  ])).trim();
  if (bootCompleted != '1') {
    throw StateError('The physical Android device has not completed boot.');
  }
  final osVersion = (await adb.run(const <String>[
    'shell',
    'getprop',
    'ro.build.version.release',
  ])).trim();
  final manufacturer = (await adb.run(const <String>[
    'shell',
    'getprop',
    'ro.product.manufacturer',
  ])).trim();
  final model = (await adb.run(const <String>[
    'shell',
    'getprop',
    'ro.product.model',
  ])).trim();
  final availableDataKb = _availableDataKb(
    await adb.run(const <String>['shell', 'df', '-k', '/data']),
  );
  final battery = _battery(
    await adb.run(const <String>['shell', 'dumpsys', 'battery']),
  );
  final adbVersion = (await adb.server(const <String>['version']))
      .split('\n')
      .first
      .trim();
  if (<String>[
    osVersion,
    manufacturer,
    model,
    adbVersion,
    '${flutter['frameworkVersion']}',
    '${flutter['dartSdkVersion']}',
  ].any((value) => value.trim().isEmpty)) {
    throw StateError('Physical preflight returned incomplete exact versions.');
  }

  final startedAt = DateTime.now().toUtc();
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-native-evidence-',
  );
  final consumer = Directory('${temporary.path}/consumer');
  File? apk;
  var integrationPassed = false;
  var mediaClean = false;
  var dataClean = false;
  try {
    await _run(temporary, 'flutter', <String>[
      'create',
      '--platforms=android',
      '--org=dev.dartitect',
      '--project-name=dartitect_native_capabilities_harness',
      consumer.path,
    ], environment: environment);
    await materializeNativeEvidenceHarness(
      root: root,
      consumer: consumer,
      packages: const <String>{'dartitect_media', 'dartitect_privacy'},
    );
    await _run(consumer, 'flutter', const <String>[
      'pub',
      'get',
    ], environment: environment);
    await _runPhysicalIntegration(
      consumer,
      deviceId,
      apiLevel,
      adb,
      environment,
    );
    integrationPassed = true;

    final packageState = await adb.run(const <String>[
      'shell',
      'dumpsys',
      'package',
      _applicationId,
    ]);
    if (RegExp(r'android\.permission\.WRITE_EXTERNAL_STORAGE:\s+granted=true')
        .hasMatch(packageState)) {
      throw StateError(
        'Android API 34 harness unexpectedly holds legacy storage permission.',
      );
    }
    await _cleanupAndroidTestAssets(adb);
    mediaClean = await _androidTestAssetsAreAbsent(adb);
    if (!mediaClean) {
      throw StateError('Formal Android test media remains after cleanup.');
    }

    await _run(consumer, 'flutter', const <String>[
      'build',
      'apk',
      '--debug',
    ], environment: environment);
    apk = File('${consumer.path}/build/app/outputs/flutter-apk/app-debug.apk');
    if (!apk.existsSync()) {
      throw StateError('Clean QA harness APK was not produced.');
    }
    await _installCleanHarness(adb, apk);
    dataClean = await _applicationDataIsClean(adb);
    if (!dataClean) {
      throw StateError('Installed QA harness retains owned preferences/data.');
    }
    final installed = await adb.run(const <String>[
      'shell',
      'pm',
      'path',
      _applicationId,
    ]);
    if (!installed.trim().startsWith('package:')) {
      throw StateError('Clean QA harness is not installed.');
    }

    final dirtyAfter = (await _run(root, 'git', const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ], environment: environment)).stdout;
    if (dirtyAfter != dirtyBefore) {
      throw StateError('Physical execution changed the source tree.');
    }
    final apkDigest = await sha256.bind(apk.openRead()).first;
    final receipt = <String, Object?>{
      'schemaVersion': 2,
      'goal': 'V1S-13',
      'cellId': cellId,
      'sourceSha': sourceSha,
      'sourceTree': sourceTree,
      'result': 'passed',
      'platform': 'android',
      'capabilities': cell['capabilities'],
      'evidenceKind': 'physical',
      'versions': <String, Object?>{
        'os': osVersion,
        'flutter': '${flutter['frameworkVersion']}',
        'dart': '${flutter['dartSdkVersion']}',
        'adb': adbVersion,
      },
      'environment': <String, Object?>{
        'kind': 'physical',
        'osVersion': osVersion,
        'apiLevel': apiLevel,
        'deviceModel': '$manufacturer $model'.trim().isEmpty
            ? selected.model
            : '$manufacturer $model'.trim(),
        'deviceIdSha256': selected.idSha256,
        'bootCompleted': true,
        'availableDataKb': availableDataKb,
        'batteryLevel': battery.level,
        'batteryStatus': battery.status,
      },
      'startedAt': startedAt.toIso8601String(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceDirty': false,
      'treeClean': true,
      'scenarios': cell['requiredScenarios'],
      'retention': <String, Object?>{
        'kind': 'installed-app',
        'applicationId': _applicationId,
        'dataClean': true,
        'mediaClean': true,
        'apkSha256': '$apkDigest',
      },
    };
    final receiptDirectory = Directory(
      '${root.path}/${contract['receiptDirectory']}',
    );
    await receiptDirectory.create(recursive: true);
    final receiptFile = File(
      '${receiptDirectory.path}/$cellId-$sourceSha.json',
    );
    await receiptFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
    );
    stdout.writeln('Physical receipt written with device identifier redacted.');
    stdout.writeln('Native evidence receipt: ${receiptFile.path}');
  } finally {
    await adb.run(const <String>[
      'shell',
      'am',
      'task',
      'lock',
      'stop',
    ], allowFailure: true);
    await adb.run(const <String>[
      'shell',
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ], allowFailure: true);
    await _cleanupAndroidTestAssets(adb);
    if (!dataClean && apk != null && apk.existsSync()) {
      await _installCleanHarness(adb, apk, allowFailure: !integrationPassed);
    } else if (!dataClean) {
      await adb.run(const <String>[
        'shell',
        'pm',
        'clear',
        _applicationId,
      ], allowFailure: true);
    }
    if (!mediaClean && integrationPassed) {
      mediaClean = await _androidTestAssetsAreAbsent(adb);
    }
    if (!dataClean && integrationPassed) {
      dataClean = await _applicationDataIsClean(adb);
    }
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

Future<void> _runPhysicalIntegration(
  Directory consumer,
  String deviceId,
  int apiLevel,
  _Adb adb,
  Map<String, String> environment,
) async {
  final lifecycle = Completer<void>();
  final process = await Process.start(
    'flutter',
    <String>[
      'test',
      'integration_test/android_media_test.dart',
      '-d',
      deviceId,
      '--dart-define=DARTITECT_ANDROID_API=$apiLevel',
      '--dart-define=DARTITECT_EXERCISE_LIFECYCLE=true',
    ],
    workingDirectory: consumer.path,
    environment: environment,
  );
  stdout.writeln(
    '> flutter test integration_test/android_media_test.dart '
    '-d <physical-device>',
  );
  var lifecycleTriggered = false;
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        stdout.writeln(redactDeviceId(line, deviceId));
        if (!lifecycleTriggered && line.contains('DARTITECT_LIFECYCLE_READY')) {
          lifecycleTriggered = true;
          unawaited(
            _exerciseAndroidLifecycle(adb).then(
              (_) => lifecycle.complete(),
              onError: (Object error, StackTrace stackTrace) {
                lifecycle.completeError(error, stackTrace);
              },
            ),
          );
        }
      });
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) => stderr.writeln(redactDeviceId(line, deviceId)));
  final result = await process.exitCode;
  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  if (!lifecycleTriggered) {
    throw StateError('Integration test did not request lifecycle exercise.');
  }
  await lifecycle.future;
  if (result != 0) {
    throw StateError('Physical Android integration test failed.');
  }
}

Future<void> _exerciseAndroidLifecycle(_Adb adb) async {
  final accelerometer = (await adb.run(const <String>[
    'shell',
    'settings',
    'get',
    'system',
    'accelerometer_rotation',
  ])).trim();
  final userRotation = (await adb.run(const <String>[
    'shell',
    'settings',
    'get',
    'system',
    'user_rotation',
  ])).trim();
  if (!const <String>{'0', '1'}.contains(accelerometer) ||
      int.tryParse(userRotation) == null) {
    throw StateError('Could not capture Android rotation state.');
  }
  final targetRotation = userRotation == '0' ? '1' : '0';
  try {
    await adb.run(const <String>[
      'shell',
      'settings',
      'put',
      'system',
      'accelerometer_rotation',
      '0',
    ]);
    await adb.run(<String>[
      'shell',
      'settings',
      'put',
      'system',
      'user_rotation',
      targetRotation,
    ]);
    await Future<void>.delayed(const Duration(seconds: 2));
    final changed = (await adb.run(const <String>[
      'shell',
      'settings',
      'get',
      'system',
      'user_rotation',
    ])).trim();
    if (changed != targetRotation) {
      throw StateError('Android rotation exercise did not take effect.');
    }

    final taskId = await _resumedTaskId(adb, _applicationId);
    await adb.run(const <String>[
      'shell',
      'am',
      'start',
      '-a',
      'android.settings.SETTINGS',
    ]);
    await Future<void>.delayed(const Duration(seconds: 2));
    await adb.run(<String>['shell', 'am', 'task', 'lock', '$taskId']);
    await Future<void>.delayed(const Duration(seconds: 2));
    final activities = await adb.run(const <String>[
      'shell',
      'dumpsys',
      'activity',
      'activities',
    ]);
    if (!activities
        .split('\n')
        .any(
          (line) =>
              line.contains('topResumedActivity=') &&
              line.contains(_applicationId),
        )) {
      throw StateError('Instrumented Android task did not resume.');
    }
  } finally {
    await adb.run(const <String>[
      'shell',
      'am',
      'task',
      'lock',
      'stop',
    ], allowFailure: true);
    await adb.run(<String>[
      'shell',
      'settings',
      'put',
      'system',
      'user_rotation',
      userRotation,
    ], allowFailure: true);
    await adb.run(<String>[
      'shell',
      'settings',
      'put',
      'system',
      'accelerometer_rotation',
      accelerometer,
    ], allowFailure: true);
  }
  final restoredAccelerometer = (await adb.run(const <String>[
    'shell',
    'settings',
    'get',
    'system',
    'accelerometer_rotation',
  ])).trim();
  final restoredRotation = (await adb.run(const <String>[
    'shell',
    'settings',
    'get',
    'system',
    'user_rotation',
  ])).trim();
  if (restoredAccelerometer != accelerometer ||
      restoredRotation != userRotation) {
    throw StateError('Android rotation state was not restored.');
  }
}

Future<int> _resumedTaskId(_Adb adb, String application) async {
  final activities = await adb.run(const <String>[
    'shell',
    'dumpsys',
    'activity',
    'activities',
  ]);
  int? taskId;
  for (final line in activities.split('\n')) {
    final task = RegExp(r'\* Task\{[^\n]* #(\d+) ').firstMatch(line);
    if (task != null) taskId = int.parse(task.group(1)!);
    if (line.contains('topResumedActivity=') && line.contains(application)) {
      if (taskId != null) return taskId;
      break;
    }
  }
  throw StateError('Could not resolve the resumed instrumented task.');
}

Future<void> _cleanupAndroidTestAssets(_Adb adb) async {
  await adb.run(const <String>[
    'shell',
    'content',
    'delete',
    '--uri',
    'content://media/external/images/media',
    '--where',
    "_display_name='dartitect-v1s13.png'",
  ], allowFailure: true);
}

Future<bool> _androidTestAssetsAreAbsent(_Adb adb) async {
  final result = await adb.run(const <String>[
    'shell',
    'content',
    'query',
    '--uri',
    'content://media/external/images/media',
    '--projection',
    '_id',
    '--where',
    "_display_name='dartitect-v1s13.png'",
  ]);
  return !RegExp(r'\bRow:\s*\d+').hasMatch(result) &&
      !RegExp(r'_id=\d+').hasMatch(result);
}

Future<void> _installCleanHarness(
  _Adb adb,
  File apk, {
  bool allowFailure = false,
}) async {
  await adb.run(<String>[
    'install',
    '-r',
    '-t',
    apk.path,
  ], allowFailure: allowFailure);
  await adb.run(const <String>[
    'shell',
    'pm',
    'clear',
    _applicationId,
  ], allowFailure: allowFailure);
}

Future<bool> _applicationDataIsClean(_Adb adb) async {
  final preferences = await adb.run(const <String>[
    'shell',
    'run-as',
    _applicationId,
    'sh',
    '-c',
    r'dirty=0; for path in shared_prefs files databases app_flutter; do [ -d "$path" ] && [ -n "$(ls -A "$path" 2>/dev/null)" ] && dirty=1; done; [ "$dirty" -eq 0 ] && echo CLEAN || echo DIRTY',
  ]);
  return preferences.trim() == 'CLEAN';
}

int _availableDataKb(String output) {
  final lines = output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 2) throw StateError('Android data-space check failed.');
  final fields = lines.last.split(RegExp(r'\s+'));
  if (fields.length < 4) throw StateError('Android data-space output changed.');
  final value = int.tryParse(fields[3]);
  if (value == null || value <= 0) {
    throw StateError('Android data-space value is invalid.');
  }
  return value;
}

_Battery _battery(String output) {
  int? level;
  String? status;
  for (final line in output.split('\n')) {
    final parts = line.trim().split(':');
    if (parts.length < 2) continue;
    if (parts.first == 'level') level = int.tryParse(parts[1].trim());
    if (parts.first == 'status') status = parts[1].trim();
  }
  if (level == null ||
      level < 0 ||
      level > 100 ||
      status == null ||
      status.isEmpty) {
    throw StateError('Android battery preflight is invalid.');
  }
  return _Battery(level, status);
}

Future<_Adb> _discoverAdb(
  Directory root,
  String deviceId,
  Map<String, String> environment,
) async {
  final sdkRoots = <String>{
    for (final key in const <String>['ANDROID_SDK_ROOT', 'ANDROID_HOME'])
      if (environment[key] case final value? when value.trim().isNotEmpty)
        value,
  };
  final executableName = Platform.isWindows ? 'adb.exe' : 'adb';
  final candidates = <String>[
    for (final sdkRoot in sdkRoots)
      <String>[
        sdkRoot,
        'platform-tools',
        executableName,
      ].join(Platform.pathSeparator),
    'adb',
  ];
  for (final executable in candidates) {
    try {
      final result = await Process.run(
        executable,
        const <String>['version'],
        workingDirectory: root.path,
        environment: environment,
      );
      if (result.exitCode == 0) {
        return _Adb(root, executable, deviceId, environment);
      }
    } on ProcessException {
      // Try the next explicit SDK root or PATH fallback.
    }
  }
  throw StateError(
    'adb is unavailable; configure ANDROID_SDK_ROOT/ANDROID_HOME or PATH.',
  );
}

final class _Adb {
  const _Adb(this.root, this.executable, this.deviceId, this.environment);

  final Directory root;
  final String executable;
  final String deviceId;
  final Map<String, String> environment;

  Future<String> server(List<String> arguments, {bool allowFailure = false}) =>
      _execute(arguments, allowFailure: allowFailure);

  Future<String> run(List<String> arguments, {bool allowFailure = false}) =>
      _execute(<String>[
        '-s',
        deviceId,
        ...arguments,
      ], allowFailure: allowFailure);

  Future<String> _execute(
    List<String> arguments, {
    required bool allowFailure,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: root.path,
      environment: environment,
    );
    final output = redactDeviceId(
      '${result.stdout}\n${result.stderr}',
      deviceId,
    );
    if (result.exitCode != 0 && !allowFailure) {
      throw StateError('Isolated adb command failed: $output');
    }
    return result.stdout as String;
  }
}

Future<_Output> _run(
  Directory workingDirectory,
  String executable,
  List<String> arguments, {
  required Map<String, String> environment,
  String? redact,
}) async {
  String safe(String value) =>
      redact == null ? value : redactDeviceId(value, redact);
  stdout.writeln(safe('> $executable ${arguments.join(' ')}'));
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
    environment: environment,
  );
  if (result.stdout case final String output when output.isNotEmpty) {
    stdout.write(safe(output));
  }
  if (result.stderr case final String output when output.isNotEmpty) {
    stderr.write(safe(output));
  }
  if (result.exitCode != 0) {
    throw StateError(
      '$executable command failed with exit ${result.exitCode}.',
    );
  }
  return _Output(result.stdout as String, result.stderr as String);
}

String _argument(List<String> arguments, String prefix) {
  final values = arguments
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => argument.substring(prefix.length))
      .toList();
  if (values.length != 1 || values.single.trim().isEmpty) {
    throw FormatException('Exactly one $prefix argument is required.');
  }
  return values.single;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?> ||
      value.any((item) => item is! Map<String, Object?>)) {
    throw const FormatException('Expected a JSON object list.');
  }
  return value.cast<Map<String, Object?>>();
}

final class _Output {
  const _Output(this.stdout, this.stderr);

  final String stdout;
  final String stderr;
}

final class _Battery {
  const _Battery(this.level, this.status);

  final int level;
  final String status;
}
