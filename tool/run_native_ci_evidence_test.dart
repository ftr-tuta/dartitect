import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'src/android_emulator_evidence.dart';

void main() {
  test('requires the exact hosted API 34 AVD configuration', () {
    expect(
      () => requireHostedAndroidEmulatorEnvironment(const <String, String>{
        'GITHUB_ACTIONS': 'true',
        'RUNNER_ENVIRONMENT': 'github-hosted',
        'RUNNER_OS': 'Linux',
        'DARTITECT_ANDROID_AVD': androidEvidenceAvd,
        'DARTITECT_ANDROID_SYSTEM_IMAGE': androidEvidenceSystemImage,
      }),
      returnsNormally,
    );
    expect(
      () => requireHostedAndroidEmulatorEnvironment(const <String, String>{
        'GITHUB_ACTIONS': 'true',
        'RUNNER_ENVIRONMENT': 'self-hosted',
        'RUNNER_OS': 'Linux',
      }),
      throwsStateError,
    );
  });

  test('accepts only one fully booted API 34 emulator', () {
    final metadata = validateAndroidEmulator(
      requestedId: 'emulator-5554',
      apiLevel: '34',
      bootCompleted: '1',
      qemu: '1',
      osVersion: '14',
      model: 'sdk_gphone_x86_64',
      flutterDevicesJson: jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'emulator-5554',
          'name': 'Android SDK built for x86_64',
          'targetPlatform': 'android-x64',
          'emulator': true,
        },
      ]),
    );
    expect(metadata.apiLevel, 34);
    expect(
      () => validateAndroidEmulator(
        requestedId: 'emulator-5554',
        apiLevel: '33',
        bootCompleted: '1',
        qemu: '1',
        osVersion: '13',
        model: 'fixture',
        flutterDevicesJson: '[]',
      ),
      throwsStateError,
    );
  });

  test(
    'runner contract includes lifecycle, media/data cleanup, and shutdown',
    () {
      expect(
        androidLifecycleOperations.expand((operation) => operation),
        containsAll(<String>['settings', 'android.settings.SETTINGS', 'focus']),
      );
      expect(
        androidCleanupOperations.expand((operation) => operation),
        containsAll(<String>['content', 'delete', 'pm', 'clear']),
      );
      expect(androidShutdownOperation, <String>['emu', 'kill']);

      final integration = File(
        'tool/canaries/native_capabilities/integration_test/'
        'android_media_test.dart',
      ).readAsStringSync();
      for (final marker in const <String>[
        'DARTITECT_LIFECYCLE_READY',
        'MethodChannelGalleryMediaService',
        'saveImage',
        'image.existsSync()',
        'missing.png',
        'GalleryFileNotFoundFailure',
        'GalleryInvalidFileFailure',
        'clearOwnedState',
      ]) {
        expect(integration, contains(marker));
      }

      final runner = File('tool/run_native_ci_evidence.dart')
          .readAsStringSync();
      for (final marker in const <String>[
        '--reporter=expanded',
        '_cleanupAndroidTestAssets',
        '_androidTestAssetsAreAbsent',
        '_applicationDataIsClean',
        'androidShutdownOperation',
      ]) {
        expect(runner, contains(marker));
      }
      expect(runner, isNot(contains("'user-rotation'")));
    },
  );
}
