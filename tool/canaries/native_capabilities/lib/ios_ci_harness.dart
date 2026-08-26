import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';
import 'package:dartitect_privacy/dartitect_privacy.dart';
import 'package:flutter/widgets.dart';

const _lifecycleReadyFile = 'dartitect-ios-lifecycle-ready';
const _successFile = 'dartitect-ios-integration-passed';
const _failureFile = 'dartitect-ios-integration-failed';
const _stageFile = 'dartitect-ios-integration-stage';
const _photosRequestPrimedFile = 'dartitect-ios-photos-request-primed';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  await WidgetsBinding.instance.endOfFrame;
  final privacy = MethodChannelTrackingAuthorizationService();
  final media = MethodChannelGalleryMediaService();
  final lifecycle = _LifecycleProbe();
  final photosRequestPrimed = _photosRequestPrimedMarker.existsSync();
  WidgetsBinding.instance.addObserver(lifecycle);
  try {
    await _stage('lifecycle');
    await _signal(_lifecycleReadyFile);
    if (!photosRequestPrimed) {
      await lifecycle.waitForBackgroundAndResume();
    }
    await _exercisePublicChannels(
      privacy: privacy,
      media: media,
      photosRequestPrimed: photosRequestPrimed,
    );
    await _stage('complete');
    await _signal(_successFile);
  } on Object {
    await _signal(_failureFile);
  } finally {
    WidgetsBinding.instance.removeObserver(lifecycle);
  }
}

Future<void> _exercisePublicChannels({
  required MethodChannelTrackingAuthorizationService privacy,
  required MethodChannelGalleryMediaService media,
  required bool photosRequestPrimed,
}) async {
  if (!Platform.isIOS) throw StateError('iOS runtime required.');

  await _stage('att-status');
  final privacyStatus = await privacy.status();
  if (!TrackingAuthorizationStatus.values.contains(privacyStatus)) {
    throw StateError('Invalid ATT status.');
  }

  await _stage('photos-status');
  final initialPhotosStatus = await media.status();
  if (photosRequestPrimed &&
      initialPhotosStatus == GalleryPermissionStatus.notDetermined) {
    await _stage('photos-status-after-priming-notDetermined');
    throw StateError('Photos remained undetermined after TCC priming.');
  }
  if (initialPhotosStatus != GalleryPermissionStatus.authorized &&
      initialPhotosStatus != GalleryPermissionStatus.notDetermined) {
    await _stage('photos-status-${initialPhotosStatus.name}');
    throw StateError('Photos cannot be requested.');
  }

  // CoreSimulator can retain a pre-authorized TCC decision while
  // authorizationStatus(for: .readWrite) still reports notDetermined until
  // the application exercises requestAuthorization at least once. Use the
  // package's public request entrypoint so the runtime evidence covers both
  // status and request instead of treating the simulator control as proof.
  await _stage('photos-request');
  if (initialPhotosStatus == GalleryPermissionStatus.notDetermined) {
    await _photosRequestPrimedMarker.writeAsString('ready', flush: true);
    // Write the host-visible handoff before requestAuthorization presents its
    // system alert. CoreSimulator can suspend the application while that
    // alert is active, so no Dart timer may be relied on after this point.
    await _stage('photos-request-pending');
  }
  final requestedPhotosStatus = await media.requestAccess();
  if (requestedPhotosStatus != GalleryPermissionStatus.authorized) {
    await _stage('photos-request-${requestedPhotosStatus.name}');
    throw StateError('Photos request was not authorized.');
  }

  await _stage('photos-status-after-request');
  final photosStatus = await media.status();
  if (photosStatus != GalleryPermissionStatus.authorized) {
    await _stage('photos-status-after-request-${photosStatus.name}');
    throw StateError('Photos is not authorized after request.');
  }

  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-native-media-',
  );
  final image = File('${temporary.path}/dartitect-v1s13.png');
  try {
    await image.writeAsBytes(base64Decode(_onePixelPng), flush: true);
    await _stage('save-with-album');
    final saved = await media.saveImage(
      GallerySaveRequest(path: image.path, album: 'Dartitect V1S13'),
    );
    if (saved is! Ok<GallerySaveReceipt> ||
        saved.value.identifier.isEmpty ||
        !image.existsSync()) {
      throw StateError('Photos save contract failed.');
    }

    await _stage('missing-file');
    final missing = await media.saveImage(
      GallerySaveRequest(path: '${temporary.path}/missing.png'),
    );
    if (missing is! Err<GalleryFailure> ||
        missing.failure is! GalleryFileNotFoundFailure) {
      throw StateError('Missing-file contract failed.');
    }

    await _stage('invalid-file');
    final invalid = await media.saveImage(
      GallerySaveRequest(path: temporary.path),
    );
    if (invalid is! Err<GalleryFailure> ||
        invalid.failure is! GalleryInvalidFileFailure) {
      throw StateError('Invalid-file contract failed.');
    }

    await _stage('att-liveness');
    if (!TrackingAuthorizationStatus.values.contains(await privacy.status())) {
      throw StateError('ATT channel did not survive lifecycle.');
    }
    await _stage('photos-liveness');
    if (await media.status() != GalleryPermissionStatus.authorized) {
      throw StateError('Photos channel did not survive lifecycle.');
    }
  } finally {
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

Future<void> _signal(String name) =>
    File('${Directory.systemTemp.path}/$name')
        .writeAsString('ready', flush: true);

Future<void> _stage(String stage) =>
    File('${Directory.systemTemp.path}/$_stageFile')
        .writeAsString(stage, flush: true);

File get _photosRequestPrimedMarker => File(
  '${Directory.systemTemp.parent.path}/Library/Caches/'
  '$_photosRequestPrimedFile',
);

final class _LifecycleProbe with WidgetsBindingObserver {
  final List<AppLifecycleState> _states = <AppLifecycleState>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _states.add(state);
  }

  Future<void> waitForBackgroundAndResume() async {
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final background = _states.indexWhere(
        (state) =>
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused,
      );
      if (background >= 0 &&
          _states.skip(background + 1).contains(AppLifecycleState.resumed)) {
        return;
      }
    }
    throw StateError('Lifecycle transition was not observed.');
  }
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '/x8AAusB9Wl2nNwAAAAASUVORK5CYII=';
