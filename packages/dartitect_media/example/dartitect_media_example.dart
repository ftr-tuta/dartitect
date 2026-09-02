import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';

/// Pure presentation projection for every native capability outcome.
enum GalleryCapabilityView {
  /// The capability can execute.
  supported,

  /// The host cannot provide the capability.
  unsupported,

  /// A consumer-owned permission interaction is required.
  permissionRequired,

  /// The user or system denied permission.
  permissionDenied,

  /// The capability may become available without an app upgrade.
  temporarilyUnavailable,

  /// The provider failed independently of permission state.
  providerFailure,
}

/// Maps status to pure view data without invoking a plugin.
GalleryCapabilityView projectGalleryStatus(GalleryPermissionStatus status) =>
    switch (status) {
      GalleryPermissionStatus.authorized => GalleryCapabilityView.supported,
      GalleryPermissionStatus.notSupported => GalleryCapabilityView.unsupported,
      GalleryPermissionStatus.notDetermined =>
        GalleryCapabilityView.permissionRequired,
      GalleryPermissionStatus.denied => GalleryCapabilityView.permissionDenied,
      GalleryPermissionStatus.limited =>
        GalleryCapabilityView.temporarilyUnavailable,
    };

/// Maps typed provider failures to pure view data without native I/O.
GalleryCapabilityView projectGalleryFailure(GalleryFailure failure) =>
    switch (failure) {
      GalleryPermissionFailure() => GalleryCapabilityView.permissionDenied,
      GalleryLimitedAccessFailure() ||
      GalleryCancelledFailure() => GalleryCapabilityView.temporarilyUnavailable,
      GalleryNativeFailure(code: 'not_supported') =>
        GalleryCapabilityView.unsupported,
      _ => GalleryCapabilityView.providerFailure,
    };

Future<void> saveExport(String absolutePath) async {
  final gallery = MethodChannelGalleryMediaService();
  if (await gallery.requestAccess() != GalleryPermissionStatus.authorized)
    return;
  final result = await gallery.saveImage(
    GallerySaveRequest(path: absolutePath, album: 'Exports'),
  );
  if (result case Err<GalleryFailure>()) return;
}
