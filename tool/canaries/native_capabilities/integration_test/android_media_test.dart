import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';
import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _expectedApi = int.fromEnvironment('DARTITECT_ANDROID_API');
const _exerciseLifecycle = bool.fromEnvironment('DARTITECT_EXERCISE_LIFECYCLE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android current exercises media and keeps privacy inert', (
    tester,
  ) async {
    expect(_expectedApi, greaterThanOrEqualTo(29));
    final privacy = MethodChannelTrackingAuthorizationService();
    expect(await privacy.status(), TrackingAuthorizationStatus.notSupported);
    expect(await privacy.request(), TrackingAuthorizationStatus.notSupported);

    final media = MethodChannelGalleryMediaService();
    expect(await media.status(), GalleryPermissionStatus.authorized);
    final temporary = await Directory.systemTemp.createTemp(
      'dartitect-native-media-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final image = File('${temporary.path}/dartitect-v1s13.png');
    await image.writeAsBytes(base64Decode(_onePixelPng));

    final saved = await media.saveImage(
      GallerySaveRequest(path: image.path, album: 'Dartitect V1S13'),
    );
    expect(saved, isA<Ok<GallerySaveReceipt>>());
    expect((saved as Ok<GallerySaveReceipt>).value.identifier, isNotEmpty);
    expect(image.existsSync(), isTrue, reason: 'The source remains borrowed.');

    final missing = await media.saveImage(
      GallerySaveRequest(path: '${temporary.path}/missing.png'),
    );
    expect(
      (missing as Err<GalleryFailure>).failure,
      isA<GalleryFileNotFoundFailure>(),
    );
    final invalid = await media.saveImage(
      GallerySaveRequest(path: temporary.path),
    );
    expect(
      (invalid as Err<GalleryFailure>).failure,
      isA<GalleryInvalidFileFailure>(),
    );
    await media.clearOwnedState();
    await media.clearOwnedState();
  });

  testWidgets('Android lifecycle returns after real background transition', (
    tester,
  ) async {
    if (!_exerciseLifecycle) return;
    final observer = _LifecycleObserver();
    WidgetsBinding.instance.addObserver(observer);
    addTearDown(() => WidgetsBinding.instance.removeObserver(observer));
    // The runner waits for this marker before opening an external Activity and
    // bringing this exact instrumented task back to the foreground. This
    // exercises the real Activity/engine lifecycle, not a fake event.
    // ignore: avoid_print
    print('DARTITECT_LIFECYCLE_READY');
    await Future<void>.delayed(const Duration(seconds: 30));
    final backgroundIndex = observer.states.indexWhere(
      (state) =>
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused,
    );
    expect(
      backgroundIndex,
      greaterThanOrEqualTo(0),
      reason: '${observer.states}',
    );
    expect(
      observer.states.skip(backgroundIndex + 1),
      contains(AppLifecycleState.resumed),
      reason: '${observer.states}',
    );
  });
}

final class _LifecycleObserver with WidgetsBindingObserver {
  final List<AppLifecycleState> states = <AppLifecycleState>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    states.add(state);
  }
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '/x8AAusB9Wl2nNwAAAAASUVORK5CYII=';
