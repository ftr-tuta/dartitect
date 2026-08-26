# Dartitect Privacy

[Português (Brasil)](README.pt-BR.md)

## Purpose

`dartitect_privacy` is a removable, ATT-only iOS boundary. Construction and
bootstrap are inert; `request()` is invoked only by an explicit consumer action.
iOS versions without ATT and non-iOS platforms return `notSupported`.

This package is not a consent engine and makes no LGPD, GDPR, legal-basis, or
regulatory-compliance claim.

## Boundary contract

- Why a package: isolate the AppTrackingTransparency framework from foundation.
- Owns: method-channel request coordination; no provider or global resource.
- Borrows: the Flutter registrar/channel and consumer disclosure flow.
- Persists: nothing.
- Logs: nothing; authorization state and user action are never telemetry here.
- Supports: ATT status and explicit request only.
- Does not support: legal consent, analytics policy, SDK initialization, or
  privacy-description generation.
- Removal: remove plugin registration/dependency and replace the injected
  `TrackingAuthorizationService`.

The app owns `NSUserTrackingUsageDescription`, disclosure copy, timing, legal
review, and initialization of any tracking SDK.
