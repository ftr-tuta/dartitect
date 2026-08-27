import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';
import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/native_qa_panel.dart';

void main() {
  testWidgets('runs explicit QA actions and keeps the log redacted', (
    tester,
  ) async {
    final media = _FakeMedia();
    await tester.pumpWidget(
      NativeCapabilityHarness(media: media, privacy: _FakePrivacy()),
    );

    for (final key in const <String>[
      'privacyStatus',
      'privacyRequest',
      'mediaStatus',
      'mediaRequest',
      'saveImage',
      'missingFile',
      'invalidFile',
      'cleanup',
    ]) {
      final button = find.byKey(Key(key));
      await tester.ensureVisible(button);
      VoidCallback? action;
      for (var attempt = 0; attempt < 20 && action == null; attempt += 1) {
        action = tester.widget<FilledButton>(button).onPressed;
        if (action == null) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
      }
      expect(action, isNotNull, reason: '$key remained disabled');
      action!();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    final log = tester.widget<SelectableText>(find.byKey(const Key('qaLog')));
    expect(log.data, contains('privacy-status:notSupported'));
    expect(log.data, contains('media-status:authorized'));
    expect(log.data, contains('save-image:passed-source-preserved'));
    expect(log.data, contains('missing-file:passed'));
    expect(log.data, contains('invalid-file:passed'));
    expect(log.data, contains('cleanup:passed-idempotent'));
    expect(log.data, isNot(contains('/tmp/')));
    expect(log.data, isNot(contains('content://')));
    expect(media.cleanupCalls, 2);
  });
}

final class _FakePrivacy implements TrackingAuthorizationService {
  @override
  Future<TrackingAuthorizationStatus> request() async =>
      TrackingAuthorizationStatus.notSupported;

  @override
  Future<TrackingAuthorizationStatus> status() async =>
      TrackingAuthorizationStatus.notSupported;
}

final class _FakeMedia implements GalleryMediaService {
  int cleanupCalls = 0;

  @override
  Future<void> clearOwnedState() async {
    cleanupCalls += 1;
  }

  @override
  Future<GalleryPermissionStatus> requestAccess() async =>
      GalleryPermissionStatus.authorized;

  @override
  Future<Result<GallerySaveReceipt, GalleryFailure>> saveImage(
    GallerySaveRequest request,
  ) async {
    if (request.path.endsWith('missing.png')) {
      return Err<GalleryFailure>(
        const GalleryFileNotFoundFailure(),
        StackTrace.current,
      );
    }
    if (!request.path.endsWith('.png')) {
      return Err<GalleryFailure>(
        const GalleryInvalidFileFailure(),
        StackTrace.current,
      );
    }
    return const Ok<GallerySaveReceipt>(
      GallerySaveReceipt(
        identifier: 'content://must-not-be-logged',
        album: 'Dartitect V1S13',
      ),
    );
  }

  @override
  Future<GalleryPermissionStatus> status() async =>
      GalleryPermissionStatus.authorized;
}
