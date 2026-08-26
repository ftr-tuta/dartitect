import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'src/native_evidence_harness.dart';

const _iosApplicationId = 'dev.dartitect.dartitectNativeCapabilitiesHarness';
const _iosLifecycleReadyFile = 'dartitect-ios-lifecycle-ready';
const _iosSuccessFile = 'dartitect-ios-integration-passed';
const _iosFailureFile = 'dartitect-ios-integration-failed';
const _iosStageFile = 'dartitect-ios-integration-stage';
const _iosStages = <String>{
  'lifecycle',
  'att-status',
  'photos-status',
  'photos-status-notSupported',
  'photos-status-notDetermined',
  'photos-status-denied',
  'photos-status-limited',
  'photos-status-after-priming-notDetermined',
  'photos-request',
  'photos-request-pending',
  'photos-request-notSupported',
  'photos-request-notDetermined',
  'photos-request-denied',
  'photos-request-limited',
  'photos-status-after-request',
  'photos-status-after-request-notSupported',
  'photos-status-after-request-notDetermined',
  'photos-status-after-request-denied',
  'photos-status-after-request-limited',
  'save-with-album',
  'missing-file',
  'invalid-file',
  'att-liveness',
  'photos-liveness',
  'complete',
};

Future<void> main(List<String> arguments) async {
  String? simulatorId;
  try {
    simulatorId = Platform.environment['DARTITECT_IOS_SIMULATOR_ID'];
    await _main(arguments);
  } on Object catch (error) {
    final message = simulatorId == null
        ? '$error'
        : '$error'.replaceAll(simulatorId, '<ios-simulator>');
    stderr.writeln(message);
    exitCode = error is FormatException ? 64 : 1;
  }
}

