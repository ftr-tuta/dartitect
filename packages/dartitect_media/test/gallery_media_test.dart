import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.dartitect/media.test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('request validates an absolute path and optional album', () {
    expect(() => GallerySaveRequest(path: 'relative.png'), throwsArgumentError);
    expect(
      () => GallerySaveRequest(path: '/tmp/image.png', album: ' '),
      throwsArgumentError,
    );
    final request = GallerySaveRequest(path: '/tmp/image.png', album: ' Maps ');
    expect(request.album, 'Maps');
  });

  test('construction is inert and status preserves limited access', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return 'limited';
        });
    final service = _service(channel);
    expect(calls, isEmpty);
    expect(await service.status(), GalleryPermissionStatus.limited);
    expect(await service.requestAccess(), GalleryPermissionStatus.limited);
    expect(calls, <String>['status', 'request']);
  });

  test('preserves the legacy Android initial authorization state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'notDetermined');
    final service = MethodChannelGalleryMediaService(
      channel: channel,
      platform: TargetPlatform.android,
      isWeb: false,
    );

    expect(await service.status(), GalleryPermissionStatus.notDetermined);
  });

  test(
    'preserves every native permission status and rejects unknowns',
    () async {
      for (final status in GalleryPermissionStatus.values) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => status.name);
        expect(await _service(channel).status(), status);
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'futureStatus');
      await expectLater(
        _service(channel).status(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'invalid_status',
          ),
        ),
      );
    },
  );

  test('unsupported hosts are channel-inert with typed outcomes', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls += 1;
          return 'authorized';
        });
    final cases = <(TargetPlatform, bool)>[
      (TargetPlatform.linux, false),
      (TargetPlatform.macOS, false),
      (TargetPlatform.windows, false),
      (TargetPlatform.fuchsia, false),
      (TargetPlatform.android, true),
      (TargetPlatform.iOS, true),
    ];
    for (final (platform, isWeb) in cases) {
      final service = MethodChannelGalleryMediaService(
        channel: channel,
        platform: platform,
        isWeb: isWeb,
      );
      expect(
        await service.status(),
        GalleryPermissionStatus.notSupported,
        reason: '$platform web=$isWeb',
      );
      expect(
        await service.requestAccess(),
        GalleryPermissionStatus.notSupported,
        reason: '$platform web=$isWeb',
      );
      final save = await service.saveImage(
        GallerySaveRequest(path: '/tmp/image.png'),
      );
      expect(
        (save as Err<GalleryFailure>).failure,
        isA<GalleryNativeFailure>().having(
          (failure) => failure.code,
          'code',
          'not_supported',
        ),
        reason: '$platform web=$isWeb',
      );
      await service.clearOwnedState();
    }
    expect(calls, 0);
  });

  test('clearOwnedState only removes Android plugin metadata', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    final android = MethodChannelGalleryMediaService(
      channel: channel,
      platform: TargetPlatform.android,
      isWeb: false,
    );
    await android.clearOwnedState();
    await _service(channel).clearOwnedState();
    expect(calls, <String>['clearOwnedState']);
  });

  test('clearOwnedState exposes a stable removal-blocking failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'cleanup_failed'),
        );
    final service = MethodChannelGalleryMediaService(
      channel: channel,
      platform: TargetPlatform.android,
      isWeb: false,
    );
    await expectLater(
      service.clearOwnedState(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'cleanup_failed',
        ),
      ),
    );
  });

  test('save maps success and every reviewed native failure', () async {
    Future<Result<GallerySaveReceipt, GalleryFailure>> run(
      String? error,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'status') return 'authorized';
            if (error != null) throw PlatformException(code: error);
            return <String, Object?>{'identifier': 'asset-1'};
          });
      return _service(channel)
          .saveImage(GallerySaveRequest(path: '/tmp/image.png', album: 'Maps'));
    }

    final success = await run(null) as Ok<GallerySaveReceipt>;
    expect(success.value.identifier, 'asset-1');
    expect(success.value.album, 'Maps');
    expect(
      (await run('file_not_found') as Err<GalleryFailure>).failure,
      isA<GalleryFileNotFoundFailure>(),
    );
    expect(
      (await run('invalid_file') as Err<GalleryFailure>).failure,
      isA<GalleryInvalidFileFailure>(),
    );
    expect(
      (await run('permission_denied') as Err<GalleryFailure>).failure,
      isA<GalleryPermissionFailure>(),
    );
    expect(
      (await run('limited_access') as Err<GalleryFailure>).failure,
      isA<GalleryLimitedAccessFailure>(),
    );
    expect(
      (await run('cancelled') as Err<GalleryFailure>).failure,
      isA<GalleryCancelledFailure>(),
    );
    expect(
      (await run('native_error') as Err<GalleryFailure>).failure,
      isA<GalleryNativeFailure>(),
    );
  });

  test(
    'save does not request permission and distinguishes limited access',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return 'limited';
          });
      final result = await _service(channel)
          .saveImage(GallerySaveRequest(path: '/tmp/image.png'));
      expect(
        (result as Err<GalleryFailure>).failure,
        isA<GalleryLimitedAccessFailure>(),
      );
      expect(calls, <String>['status']);
    },
  );

  test('save preserves no native message or path in typed failures', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'status') return 'authorized';
          throw PlatformException(
            code: 'native_error',
            message: '/private/consumer/image.png',
          );
        });
    final result = await _service(channel)
        .saveImage(GallerySaveRequest(path: '/tmp/image.png'));
    final failure = (result as Err<GalleryFailure>).failure;
    expect(failure, isA<GalleryNativeFailure>());
    expect('$failure', isNot(contains('/private/consumer/image.png')));
    expect('$failure', isNot(contains('/tmp/image.png')));
  });
}

MethodChannelGalleryMediaService _service(MethodChannel channel) =>
    MethodChannelGalleryMediaService(
      channel: channel,
      platform: TargetPlatform.iOS,
      isWeb: false,
    );
