# dartitect_devtools

## Purpose

An optional development-only bridge from Dartitect diagnostics protocol v2 to
three isolate-local read-only VM service extensions, plus a bundled Flutter Web
DevTools inspector.

## When to use

Use it from an explicit development entrypoint when bounded payload-free local
runtime topology and lifecycle facts need interactive inspection.

## When not to use

Do not register it in product/release entrypoints or treat it as telemetry,
remote administration, retry control, cancellation control, or application UI.

## Platforms and entrypoints

Import `package:dartitect_devtools/dartitect_devtools.dart` on the Dart VM or
Flutter development host. The inspector is a bundled Flutter Web extension.
Product builds install no service extensions.

## Mental model and data flow

An application-owned diagnostics emitter writes payload-free protocol-v2 events
to a bounded buffer. Explicit registration exposes capabilities, a snapshot,
and event deltas for that isolate. The inspector reads those RPCs only.

## Minimal workflow

```dart
final registration = DartitectDevToolsRegistration.register(
  enabled: developmentMode,
  buffer: diagnosticBuffer,
  detail: DartitectDiagnosticDetail.topology,
);
```

## Public API tour

`DartitectDevToolsRegistration` installs the exact service-extension allowlist.
The three public method constants and `dartitectReadOnlyServiceExtensions` let
tests verify discovery. A registrar interface supports deterministic tests.

## Ownership and lifecycle

The development composition root owns registration and its diagnostic buffer.
Registered disposal clears every retained event. VM handlers cannot unregister,
so disposed handlers remain inert and read only the empty terminal buffer.

## Failure, cancellation, and concurrency

Invalid RPC parameters return a fixed invalid-parameters response. Reads are
isolate-local and bounded by ring capacity. No inspector failure can change the
application or trigger runtime work.

## Prohibited uses and limitations

- No retry, cancel, clear, mutation, arbitrary metadata, or payload RPC.
- No URL, domain key, error text, stack, credential, or user identifier.
- No product-mode registration or remote exporter.
- No cross-isolate aggregate pretending to be one authoritative snapshot.

## Testing

Run `dart test`. Build and validate the extension with `devtools_extensions`,
and run its widget test on Chrome. Verify RPC discovery, payload exclusion,
ring bounds, disposal, and absence of extension names in a release bundle.

## Related packages and guides

Use protocol v2 from `dartitect`; instrument provider-neutral runtime boundaries
without adding telemetry. Read the
[paved-road guide](../../docs/guides/paved-road-platform.md).

## Availability

The workspace contains the `1.0.0-rc.6` source candidate. Supported Git use
requires coordinates from a matching tagged GitHub Release; otherwise there is
no supported consumption path.
