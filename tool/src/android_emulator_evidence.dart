import 'dart:convert';

const androidEvidenceApi = 34;
const androidEvidenceAvd = 'dartitect-api-34';
const androidEvidenceSystemImage =
    'system-images;android-34;google_apis;x86_64';

void requireHostedAndroidEmulatorEnvironment(Map<String, String> environment) {
  if (environment['GITHUB_ACTIONS'] != 'true' ||
      environment['RUNNER_ENVIRONMENT'] != 'github-hosted' ||
      environment['RUNNER_OS'] != 'Linux') {
    throw StateError(
      'Android emulator evidence requires a GitHub-hosted Linux runner.',
    );
  }
  if (environment['DARTITECT_ANDROID_AVD'] != androidEvidenceAvd ||
      environment['DARTITECT_ANDROID_SYSTEM_IMAGE'] !=
          androidEvidenceSystemImage) {
    throw StateError('Android emulator configuration does not match policy.');
  }
}

AndroidEmulatorMetadata validateAndroidEmulator({
  required String requestedId,
  required String apiLevel,
  required String bootCompleted,
  required String qemu,
  required String osVersion,
  required String model,
  required String flutterDevicesJson,
}) {
  final decoded = jsonDecode(flutterDevicesJson);
  if (decoded is! List<Object?> ||
      decoded.any((value) => value is! Map<String, Object?>)) {
    throw const FormatException('Flutter device inventory is invalid.');
  }
  final matches = decoded.cast<Map<String, Object?>>().where(
    (device) =>
        device['id'] == requestedId &&
        '${device['targetPlatform']}'.startsWith('android-'),
  );
  if (matches.length != 1 || matches.single['emulator'] != true) {
    throw StateError('The selected Android target is not the required AVD.');
  }
  if (int.tryParse(apiLevel.trim()) != androidEvidenceApi) {
    throw StateError('Android emulator evidence requires API 34 exactly.');
  }
  if (bootCompleted.trim() != '1' || qemu.trim() != '1') {
    throw StateError('The API 34 Android emulator is not fully booted.');
  }
  if (osVersion.trim().isEmpty || model.trim().isEmpty) {
    throw StateError('Android emulator metadata is incomplete.');
  }
  return AndroidEmulatorMetadata(
    apiLevel: androidEvidenceApi,
    osVersion: osVersion.trim(),
    model: model.trim(),
  );
}

const androidLifecycleOperations = <List<String>>[
  <String>['shell', 'settings', 'get', 'system', 'accelerometer_rotation'],
  <String>['shell', 'settings', 'get', 'system', 'user_rotation'],
  <String>['shell', 'am', 'start', '-a', 'android.settings.SETTINGS'],
  <String>['shell', 'am', 'task', 'lock'],
  <String>['shell', 'am', 'task', 'lock', 'stop'],
];

const androidCleanupOperations = <List<String>>[
  <String>[
    'shell',
    'content',
    'delete',
    '--uri',
    'content://media/external/images/media',
  ],
  <String>['shell', 'pm', 'clear'],
];

const androidShutdownOperation = <String>['emu', 'kill'];

final class AndroidEmulatorMetadata {
  const AndroidEmulatorMetadata({
    required this.apiLevel,
    required this.osVersion,
    required this.model,
  });

  final int apiLevel;
  final String osVersion;
  final String model;
}
