# Dartitect Media

[Português (Brasil)](README.pt-BR.md)

## Purpose

`dartitect_media` is a removable Android/iOS plugin for gallery authorization
status, explicit authorization requests, and image saves. It does not provide a
picker, video pipeline, editor, temporary-file manager, or broad media layer.

Android API 24–28 stores only whether this plugin has previously initiated the
legacy write-permission request, allowing `notDetermined` to remain distinct
from `denied`. Android 29+ neither declares nor requests legacy storage write
permission. On iOS 14+, the 1.0 contract deliberately uses Photos `.readWrite`
for status, request, and save because optional album lookup/creation requires
library access; `.limited` is preserved and cannot satisfy a save.

## Usage

Create `MethodChannelGalleryMediaService` in infrastructure composition.
Request access only from an explicit consumer-owned UI action, then pass a
native-readable absolute image path and optional album to `saveImage`. Saving
never requests permission automatically. Native completions return to Flutter
on the main thread.

## Boundary contract

- Why a package: it isolates Android MediaStore and iOS Photos build/runtime
  dependencies from the foundation.
- Owns: method-channel coordination and the Android "request attempted" bit.
- Borrows: the input path and source file; it never deletes or edits them.
- Persists: only that Android authorization-history bit. Asset persistence is
  performed by the platform gallery.
- Logs: nothing. Paths, file names, bytes, album names, and native messages are
  never telemetry payloads.
- Supports: Android/iOS status, request, one image save, optional album, and
  removal of the plugin-owned authorization-history bit.
- Does not support: picker, video, editing, temporary cleanup, desktop, or web.
- Removal: while the Android plugin is still installed, await
  `clearOwnedState()` to delete its authorization-history bit. Then remove the
  dependency/plugin registration and replace the injected
  `GalleryMediaService`. The cleanup is inert on other hosts and never revokes
  OS permission or deletes source files/gallery assets; existing gallery assets
  remain platform/user-owned. If cleanup reports `cleanup_failed`, keep the
  plugin installed and retry rather than claiming zero residue.

The app owns Android/iOS disclosure text, `Info.plist` usage descriptions,
album naming, source-file lifetime and cleanup, user messaging, and platform
review.
