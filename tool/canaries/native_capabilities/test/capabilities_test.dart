import 'package:dartitect/dartitect.dart';
import 'package:dartitect_geometry/dartitect_geometry.dart';
import 'package:dartitect_locale_br/dartitect_locale_br.dart';
import 'package:dartitect_media/dartitect_media.dart';
import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const privacyChannel = MethodChannel('dev.dartitect/canary.privacy');
  const mediaChannel = MethodChannel('dev.dartitect/canary.media');

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(privacyChannel, null);
    messenger.setMockMethodCallHandler(mediaChannel, null);
  });

  test('privacy preserves explicit iOS transitions', () async {
    final replies = <String>['notDetermined', 'authorized'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          privacyChannel,
          (_) async => replies.removeAt(0),
        );
    final service = MethodChannelTrackingAuthorizationService(
      channel: privacyChannel,
      platform: TargetPlatform.iOS,
      isWeb: false,
    );
    expect(await service.status(), TrackingAuthorizationStatus.notDetermined);
    expect(await service.request(), TrackingAuthorizationStatus.authorized);
  });

  test('media maps limited, cancellation, album, and missing file', () async {
    String failure = 'cancelled';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mediaChannel, (call) async {
          if (call.method == 'status') return 'authorized';
          throw PlatformException(code: failure);
        });
    final service = MethodChannelGalleryMediaService(
      channel: mediaChannel,
      platform: TargetPlatform.iOS,
      isWeb: false,
    );
    final request = GallerySaveRequest(
      path: '/tmp/canary.png',
      album: 'Canary',
    );
    expect(
      (await service.saveImage(request) as Err<GalleryFailure>).failure,
      isA<GalleryCancelledFailure>(),
    );
    failure = 'file_not_found';
    expect(
      (await service.saveImage(request) as Err<GalleryFailure>).failure,
      isA<GalleryFileNotFoundFailure>(),
    );
    failure = 'limited_access';
    expect(
      (await service.saveImage(request) as Err<GalleryFailure>).failure,
      isA<GalleryLimitedAccessFailure>(),
    );
    expect(request.album, 'Canary');
  });

  test('geometry and CEP accept valid values and reject invalid values', () {
    final polygon = Polygon2(
      outerRing: <Point2<num>>[
        Point2<int>(0, 0),
        Point2<int>(10, 0),
        Point2<int>(10, 10),
        Point2<int>(0, 10),
      ],
    );
    expect(poleOfInaccessibility(polygon).point, Point2<double>(5, 5));
    expect(
      () => Polygon2(
        outerRing: <Point2<num>>[
          Point2<int>(0, 0),
          Point2<int>(1, 1),
          Point2<int>(2, 2),
        ],
      ),
      throwsArgumentError,
    );
    expect(BrazilianPostalCode.parse('12.345-678').digits, '12345678');
    expect(BrazilianPostalCode.tryParse('12.345_678'), isNull);
  });
}
