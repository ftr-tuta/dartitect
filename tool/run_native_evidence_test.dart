import 'dart:io';

import 'package:test/test.dart';

import 'src/native_evidence_device.dart';

void main() {
  group('isolated ADB socket', () {
    test('rejects a missing socket before any device query', () async {
      final result = await _runner(const <String, String>{});
      expect(result.exitCode, 1);
      expect(result.stderr, contains('ADB_SERVER_SOCKET is required'));
    });

    test('rejects the default or any incorrect socket', () async {
      final result = await _runner(const <String, String>{
        'ADB_SERVER_SOCKET': 'tcp:127.0.0.1:5037',
      });
      expect(result.exitCode, 1);
      expect(result.stderr, contains(requiredAdbServerSocket));
    });

    test('propagates only the required isolated socket', () {
      final environment = nativeEvidenceEnvironment(const <String, String>{
        'PATH': '/test',
        'ADB_SERVER_SOCKET': requiredAdbServerSocket,
      });
      expect(environment['PATH'], '/test');
      expect(environment['ADB_SERVER_SOCKET'], requiredAdbServerSocket);
    });
  });

  group('physical Android selection', () {
    test('rejects offline and unauthorized devices', () {
      for (final state in const <String>['offline', 'unauthorized']) {
        expect(
          () => selectPhysicalAndroidDevice(
            requestedId: 'private-id',
            adbDevicesOutput:
                'List of devices attached\nprivate-id\t$state product:test\n',
            flutterDevices: <Map<String, Object?>>[],
          ),
          throwsA(
            isA<StateError>().having(
              (error) => '$error',
              'message',
              contains(state),
            ),
          ),
        );
      }
    });

    test('rejects multiple connected devices', () {
      expect(
        () => selectPhysicalAndroidDevice(
          requestedId: 'private-id',
          adbDevicesOutput:
              'List of devices attached\nprivate-id\tdevice\nother\tdevice\n',
          flutterDevices: <Map<String, Object?>>[],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('Exactly one device'),
          ),
        ),
      );
    });

    test('rejects an emulator even when it is the only device', () {
      expect(
        () => selectPhysicalAndroidDevice(
          requestedId: 'private-id',
          adbDevicesOutput:
              'List of devices attached\nprivate-id\tdevice product:test\n',
          flutterDevices: <Map<String, Object?>>[
            <String, Object?>{
              'id': 'private-id',
              'name': 'Emulator',
              'sdk': 'Android 14',
              'targetPlatform': 'android-arm64',
              'emulator': true,
            },
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('emulators are forbidden'),
          ),
        ),
      );
    });

    test('accepts one physical selection and never exposes its identifier', () {
      const identifier = 'sensitive-physical-id';
      final selected = selectPhysicalAndroidDevice(
        requestedId: identifier,
        adbDevicesOutput:
            'List of devices attached\n$identifier\tdevice product:test\n',
        flutterDevices: <Map<String, Object?>>[
          <String, Object?>{
            'id': identifier,
            'name': 'Redmi Note 10S',
            'sdk': 'Android 14 (API 34)',
            'targetPlatform': 'android-arm64',
            'emulator': false,
          },
        ],
      );
      expect(selected.idSha256, hasLength(64));
      expect(selected.idSha256, isNot(contains(identifier)));
      expect(
        redactDeviceId('device=$identifier', identifier),
        'device=<physical-device>',
      );
    });

    test('requires API 34 exactly', () {
      expect(() => requireAndroidApi34(33), throwsStateError);
      expect(() => requireAndroidApi34(35), throwsStateError);
      expect(() => requireAndroidApi34(34), returnsNormally);
    });
  });
}

Future<ProcessResult> _runner(Map<String, String> environment) {
  final script = File(
    '${Directory.current.path}/tool/run_native_evidence.dart',
  );
  return Process.run(
    Platform.resolvedExecutable,
    <String>[
      script.path,
      '--cell=android-media-current-physical',
      '--device=private-id',
    ],
    workingDirectory: Directory.current.path,
    environment: <String, String>{
      'DARTITECT_NATIVE_EVIDENCE_TEST': '1',
      ...environment,
    },
    includeParentEnvironment: false,
  );
}
