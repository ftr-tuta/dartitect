import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Gallery authorization state, preserving iOS limited access.
enum GalleryPermissionStatus {
  /// Gallery integration is unavailable on this platform.
  notSupported,

  /// The consumer has not requested access.
  notDetermined,

  /// Access was denied or restricted.
  denied,

  /// The user granted limited photo-library access.
  limited,

  /// Full required access is authorized.
  authorized,
}

/// Validated immutable image save request.
final class GallerySaveRequest {
  /// Creates a request for an existing native-readable absolute [path].
  GallerySaveRequest({required this.path, String? album})
    : album = album?.trim() {
    final normalized = path.replaceAll('\\', '/');
    final absolute =
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
    if (!absolute || path.contains('\u0000')) {
      throw ArgumentError.value(path, 'path', 'must be an absolute path');
    }
    if (this.album != null && this.album!.isEmpty) {
      throw ArgumentError.value(album, 'album', 'must not be empty');
    }
  }

  /// Absolute source image path.
  final String path;

  /// Optional consumer-owned destination album name.
  final String? album;
}

/// Receipt containing only the native asset identifier and requested album.
final class GallerySaveReceipt {
  /// Creates a successful save receipt.
  const GallerySaveReceipt({required this.identifier, this.album});

  /// Platform asset URI/local identifier.
  final String identifier;

  /// Requested album, when present.
  final String? album;
}

/// Expected gallery save failure without retaining native error text.
sealed class GalleryFailure implements Exception {
  const GalleryFailure(this.message);

  /// Static payload-free classification message.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Source path does not exist.
final class GalleryFileNotFoundFailure extends GalleryFailure {
  /// Creates the failure.
  const GalleryFileNotFoundFailure() : super('Image file was not found.');
}

/// Source is unreadable or not a supported image.
final class GalleryInvalidFileFailure extends GalleryFailure {
  /// Creates the failure.
  const GalleryInvalidFileFailure() : super('Image file is invalid.');
}

/// Required gallery access is denied or not yet requested.
final class GalleryPermissionFailure extends GalleryFailure {
  /// Creates the failure.
  const GalleryPermissionFailure()
    : super('Gallery permission is unavailable.');
}

/// Limited access cannot satisfy this save operation.
final class GalleryLimitedAccessFailure extends GalleryFailure {
  /// Creates the failure.
  const GalleryLimitedAccessFailure()
    : super('Limited gallery access cannot satisfy this operation.');
}

/// Native authorization or save interaction was cancelled.
final class GalleryCancelledFailure extends GalleryFailure {
  /// Creates the failure.
  const GalleryCancelledFailure() : super('Gallery operation was cancelled.');
}

/// Platform integration failed for a non-user-controlled reason.
final class GalleryNativeFailure extends GalleryFailure {
  /// Creates a native failure named only by a stable [code].
  const GalleryNativeFailure(this.code)
    : super('Native gallery operation failed.');

  /// Stable plugin error code without native message or path.
  final String code;
}

/// Explicit permission and image-save port.
abstract interface class GalleryMediaService {
  /// Reads current access without prompting.
  Future<GalleryPermissionStatus> status();

  /// Requests access only when called by the consumer.
  Future<GalleryPermissionStatus> requestAccess();

  /// Saves one validated image without automatically requesting permission.
  Future<Result<GallerySaveReceipt, GalleryFailure>> saveImage(
    GallerySaveRequest request,
  );

  /// Removes only plugin-owned authorization-history metadata.
  ///
  /// This is a removal/migration operation. It does not revoke platform
  /// permission, delete source files, or delete gallery assets.
  Future<void> clearOwnedState();
}

/// Android/iOS method-channel implementation.
final class MethodChannelGalleryMediaService implements GalleryMediaService {
  /// Creates the service without reading or requesting permission.
  MethodChannelGalleryMediaService({
    MethodChannel? channel,
    TargetPlatform? platform,
    bool? isWeb,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _platform = platform,
       _isWeb = isWeb;

  static const String _channelName = 'dev.dartitect/media';

  final MethodChannel _channel;
  final TargetPlatform? _platform;
  final bool? _isWeb;

  bool get _isSupported {
    if (_isWeb ?? kIsWeb) return false;
    final platform = _platform ?? defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  @override
  Future<GalleryPermissionStatus> status() => _permission('status');

  @override
  Future<GalleryPermissionStatus> requestAccess() => _permission('request');

  Future<GalleryPermissionStatus> _permission(String method) async {
    if (!_isSupported) return GalleryPermissionStatus.notSupported;
    return _statusFrom(await _channel.invokeMethod<String>(method));
  }

  @override
  Future<Result<GallerySaveReceipt, GalleryFailure>> saveImage(
    GallerySaveRequest request,
  ) async {
    if (!_isSupported) {
      return Err<GalleryFailure>(
        const GalleryNativeFailure('not_supported'),
        StackTrace.current,
      );
    }
    final permission = await status();
    if (permission == GalleryPermissionStatus.limited) {
      return Err<GalleryFailure>(
        const GalleryLimitedAccessFailure(),
        StackTrace.current,
      );
    }
    if (permission != GalleryPermissionStatus.authorized) {
      return Err<GalleryFailure>(
        const GalleryPermissionFailure(),
        StackTrace.current,
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'saveImage',
        <String, Object?>{
          'path': request.path,
          if (request.album != null) 'album': request.album,
        },
      );
      final identifier = raw?['identifier'];
      if (identifier is! String || identifier.isEmpty) {
        return Err<GalleryFailure>(
          const GalleryNativeFailure('invalid_receipt'),
          StackTrace.current,
        );
      }
      return Ok<GallerySaveReceipt>(
        GallerySaveReceipt(identifier: identifier, album: request.album),
      );
    } on PlatformException catch (error, stackTrace) {
      final failure = switch (error.code) {
        'file_not_found' => const GalleryFileNotFoundFailure(),
        'invalid_file' => const GalleryInvalidFileFailure(),
        'permission_denied' => const GalleryPermissionFailure(),
        'limited_access' => const GalleryLimitedAccessFailure(),
        'cancelled' => const GalleryCancelledFailure(),
        _ => GalleryNativeFailure(error.code),
      };
      return Err<GalleryFailure>(failure, stackTrace);
    }
  }

  @override
  Future<void> clearOwnedState() async {
    if ((_isWeb ?? kIsWeb) ||
        (_platform ?? defaultTargetPlatform) != TargetPlatform.android) {
      return;
    }
    await _channel.invokeMethod<void>('clearOwnedState');
  }
}

GalleryPermissionStatus _statusFrom(String? value) => switch (value) {
  'notSupported' => GalleryPermissionStatus.notSupported,
  'notDetermined' => GalleryPermissionStatus.notDetermined,
  'denied' => GalleryPermissionStatus.denied,
  'limited' => GalleryPermissionStatus.limited,
  'authorized' => GalleryPermissionStatus.authorized,
  _ => throw PlatformException(
    code: 'invalid_status',
    message: 'Native gallery integration returned an unknown status.',
  ),
};
