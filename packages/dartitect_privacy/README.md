# dartitect_privacy

## Purpose

A removable Flutter boundary for Apple App Tracking Transparency (ATT) status
and an explicit authorization request. Construction and status reads never
prompt. The package is not a consent engine and makes no legal-compliance claim.

## When to use

Use it when an iOS Flutter application has independently decided to use ATT and
needs a small injectable boundary that keeps prompting under a consumer-owned
interaction.

## When not to use

Do not use it for LGPD/GDPR consent, analytics policy, SDK initialization,
privacy-manifest generation, disclosure copy, or automatic bootstrap prompts.
It is also not the observability classification/sanitization boundary; ATT and
telemetry destination privacy remain independent contracts.

## Platforms and entrypoints

Import `package:dartitect_privacy/dartitect_privacy.dart` from Flutter code. ATT
is available on iOS 14 and later; the plugin's iOS deployment floor is iOS 12.
Earlier iOS versions and non-iOS hosts return `notSupported`.

## Mental model and data flow

The composition root injects a `TrackingAuthorizationService`. UI first presents
consumer-owned disclosure and then, from an explicit user action, reads status
and optionally calls `request()`. Native status returns as the closed
`TrackingAuthorizationStatus` enum. Nothing is persisted or logged.

## Minimal workflow

```dart
import 'package:dartitect_privacy/dartitect_privacy.dart';

Future<void> requestAfterDisclosure() async {
  final tracking = MethodChannelTrackingAuthorizationService();
  if (await tracking.status() == TrackingAuthorizationStatus.notDetermined) {
    await tracking.request();
  }
}
```

## Public API tour

- `TrackingAuthorizationService` is the injectable status/request contract.
- `MethodChannelTrackingAuthorizationService` is the Flutter implementation.
- `TrackingAuthorizationStatus` preserves authorized, denied, restricted,
  not-determined, and not-supported outcomes.

## Ownership and lifecycle

The service owns only request coordination and has no dispose operation. It
borrows Flutter plugin registration and the consumer's disclosure flow. The
application owns `NSUserTrackingUsageDescription`, request timing, UI copy,
legal review, and every tracking/analytics SDK.

## Failure, cancellation, and concurrency

Concurrent prompt coordination is handled by the service/native boundary.
Requests are platform-controlled and not cancellable after dispatch. Unsupported
hosts return a typed status without making a channel call. An unknown future
native status fails closed with the stable `invalid_status` error rather than
retaining native payload.

## Prohibited uses and limitations

Never prompt during construction, bootstrap, a status read, or without explicit
consumer interaction. Do not interpret ATT as general consent, initialize a
tracking SDK here, persist authorization state, or emit status/user action as
telemetry.

## Testing

Run `flutter test`. Cover inert construction, status mapping, explicit prompt
separation, unsupported hosts, concurrent requests, unknown status, and absence
of logging/persistence. Native integration should cover the deployment floor
and an ATT-capable simulator/device environment.

## Related packages and guides

This is an optional leaf package. Pair it with consumer UI and policy; it has no
required relationship to media or observability. Read
[optional capabilities](../../docs/guides/optional-capabilities.md) and
[ecosystem selection](../../docs/guides/ecosystem-selection.md).

## Availability

Dartitect `1.1.0` is distributed only by the annotated `v1.1.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