Future<void> _main(List<String> arguments) async {
  final cellId = _argument(arguments, '--cell=');
  if (arguments.length != 1 || !arguments.single.startsWith('--cell=')) {
    throw const FormatException(
      'Usage: dart run tool/run_native_ci_evidence.dart --cell=<ci-cell-id>',
    );
  }
  final environment = Platform.environment;
  if (environment['GITHUB_ACTIONS'] != 'true') {
    throw StateError('CI native receipts require GitHub Actions.');
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final contract = _object(
    jsonDecode(
      File('${root.path}/tool/native_evidence_contract.json')
          .readAsStringSync(),
    ),
  );
  final cell = _objects(contract['requiredCells']).singleWhere(
    (candidate) => candidate['id'] == cellId,
    orElse: () => throw FormatException('Unknown native CI cell: $cellId'),
  );
  if (cell['evidenceKind'] == 'physical') {
    throw const FormatException(
      'Physical evidence cannot be manufactured by a CI runner.',
    );
  }
  final sourceSha = (await _run(root, 'git', const <String>[
    'rev-parse',
    'HEAD',
  ])).stdout.trim();
  final sourceTree = (await _run(root, 'git', const <String>[
    'show',
    '-s',
    '--format=%T',
    'HEAD',
  ])).stdout.trim();
  final githubSha = environment['GITHUB_SHA'];
  if (githubSha != sourceSha) {
    throw StateError('GITHUB_SHA does not match the checked-out source SHA.');
  }
  final dirtyBefore = (await _run(root, 'git', const <String>[
    'status',
    '--porcelain',
    '--untracked-files=all',
  ])).stdout;
  if (dirtyBefore.trim().isNotEmpty) {
    throw StateError('CI native evidence requires a clean source tree.');
  }

  final flutter = _object(
    jsonDecode(
      (await _run(root, 'flutter', const <String>[
        '--version',
        '--machine',
      ])).stdout,
    ),
  );
  final startedAt = DateTime.now().toUtc();
  final temporaryRoot = environment['RUNNER_TEMP'];
  if (temporaryRoot == null || temporaryRoot.trim().isEmpty) {
    throw StateError('RUNNER_TEMP is unavailable.');
  }
  final temporary = await Directory(temporaryRoot)
      .createTemp('dartitect-native-ci-');
  Map<String, String>? environmentReceipt;
  Map<String, String>? versions;
  try {
    switch (cellId) {
      case 'android-media-floor-build':
        if (!Platform.isLinux) {
          throw StateError('Android floor build must run on Linux CI.');
        }
        final consumer = Directory('${temporary.path}/android-floor');
        await _createHost(consumer, const <String>['android']);
        await materializeNativeEvidenceHarness(
          root: root,
          consumer: consumer,
          packages: const <String>{'dartitect_media', 'dartitect_privacy'},
          copyHarnessSources: false,
          copyIntegrationTests: false,
        );
        _setAndroidMinSdk(consumer, 24);
        await _run(consumer, 'flutter', const <String>['pub', 'get']);
        await _run(consumer, 'flutter', const <String>['analyze']);
        await _run(consumer, 'flutter', const <String>[
          'build',
          'apk',
          '--debug',
        ]);
        final gradle = Platform.isWindows ? 'gradlew.bat' : './gradlew';
        await _run(
          Directory('${consumer.path}/android'),
          gradle,
          const <String>['lintDebug', '--no-daemon'],
        );
        versions = <String, String>{
          'os': _linuxOsVersion(),
          'flutter': _exact(flutter['frameworkVersion'], 'Flutter'),
          'dart': _exact(flutter['dartSdkVersion'], 'Dart'),
          'androidSdk': _androidSdkVersion(environment),
          'java': (await _run(root, 'java', const <String>[
            '--version',
          ])).combined.split('\n').first.trim(),
        };
        environmentReceipt = _buildEnvironment(environment);
      case 'ios-media-floor-build':
        final result = await _iosFloor(
          root: root,
          temporary: temporary,
          package: 'dartitect_media',
          floor: '14.0',
        );
        versions = _appleVersions(flutter, result.iosSdk, result.hostOs);
        environmentReceipt = _buildEnvironment(environment);
      case 'ios-privacy-floor-build':
        final result = await _iosFloor(
          root: root,
          temporary: temporary,
          package: 'dartitect_privacy',
          floor: '12.0',
        );
        versions = _appleVersions(flutter, result.iosSdk, result.hostOs);
        environmentReceipt = _buildEnvironment(environment);
      case 'ios-current-simulator':
        final simulator = await _iosSimulator(
          root: root,
          temporary: temporary,
          environment: environment,
        );
        versions = _appleVersions(
          flutter,
          simulator.iosSdk,
          simulator.osVersion,
        )..['photosPermissionTool'] = simulator.photosPermissionToolVersion;
        environmentReceipt = <String, String>{
          'kind': 'simulator',
          'runnerOs': _requiredEnvironment(environment, 'RUNNER_OS'),
          'runnerImage': _runnerImage(environment),
          'deviceModel': simulator.model,
          'deviceIdSha256': sha256
              .convert(utf8.encode(simulator.id))
              .toString(),
        };
      default:
        throw FormatException('Unsupported native CI cell: $cellId');
    }

    final dirtyAfter = (await _run(root, 'git', const <String>[
      'status',
      '--porcelain',
      '--untracked-files=all',
    ])).stdout;
    if (dirtyAfter != dirtyBefore) {
      throw StateError('CI native execution changed the source tree.');
    }
    final receipt = <String, Object?>{
      'schemaVersion': 2,
      'goal': 'V1S-13',
      'cellId': cellId,
      'sourceSha': sourceSha,
      'sourceTree': sourceTree,
      'result': 'passed',
      'platform': cell['platform'],
      'capabilities': cell['capabilities'],
      'evidenceKind': cell['evidenceKind'],
      'versions': versions,
      'environment': environmentReceipt,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceDirty': false,
      'treeClean': true,
      'scenarios': cell['requiredScenarios'],
      'workflow': _workflow(environment, sourceSha),
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
    stdout.writeln('Native CI receipt: ${receiptFile.path}');
  } finally {
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

Future<void> _createHost(Directory consumer, List<String> platforms) async {
  await _run(consumer.parent, 'flutter', <String>[
    'create',
    '--platforms=${platforms.join(',')}',
    '--org=dev.dartitect',
    '--project-name=dartitect_native_capabilities_harness',
    consumer.path,
  ]);
}

Future<_AppleBuild> _iosFloor({
  required Directory root,
  required Directory temporary,
  required String package,
  required String floor,
}) async {
  if (!Platform.isMacOS) {
    throw StateError('iOS floor builds must run on macOS CI.');
  }
  final consumer = Directory('${temporary.path}/$package-floor');
  await _createHost(consumer, const <String>['ios']);
  await materializeNativeEvidenceHarness(
    root: root,
    consumer: consumer,
    packages: <String>{package},
    copyHarnessSources: false,
    copyIntegrationTests: false,
  );
  _setIosAppFloor(consumer, floor == '12.0' ? '13.0' : floor);
  await _run(consumer, 'flutter', const <String>['pub', 'get']);
  await _typecheckIosPlugin(
    root: root,
    temporary: temporary,
    package: package,
    floor: floor,
  );
  await _run(consumer, 'flutter', const <String>[
    'build',
    'ios',
    '--simulator',
    '--no-codesign',
  ]);
  return _AppleBuild(
    iosSdk: (await _run(root, 'xcrun', const <String>[
      '--sdk',
      'iphonesimulator',
      '--show-sdk-version',
    ])).stdout.trim(),
    hostOs: (await _run(root, 'sw_vers', const <String>[
      '-productVersion',
    ])).stdout.trim(),
  );
}

Future<void> _typecheckIosPlugin({
  required Directory root,
  required Directory temporary,
  required String package,
  required String floor,
}) async {
  final flutterExecutable = (await _run(root, 'which', const <String>[
    'flutter',
  ])).stdout.trim();
  final flutterSdk = File(flutterExecutable).resolveSymbolicLinksSync();
  final sdkRoot = File(flutterSdk).parent.parent;
  final frameworkRoot = Directory(
    '${sdkRoot.path}/bin/cache/artifacts/engine/ios/Flutter.xcframework',
  );
  if (!frameworkRoot.existsSync()) {
    throw StateError('Flutter iOS engine framework is unavailable.');
  }
  final simulatorFrameworks = frameworkRoot
      .listSync(followLinks: false)
      .whereType<Directory>()
      .where((directory) => directory.path.contains('simulator'))
      .toList();
  if (simulatorFrameworks.length != 1 ||
      !Directory('${simulatorFrameworks.single.path}/Flutter.framework')
          .existsSync()) {
    throw StateError('Flutter simulator framework is unavailable.');
  }
  final sdk = (await _run(root, 'xcrun', const <String>[
    '--sdk',
    'iphonesimulator',
    '--show-sdk-path',
  ])).stdout.trim();
  final plugin = package == 'dartitect_media'
      ? 'packages/dartitect_media/ios/Classes/DartitectMediaPlugin.swift'
      : 'packages/dartitect_privacy/ios/Classes/DartitectPrivacyPlugin.swift';
  await _run(root, 'xcrun', <String>[
    'swiftc',
    '-typecheck',
    '-sdk',
    sdk,
    '-target',
    'arm64-apple-ios$floor-simulator',
    '-F',
    simulatorFrameworks.single.path,
    '-module-cache-path',
    '${temporary.path}/swift-module-cache-$package',
    '${root.path}/$plugin',
  ]);
}

Future<_SimulatorBuild> _iosSimulator({
  required Directory root,
  required Directory temporary,
  required Map<String, String> environment,
}) async {
  if (!Platform.isMacOS) {
    throw StateError('iOS simulator evidence must run on macOS CI.');
  }
  final id = _requiredEnvironment(environment, 'DARTITECT_IOS_SIMULATOR_ID');
  final model = _requiredEnvironment(
    environment,
    'DARTITECT_IOS_SIMULATOR_MODEL',
  );
  final osVersion = _requiredEnvironment(
    environment,
    'DARTITECT_IOS_SIMULATOR_OS',
  );
  final photosPermissionTool = _requiredEnvironment(
    environment,
    'DARTITECT_APPLESIMUTILS',
  );
  final photosPermissionToolVersion = (await _run(
    root,
    photosPermissionTool,
    const <String>['--version'],
  )).stdout.trim();
  if (photosPermissionToolVersion != 'applesimutils version 0.9.12') {
    throw StateError('AppleSimulatorUtils 0.9.12 is required.');
  }
  final consumer = Directory('${temporary.path}/ios-current');
  await _createHost(consumer, const <String>['ios']);
  await materializeNativeEvidenceHarness(
    root: root,
    consumer: consumer,
    packages: const <String>{'dartitect_media', 'dartitect_privacy'},
    copyIosNativeTests: true,
  );
  _setIosAppFloor(consumer, '14.0');
  _setIosUsageDescriptions(consumer);
  await _run(consumer, 'flutter', const <String>['pub', 'get']);
  await _run(root, 'xcrun', <String>[
    'simctl',
    'bootstatus',
    id,
    '-b',
  ], redact: id);
  try {
    await _run(consumer, 'flutter', const <String>[
      'build',
      'ios',
      '--simulator',
      '--no-codesign',
    ]);
    await _run(consumer, 'xcodebuild', <String>[
      'test',
      '-workspace',
      'ios/Runner.xcworkspace',
      '-scheme',
      'Runner',
      '-configuration',
      'Debug',
      '-destination',
      'id=$id',
      'CODE_SIGNING_ALLOWED=NO',
    ], redact: id);
    await _run(
      root,
      'xcrun',
      <String>['simctl', 'boot', id],
      redact: id,
      allowFailure: true,
    );
    await _run(root, 'xcrun', <String>[
      'simctl',
      'bootstatus',
      id,
      '-b',
    ], redact: id);
    await _runIosStandaloneIntegration(
      consumer,
      id,
      root,
      photosPermissionTool,
    );
    return _SimulatorBuild(
      id: id,
      model: model,
      osVersion: osVersion,
      iosSdk: (await _run(root, 'xcrun', const <String>[
        '--sdk',
        'iphonesimulator',
        '--show-sdk-version',
      ])).stdout.trim(),
      photosPermissionToolVersion: 'applesimutils 0.9.12',
    );
  } finally {
    await _run(
      root,
      'xcrun',
      <String>['simctl', 'uninstall', id, _iosApplicationId],
      redact: id,
      allowFailure: true,
    );
    await _run(
      root,
      'xcrun',
      <String>['simctl', 'shutdown', id],
      redact: id,
      allowFailure: true,
    );
    await _run(root, 'xcrun', <String>['simctl', 'erase', id], redact: id);
  }
}

Future<void> _runIosStandaloneIntegration(
  Directory consumer,
  String simulatorId,
  Directory root,
  String photosPermissionTool,
) async {
  await _run(consumer, 'flutter', const <String>[
    'build',
    'ios',
    '--simulator',
    '--no-codesign',
    '--target=lib/ios_ci_harness.dart',
  ]);
  final app = '${consumer.path}/build/ios/iphonesimulator/Runner.app';
  await _run(root, 'xcrun', <String>[
    'simctl',
    'install',
    simulatorId,
    app,
  ], redact: simulatorId);
  // Warm Settings before the timed lifecycle scenario. Its first launch on a
  // freshly booted hosted simulator can otherwise take several minutes.
  await _run(root, 'xcrun', <String>[
    'simctl',
    'launch',
    simulatorId,
    'com.apple.Preferences',
  ], redact: simulatorId);
  await _run(root, 'xcrun', <String>[
    'simctl',
    'launch',
    '--terminate-running-process',
    simulatorId,
    _iosApplicationId,
  ], redact: simulatorId);
  // Register the installed application with the runtime before changing TCC.
  // The harness writes its lifecycle signal before it invokes either channel,
  // so this first launch cannot prompt or consume formal capability evidence.
  final registrationReady = await _waitForIosSentinel(
    root,
    simulatorId,
    _iosLifecycleReadyFile,
  );
  await _run(root, 'xcrun', <String>[
    'simctl',
    'terminate',
    simulatorId,
    _iosApplicationId,
  ], redact: simulatorId);
  await _clearIosSignals(registrationReady.parent);
  await _resetIosPhotos(root, simulatorId, photosPermissionTool);
  await _grantIosPhotos(root, simulatorId, photosPermissionTool);
  await _run(root, 'xcrun', <String>[
    'simctl',
    'launch',
    '--terminate-running-process',
    simulatorId,
    _iosApplicationId,
  ], redact: simulatorId);
  final lifecycleReady = await _waitForIosSentinel(
    root,
    simulatorId,
    _iosLifecycleReadyFile,
  );
  await _exerciseIosLifecycle(root, simulatorId);
  if (lifecycleReady.existsSync()) await lifecycleReady.delete();
  await _waitForIosIntegrationResult(root, simulatorId, photosPermissionTool);
}

Future<void> _clearIosSignals(Directory temporary) async {
  for (final name in const <String>[
    _iosLifecycleReadyFile,
    _iosSuccessFile,
    _iosFailureFile,
    _iosStageFile,
  ]) {
    final signal = File('${temporary.path}/$name');
    if (signal.existsSync()) await signal.delete();
  }
}

Future<File> _waitForIosSentinel(
  Directory root,
  String simulatorId,
  String name,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    final result = await Process.run('xcrun', <String>[
      'simctl',
      'get_app_container',
      simulatorId,
      _iosApplicationId,
      'data',
    ], workingDirectory: root.path);
    if (result.exitCode == 0) {
      final container = (result.stdout as String).trim();
      if (container.isNotEmpty) {
        final sentinel = File('$container/tmp/$name');
        if (sentinel.existsSync()) return sentinel;
        final failure = File('$container/tmp/$_iosFailureFile');
        if (failure.existsSync()) {
          final stage = _iosFailureStage(container);
          throw StateError(
            'iOS standalone integration failed before lifecycle readiness '
            'at allowlisted stage $stage.',
          );
        }
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Timed out waiting for the iOS $name signal.');
}

Future<void> _waitForIosIntegrationResult(
  Directory root,
  String simulatorId,
  String photosPermissionTool,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var restartedAfterPendingPhotosRequest = false;
  while (DateTime.now().isBefore(deadline)) {
    final success = await _iosContainerFile(root, simulatorId, _iosSuccessFile);
    if (success?.existsSync() ?? false) return;
    final failure = await _iosContainerFile(root, simulatorId, _iosFailureFile);
    if (failure?.existsSync() ?? false) {
      final container = failure!.parent.parent.path;
      final stage = _iosFailureStage(container);
      throw StateError(
        'iOS standalone integration reported failure at allowlisted stage '
        '$stage.',
      );
    }
    final stage = await _iosContainerFile(root, simulatorId, _iosStageFile);
    if (!restartedAfterPendingPhotosRequest &&
        (stage?.existsSync() ?? false) &&
        stage!.readAsStringSync().trim() == 'photos-request-pending') {
      // A pending real PhotoKit request means the pre-authorization was not
      // materialized. Terminate the prompted process, apply the same pinned
      // host-side grant again, and relaunch. The persisted priming marker makes
      // the second process require authorized status and a completed public
      // request before it can emit the success sentinel.
      await Future<void>.delayed(const Duration(seconds: 3));
      await _run(
        root,
        'xcrun',
        <String>['simctl', 'terminate', simulatorId, _iosApplicationId],
        redact: simulatorId,
        allowFailure: true,
      );
      await _grantIosPhotos(root, simulatorId, photosPermissionTool);
      await _run(root, 'xcrun', <String>[
        'simctl',
        'launch',
        '--terminate-running-process',
        simulatorId,
        _iosApplicationId,
      ], redact: simulatorId);
      restartedAfterPendingPhotosRequest = true;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  final stageFile = await _iosContainerFile(root, simulatorId, _iosStageFile);
  final stage = stageFile == null
      ? 'unknown'
      : _iosFailureStage(stageFile.parent.parent.path);
  throw StateError(
    'Timed out waiting for iOS standalone integration at allowlisted stage '
    '$stage.',
  );
}

String _iosFailureStage(String container) {
  final stageFile = File('$container/tmp/$_iosStageFile');
  if (!stageFile.existsSync()) return 'unknown';
  final stage = stageFile.readAsStringSync().trim();
  return _iosStages.contains(stage) ? stage : 'unknown';
}

Future<File?> _iosContainerFile(
  Directory root,
  String simulatorId,
  String name,
) async {
  final result = await Process.run('xcrun', <String>[
    'simctl',
    'get_app_container',
    simulatorId,
    _iosApplicationId,
    'data',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) return null;
  final container = (result.stdout as String).trim();
  return container.isEmpty ? null : File('$container/tmp/$name');
}

Future<void> _grantIosPhotos(
  Directory root,
  String simulatorId,
  String photosPermissionTool,
) async {
  // The plugin deliberately uses PHAccessLevel.readWrite because album lookup
  // and creation cannot be validated with add-only access. simctl privacy can
  // write a Photos TCC row that modern PhotoKit still reads as notDetermined,
  // so the CI runner uses the checksum-pinned AppleSimulatorUtils host tool.
  // This grant is only setup: the harness must still observe authorized via
  // .readWrite, complete the public request, and save through the real channel.
  await _run(root, photosPermissionTool, <String>[
    '--byId',
    simulatorId,
    '--bundle',
    _iosApplicationId,
    '--setPermissions',
    'photos=YES',
  ], redact: simulatorId);
}

Future<void> _resetIosPhotos(
  Directory root,
  String simulatorId,
  String photosPermissionTool,
) async {
  await _run(root, photosPermissionTool, <String>[
    '--byId',
    simulatorId,
    '--bundle',
    _iosApplicationId,
    '--setPermissions',
    'photos=unset',
  ], redact: simulatorId);
}

Future<void> _exerciseIosLifecycle(Directory root, String simulatorId) async {
  await _run(root, 'xcrun', <String>[
    'simctl',
    'launch',
    simulatorId,
    'com.apple.Preferences',
  ], redact: simulatorId);
  await Future<void>.delayed(const Duration(seconds: 2));
  await _run(root, 'xcrun', <String>[
    'simctl',
    'launch',
    simulatorId,
    _iosApplicationId,
  ], redact: simulatorId);
  await Future<void>.delayed(const Duration(seconds: 2));
}

void _setAndroidMinSdk(Directory consumer, int floor) {
  final candidates = <File>[
    File('${consumer.path}/android/app/build.gradle.kts'),
    File('${consumer.path}/android/app/build.gradle'),
  ];
  final file = candidates.firstWhere(
    (candidate) => candidate.existsSync(),
    orElse: () => throw StateError('Generated Android build file is missing.'),
  );
  var source = file.readAsStringSync();
  source = source
      .replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = $floor')
      .replaceAll(
        'minSdkVersion flutter.minSdkVersion',
        'minSdkVersion $floor',
      );
  if (!RegExp('minSdk(?:Version|\\s*=)\\s*$floor').hasMatch(source)) {
    throw StateError('Could not pin generated Android minSdk $floor.');
  }
  file.writeAsStringSync(source);
}

void _setIosAppFloor(Directory consumer, String floor) {
  final project = File('${consumer.path}/ios/Runner.xcodeproj/project.pbxproj');
  var source = project.readAsStringSync();
  source = source.replaceAll(
    RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;'),
    'IPHONEOS_DEPLOYMENT_TARGET = $floor;',
  );
  project.writeAsStringSync(source);
  final podfile = File('${consumer.path}/ios/Podfile');
  if (podfile.existsSync()) {
    var pods = podfile.readAsStringSync();
    if (RegExp(r'^#?\s*platform :ios', multiLine: true).hasMatch(pods)) {
      pods = pods.replaceFirst(
        RegExp(r'^#?\s*platform :ios[^\n]*', multiLine: true),
        "platform :ios, '$floor'",
      );
    } else {
      pods = "platform :ios, '$floor'\n$pods";
    }
    podfile.writeAsStringSync(pods);
  }
}

void _setIosUsageDescriptions(Directory consumer) {
  final plist = File('${consumer.path}/ios/Runner/Info.plist');
  var source = plist.readAsStringSync();
  const entries = '''
\t<key>NSPhotoLibraryUsageDescription</key>
\t<string>Dartitect native evidence reads the simulator photo library.</string>
\t<key>NSPhotoLibraryAddUsageDescription</key>
\t<string>Dartitect native evidence saves one identified test image.</string>
\t<key>NSUserTrackingUsageDescription</key>
\t<string>Dartitect native evidence validates explicit ATT status.</string>
''';
  source = source.replaceFirst('</dict>', '$entries</dict>');
  plist.writeAsStringSync(source);
}

Map<String, String> _appleVersions(
  Map<String, Object?> flutter,
  String iosSdk,
  String os,
) => <String, String>{
  'os': _exact(os, 'Apple OS'),
  'flutter': _exact(flutter['frameworkVersion'], 'Flutter'),
  'dart': _exact(flutter['dartSdkVersion'], 'Dart'),
  'xcode': _xcodeVersion(),
  'iosSdk': _exact(iosSdk, 'iOS SDK'),
};

String _xcodeVersion() {
  final result = Process.runSync('xcodebuild', const <String>['-version']);
  if (result.exitCode != 0) throw StateError('xcodebuild -version failed.');
  return (result.stdout as String).trim().replaceAll('\n', ' / ');
}

Map<String, String> _buildEnvironment(Map<String, String> environment) =>
    <String, String>{
      'kind': 'build',
      'runnerOs': _requiredEnvironment(environment, 'RUNNER_OS'),
      'runnerImage': _runnerImage(environment),
    };

Map<String, Object?> _workflow(
  Map<String, String> environment,
  String sourceSha,
) {
  final repository = _requiredEnvironment(environment, 'GITHUB_REPOSITORY');
  final runId = int.parse(_requiredEnvironment(environment, 'GITHUB_RUN_ID'));
  return <String, Object?>{
    'workflow': _requiredEnvironment(environment, 'GITHUB_WORKFLOW'),
    'runId': runId,
    'runAttempt': int.parse(
      _requiredEnvironment(environment, 'GITHUB_RUN_ATTEMPT'),
    ),
    'repository': repository,
    'event': _requiredEnvironment(environment, 'GITHUB_EVENT_NAME'),
    'url': 'https://github.com/$repository/actions/runs/$runId',
    'sourceSha': sourceSha,
  };
}

String _runnerImage(Map<String, String> environment) {
  final os = environment['ImageOS'];
  final version = environment['ImageVersion'];
  if (os == null ||
      os.trim().isEmpty ||
      version == null ||
      version.trim().isEmpty) {
    throw StateError('GitHub runner image version is unavailable.');
  }
  return '$os/$version';
}

String _linuxOsVersion() {
  final release = File('/etc/os-release');
  if (!release.existsSync())
    throw StateError('Linux OS release is unavailable.');
  for (final line in release.readAsLinesSync()) {
    if (line.startsWith('PRETTY_NAME=')) {
      return line.substring('PRETTY_NAME='.length).replaceAll('"', '');
    }
  }
  throw StateError('Linux exact OS version is unavailable.');
}

String _androidSdkVersion(Map<String, String> environment) {
  final root = environment['ANDROID_SDK_ROOT'] ?? environment['ANDROID_HOME'];
  if (root == null || root.trim().isEmpty) {
    throw StateError('Android SDK root is unavailable.');
  }
  String latest(String directory, String prefix) {
    final values =
        Directory('$root/$directory')
            .listSync(followLinks: false)
            .whereType<Directory>()
            .map(
              (item) =>
                  item.uri.pathSegments.where((part) => part.isNotEmpty).last,
            )
            .where((name) => name.startsWith(prefix))
            .toList()
          ..sort();
    if (values.isEmpty) {
      throw StateError('Android SDK $directory inventory is empty.');
    }
    return values.last;
  }

  return '${latest('platforms', 'android-')}/'
      '${latest('build-tools', '')}';
}

String _requiredEnvironment(Map<String, String> environment, String key) {
  final value = environment[key];
  if (value == null || value.trim().isEmpty) {
    throw StateError('Required CI environment $key is unavailable.');
  }
  return value;
}

String _exact(Object? value, String name) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') {
    throw StateError('$name exact version is unavailable.');
  }
  return text;
}

Future<_Output> _run(
  Directory workingDirectory,
  String executable,
  List<String> arguments, {
  String? redact,
  bool allowFailure = false,
}) async {
  String safe(String value) =>
      redact == null ? value : value.replaceAll(redact, '<ios-simulator>');
  stdout.writeln(safe('> $executable ${arguments.join(' ')}'));
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  );
  final output = result.stdout as String;
  final error = result.stderr as String;
  if (output.isNotEmpty) stdout.write(safe(output));
  if (error.isNotEmpty) stderr.write(safe(error));
  if (result.exitCode != 0 && !allowFailure) {
    throw StateError(
      '$executable command failed with exit ${result.exitCode}.',
    );
  }
  return _Output(output, error);
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

  String get combined => '$stdout\n$stderr';
}

final class _AppleBuild {
  const _AppleBuild({required this.iosSdk, required this.hostOs});

  final String iosSdk;
  final String hostOs;
}

final class _SimulatorBuild {
  const _SimulatorBuild({
    required this.id,
    required this.model,
    required this.osVersion,
    required this.iosSdk,
    required this.photosPermissionToolVersion,
  });

  final String id;
  final String model;
  final String osVersion;
  final String iosSdk;
  final String photosPermissionToolVersion;
}
