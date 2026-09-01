# Optional capability contracts

The four capability packages are opt-in leaves. Foundation, runtime,
observability, and tooling do not depend on them. Adding one package does not
select the others, and removing one does not change persisted Dartitect core
formats.

## Frozen 1.0 boundary matrix

| Package | Supported platform and outcome | Owns / borrows / persists | Logging | Supports | Does not support | Removal |
|---|---|---|---|---|---|---|
| `dartitect_privacy` | Flutter iOS; deployment floor iOS 12, ATT available on iOS 14+. Earlier iOS, Android, desktop, Fuchsia, and web return `notSupported` without a channel call | Owns request coordination; borrows Flutter registration and the consumer disclosure flow; persists nothing | Emits no logs; status, user choice, and action are never telemetry | Read ATT status and request only after an explicit consumer call | Legal consent, LGPD/GDPR claims, analytics policy, SDK initialization, or usage-description generation | Replace `TrackingAuthorizationService`, remove registration/dependency, then remove `NSUserTrackingUsageDescription` only if no other consumer needs it. No state migration or Dartitect residue |
| `dartitect_media` | Flutter Android API 24+ and iOS 14+. Desktop, Fuchsia, and web return typed not-supported outcomes without a channel call | Owns channel/request coordination and one Android legacy-request-history bit; borrows the source path/file unchanged; successful assets become platform/user-owned | Emits no logs; paths, names, bytes, albums, native messages, and receipts are never telemetry | Status, explicit request, one image save, optional album, and cleanup of owned metadata | Picker, video, editing, temporary-file management, desktop/web media, or automatic permission requests | Await `clearOwnedState()` while the Android plugin is installed, replace `GalleryMediaService`, then remove registration/dependency. Cleanup never revokes permission or deletes source/gallery assets |
| `dartitect_locale_br` | Dart VM, Flutter, and web | Owns one copied immutable ASCII-digit string; borrows and persists nothing | Emits no logs; raw or normalized CEP is never telemetry | Structural parse/format of plain, `XXXXX-XXX`, and `XX.XXX-XXX` CEP | Existence, assignment, delivery, address lookup, Correios integration, CPF/CNPJ, phone, currency, or widgets | Replace the value at the locale boundary and remove the dependency. No state/artifact migration |
| `dartitect_geometry` | Dart VM, Flutter, and web | Owns immutable coordinate copies; borrows and persists nothing | Emits no logs; coordinates and results are never telemetry | Finite Cartesian 2D points, validated simple polygon/holes, deterministic polylabel, explicit tolerance and precision | GIS, CRS, projection, geodesy, latitude/longitude semantics, antimeridian, unit conversion, mutable geometry, or topology repair | Replace calls at the geometry adapter and remove the dependency. No stored format or runtime resource migration |

## Permission and action rules

Construction and composition are inert. Reading status never prompts.
`request()`/`requestAccess()` may be called only from an explicit
consumer-owned interaction; no bootstrap, constructor, status read, or image
save requests permission automatically.

`dartitect_privacy` preserves every ATT state. An unknown future native state
fails with the stable `invalid_status` code and does not retain the native
payload.

ATT is unrelated to observability value classification and destination
sanitization. `dartitect_privacy` remains exclusively the optional Apple
tracking-authorization boundary; it neither configures telemetry policy nor
records consent for a local or remote destination.

`dartitect_media` freezes this platform behavior:

| Host | Status/request | Save contract |
|---|---|---|
| Android API 24–28 | Declares/requests `WRITE_EXTERNAL_STORAGE`; the plugin-owned history bit distinguishes initial `notDetermined` from `denied` | Requires authorization, copies one readable image into MediaStore, removes a partially inserted asset on failure, and returns completion on the main thread |
| Android API 29+ | Never declares or requests legacy write permission; status is `authorized` for MediaStore insertion | Uses scoped MediaStore with pending publication; source file remains untouched |
| iOS 14+ | Uses Photos `.readWrite` for status and request because optional album lookup/creation needs library access; preserves `.limited` | Requires `.authorized`; limited access produces `GalleryLimitedAccessFailure`; the Photos transaction creates one asset and optional album association; completion returns on the main thread |
| Other/web | `notSupported`, channel-inert | `Err(GalleryNativeFailure('not_supported'))`, channel-inert |

`saveImage` checks status but never calls request. Expected native failures are
mapped to payload-free typed failures. `clearOwnedState()` deletes only the
Android `legacy_write_requested` preference; it is a removal/migration command,
not routine disposal. A `cleanup_failed` platform error blocks removal and must
be retried; zero residue cannot be claimed after that error.

The consumer owns disclosure text, usage descriptions, request timing, user
messaging, source-file lifetime/cleanup, album names, legal/platform review,
and any SDK initialization.

## Pure-Dart value limits

`BrazilianPostalCode` accepts eight ASCII digits and the two documented masks,
with surrounding whitespace trimmed. Structural acceptance, including
`00000000`, makes no claim that the CEP exists, is assigned, or accepts
delivery. The reviewed reference and date remain recorded in the package
README.

`dartitect_geometry` treats coordinates as planar input units. Points must be
finite and compare exactly. Polygon construction copies and freezes rings,
rejects degeneracy, self-intersection, holes outside/touching the outer ring,
and overlapping/nested holes. `defaultGeometryTolerance` is the public absolute
`1e-12` bound; `precision` is finite, positive, expressed in input units, and
bounds remaining polylabel improvement. Equal inputs and precision produce the
same result.

## Verification

Run the two Flutter package tests and both pure-Dart suites on VM and Chrome.
The contract tests cover inert construction, unsupported hosts, native status
mapping, prompt separation, typed/payload-free failures, owned-state cleanup,
value boundaries, immutable copies, numeric validation, and determinism.

Stable release evidence covers Android API 24 manifest/lint/build compatibility
and Android 14/API 34 runtime on a clean GitHub-hosted emulator. iOS evidence
covers the iOS 14 media and iOS 12 privacy deployment floors plus real
method-channel integration on a dynamically selected hosted simulator. No
consumer hardware or privately managed runner is required; local runs are
development feedback only.
