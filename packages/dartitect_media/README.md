# dartitect_media

## Purpose

A removable Flutter plugin for Android/iOS gallery authorization status,
explicit authorization requests, one image save, optional album association,
and cleanup of the plugin's one owned metadata bit.

## When to use

Use it when a Flutter application needs a narrow, typed gallery-image boundary
and owns the user disclosure, request timing, source file, and gallery policy.

## When not to use

Do not use it as a picker, video pipeline, editor, temporary-file manager,
cross-platform media abstraction, automatic permission requester, or legal
policy engine.

## Platforms and entrypoints

Import `package:dartitect_media/dartitect_media.dart`. Supported native behavior:

- Android API 24–28 uses legacy write authorization and retains one
  plugin-owned “request attempted” bit.
- Android API 29+ uses scoped MediaStore and never requests legacy storage write
  permission.
- iOS 14+ uses Photos `.readWrite` because optional album lookup/creation needs
  library access.
- Desktop, Fuchsia, and web return typed not-supported outcomes without a
  channel call.

## Mental model and data flow

The composition root injects `GalleryMediaService`. UI requests access only from
an explicit user action. The application then supplies a native-readable
absolute source path and optional album in `GallerySaveRequest`. The plugin
checks current permission but never prompts during save, copies one image into
the platform gallery, and returns a typed receipt or failure. It never edits or
deletes the source file.

## Minimal workflow

```dart
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_media/dartitect_media.dart';

Future<void> saveExport(String absolutePath) async {
  final gallery = MethodChannelGalleryMediaService();
  if (await gallery.requestAccess() != GalleryPermissionStatus.authorized) {
    return;
  }
  final result = await gallery.saveImage(
    GallerySaveRequest(path: absolutePath, album: 'Exports'),
  );
  if (result case Err<GalleryFailure>()) return;
}
```

## Public API tour

- `GalleryMediaService` is the injectable status/request/save/cleanup contract.
- `MethodChannelGalleryMediaService` is the Flutter implementation.
- `GalleryPermissionStatus` preserves not-determined, restricted, denied,
  authorized, limited, and not-supported states.
- `GallerySaveRequest` and `GallerySaveReceipt` define the typed operation.
- `GalleryFailure` variants distinguish permission, limited access, missing or
  invalid files, cancellation, and sanitized native failures.

## Ownership and lifecycle

The plugin owns channel/request coordination and the Android 24–28
`legacy_write_requested` history bit. It borrows the input path/source file.
Successful gallery assets become platform/user-owned.

The application owns disclosure text, usage descriptions, request timing, album
names, source-file lifetime/cleanup, user messaging, and platform/legal review.
Before removing the plugin, call `clearOwnedState()` while the Android plugin is
still installed, then remove registration/dependency. Cleanup removes only the
history bit; it never revokes permission or deletes images/files.

## Failure, cancellation, and concurrency

`saveImage` returns `Result` with typed, payload-free failures and never requests
permission. Native completion returns on Flutter's main thread. Android pending
MediaStore insertion is removed on failure; iOS performs asset creation and
optional album association in one Photos transaction.

A user/native cancellation has its own failure type. Work already handed to the
platform is not cooperatively cancellable from Dart. Request coordination
prevents overlapping prompt state from becoming implicit policy. A
`cleanup_failed` platform error blocks a zero-residue removal claim and must be
retried.

## Prohibited uses and limitations

Never log paths, filenames, bytes, album names, native messages, permissions, or
receipts. Never request from bootstrap/construction/status/save. Limited iOS
access does not satisfy the package's album-capable save contract. There is no
picker, video, editing, desktop, web, or source-file cleanup.

## Testing

Run `flutter test`. Cover inert construction, every permission mapping,
prompt/save separation, typed failures, unsupported hosts, path/album boundary
validation, owned-state cleanup, and payload-free errors. Native integration
must cover Android API 24 behavior, Android scoped storage, iOS 14 Photos
behavior, partial-write cleanup, and main-thread completion.

## Related packages and guides

This is an optional leaf package. Use `dartitect` for `Result` and keep UI,
storage, and telemetry policy in the application. Read
[optional capabilities](../../docs/guides/optional-capabilities.md) and
[ecosystem selection](../../docs/guides/ecosystem-selection.md).

## Availability

The workspace contains the `1.0.0-rc.8` source candidate. Use only coordinates
from a matching tag with a corresponding published GitHub Release and compatible
cohort. Without one, there is no supported consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
