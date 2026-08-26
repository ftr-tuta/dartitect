import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.dartitect/privacy.test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('construction never reads status or requests automatically', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return 'authorized';
        });

    final service = MethodChannelTrackingAuthorizationService(
      channel: channel,
      platform: TargetPlatform.iOS,
      isWeb: false,
    );
    expect(calls, isEmpty);
    expect(await service.status(), TrackingAuthorizationStatus.authorized);
    expect(await service.request(), TrackingAuthorizationStatus.authorized);
    expect(calls, <String>['status', 'request']);
  });

  test('non-iOS and web return notSupported without channel calls', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls += 1;
          return 'authorized';
        });
    final cases = <(TargetPlatform, bool)>[
      (TargetPlatform.android, false),
      (TargetPlatform.linux, false),
      (TargetPlatform.macOS, false),
      (TargetPlatform.windows, false),
      (TargetPlatform.fuchsia, false),
      (TargetPlatform.iOS, true),
    ];
    for (final (platform, isWeb) in cases) {
      final service = MethodChannelTrackingAuthorizationService(
        channel: channel,
        platform: platform,
        isWeb: isWeb,
      );
      expect(
        await service.status(),
        TrackingAuthorizationStatus.notSupported,
        reason: '$platform web=$isWeb',
      );
      expect(
        await service.request(),
        TrackingAuthorizationStatus.notSupported,
        reason: '$platform web=$isWeb',
      );
    }
    expect(calls, 0);
  });

  test('preserves every native ATT status', () async {
    for (final status in TrackingAuthorizationStatus.values) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => status.name);
      final service = MethodChannelTrackingAuthorizationService(
        channel: channel,
        platform: TargetPlatform.iOS,
        isWeb: false,
      );
      expect(await service.status(), status);
    }
  });

  test('rejects unknown native status without retaining payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'futureStatus');
    final service = MethodChannelTrackingAuthorizationService(
      channel: channel,
      platform: TargetPlatform.iOS,
      isWeb: false,
    );
    await expectLater(
      service.status(),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'invalid_status')
            .having(
              (error) => error.message,
              'message',
              isNot(contains('futureStatus')),
            ),
      ),
    );
  });
}
