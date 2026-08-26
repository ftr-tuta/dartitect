import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final cellId = _requiredArgument(arguments, '--cell=');
  final deviceId = _requiredArgument(arguments, '--device=');
  if (arguments.length != 2 ||
      arguments.any(
        (argument) =>
            !argument.startsWith('--cell=') &&
            !argument.startsWith('--device='),
      )) {
    stderr.writeln(
      'Usage: dart run tool/run_native_evidence.dart '
      '--cell=<cell-id> --device=<flutter-device-id>',
    );
    exitCode = 64;
    return;
  }
  if (cellId != 'android-media-current-emulator') {
    stderr.writeln(
      'Automated local execution currently supports '
      'android-media-current-emulator; $cellId still requires its declared '
      'floor/physical/iOS environment.',
    );
    exitCode = 69;
    return;
  }

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
  ])).stdout.trim();
  final dirtyBefore = (await _run(root, 'git', const <String>[
    'status',
    '--porcelain',
    '--untracked-files=no',
  ])).stdout;
  if (dirtyBefore.trim().isNotEmpty) {
    throw StateError(
      'Commit or revert tracked changes before device evidence.',
    );
  }

  final flutter = _object(
    jsonDecode(
      (await _run(root, 'flutter', const <String>[
        '--version',
        '--machine',
      ])).stdout,
    ),
  );
  final devices = _objects(
    jsonDecode(
      (await _run(root, 'flutter', const <String>[
        'devices',
        '--machine',
      ])).stdout,
    ),
  );
  final device = devices.singleWhere(
    (candidate) => candidate['id'] == deviceId,
    orElse: () =>
        throw StateError('Flutter device is not connected: $deviceId'),
  );
  if (device['emulator'] != true ||
      !'${device['targetPlatform']}'.startsWith('android-')) {
    throw StateError('$deviceId is not an Android emulator.');
  }

  final adb = await _adb(root, deviceId);
  final apiLevel = int.parse(
    (await adb.run(const <String>['shell', 'getprop', 'ro.build.version.sdk']))
        .trim(),
  );
  if (apiLevel <= 24) {
    throw StateError('The current Android cell must run above API 24.');
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
  final startedAt = DateTime.now().toUtc();
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-native-evidence-',
  );
  try {
    final consumer = Directory('${temporary.path}/consumer');
    await _run(temporary, 'flutter', <String>[
      'create',
      '--platforms=android,ios',
      '--org=dev.dartitect',
      '--project-name=dartitect_native_capabilities_harness',
      consumer.path,
    ]);
    await _materializeHarness(root, consumer);
    await _run(consumer, 'flutter', const <String>['pub', 'get']);
    final lifecycle = Completer<void>();
    final process = await Process.start('flutter', <String>[
      'test',
      'integration_test/android_media_test.dart',
      '-d',
      deviceId,
      '--dart-define=DARTITECT_ANDROID_API=$apiLevel',
      '--dart-define=DARTITECT_EXERCISE_LIFECYCLE=true',
    ], workingDirectory: consumer.path);
    var lifecycleTriggered = false;
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          stdout.writeln(line);
          if (!lifecycleTriggered &&
              line.contains('DARTITECT_LIFECYCLE_READY')) {
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
        .forEach(stderr.writeln);
    final result = await process.exitCode;
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    if (!lifecycleTriggered) {
      throw StateError('Integration test did not request lifecycle exercise.');
    }
    await lifecycle.future;
    if (result != 0) {
      throw ProcessException(
        'flutter',
        const <String>['test', 'integration_test/android_media_test.dart'],
        'Native integration test failed.',
        result,
      );
    }
    await _cleanupAndroidTestAssets(adb);

    final dirtyAfter = (await _run(root, 'git', const <String>[
      'status',
      '--porcelain',
      '--untracked-files=no',
    ])).stdout;
    if (dirtyAfter != dirtyBefore) {
      throw StateError('Native execution changed the tracked project tree.');
    }
    final receipt = <String, Object?>{
      'schemaVersion': 1,
      'goal': 'V1S-13',
      'cellId': cellId,
      'sourceSha': sourceSha,
      'result': 'passed',
      'platform': 'android',
      'capability': 'media',
      'deviceKind': 'emulator',
      'osVersion': osVersion,
      'apiLevel': apiLevel,
      'sdkVersion': '${device['sdk']}',
      'flutterVersion': '${flutter['frameworkVersion']}',
      'dartVersion': '${flutter['dartSdkVersion']}',
      'deviceModel': '$manufacturer $model'.trim(),
      'deviceIdSha256': sha256.convert(utf8.encode(deviceId)).toString(),
      'startedAt': startedAt.toIso8601String(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceDirty': false,
      'treeClean': true,
      'scenarios': cell['requiredScenarios'],
      'commands': <String>[
        'flutter create --platforms=android,ios <temporary-consumer>',
        'flutter pub get',
        'flutter test integration_test/android_media_test.dart -d <device>',
        'adb shell am start -a android.settings.SETTINGS',
        'adb shell am task lock <instrumented-task-id>',
        'adb shell am task lock stop',
      ],
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
    stdout.writeln('Native evidence receipt: ${receiptFile.path}');
  } finally {
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

Future<void> _materializeHarness(Directory root, Directory consumer) async {
  final path = (String package) => jsonEncode(
    '${root.path}/packages/$package'.replaceAll(Platform.pathSeparator, '/'),
  );
  await File('${consumer.path}/pubspec.yaml').writeAsString('''
name: dartitect_native_capabilities_harness
description: Ephemeral V1S-13 native device harness.
version: 0.0.0
publish_to: none

environment:
  sdk: ^3.13.0
  flutter: '>=3.47.1'

dependencies:
  dartitect:
    path: ${path('dartitect')}
  dartitect_media:
    path: ${path('dartitect_media')}
  dartitect_privacy:
    path: ${path('dartitect_privacy')}
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

dependency_overrides:
  dartitect:
    path: ${path('dartitect')}

flutter:
  uses-material-design: true
''');
  final source = Directory('${root.path}/tool/canaries/native_capabilities');
  await _copyDirectory(
    Directory('${source.path}/lib'),
    Directory('${consumer.path}/lib'),
  );
  await _copyDirectory(
    Directory('${source.path}/integration_test'),
    Directory('${consumer.path}/integration_test'),
  );
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}/$relative';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}

Future<void> _exerciseAndroidLifecycle(_Adb adb) async {
  const application = 'dev.dartitect.dartitect_native_capabilities_harness';
  final taskId = await _resumedTaskId(adb, application);
  await adb.run(const <String>[
    'shell',
    'am',
    'start',
    '-a',
    'android.settings.SETTINGS',
  ]);
  await Future<void>.delayed(const Duration(seconds: 2));
  await adb.run(<String>['shell', 'am', 'task', 'lock', '$taskId']);
  try {
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
              line.contains(application),
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
      if (taskId == null) break;
      return taskId;
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

Future<_Adb> _adb(Directory root, String deviceId) async {
  final sdkRoots = <String>{
    for (final key in const <String>['ANDROID_SDK_ROOT', 'ANDROID_HOME'])
      if (Platform.environment[key] case final value?
          when value.trim().isNotEmpty)
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
      final result = await Process.run(executable, const <String>['version']);
      if (result.exitCode == 0) return _Adb(root, executable, deviceId);
    } on ProcessException {
      // Try the next explicit SDK root or the PATH fallback.
    }
  }
  throw StateError(
    'adb is unavailable; configure ANDROID_SDK_ROOT/ANDROID_HOME or PATH.',
  );
}

final class _Adb {
  const _Adb(this.root, this.executable, this.deviceId);

  final Directory root;
  final String executable;
  final String deviceId;

  Future<String> run(
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    final result = await Process.run(executable, <String>[
      '-s',
      deviceId,
      ...arguments,
    ], workingDirectory: root.path);
    if (result.exitCode != 0 && !allowFailure) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    return result.stdout as String;
  }
}

Future<_Output> _run(
  Directory workingDirectory,
  String executable,
  List<String> arguments,
) async {
  stdout.writeln('> $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  if (result.stdout case final String output when output.isNotEmpty) {
    stdout.write(output);
  }
  if (result.stderr case final String output when output.isNotEmpty) {
    stderr.write(output);
  }
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
  return _Output(result.stdout as String, result.stderr as String);
}

String _requiredArgument(List<String> arguments, String prefix) {
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
