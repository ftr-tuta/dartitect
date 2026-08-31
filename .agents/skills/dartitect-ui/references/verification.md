# UI verification

Use `dartitect_flutter_testing` only as a dev dependency. The standard matrix is
five paired rows: 360x640, 430x932, 768x1024, 1024x768, and 1440x900. Across
those rows it covers 100%/200% text, LTR/RTL, light/dark, normal/high contrast,
and normal/reduced motion without a Cartesian explosion. The consumer supplies
the root widget, themes, locales, and scenario exercises.

`DartitectUiHarness` configures and restores the Flutter test view, platform,
MediaQuery, accessibility features, and semantics even after failure. Its
policy uses Flutter's official labeled-target, contrast, and mobile tap-target
guidelines and fails on framework exceptions or overflow. Add explicit
assertions for focus order, keyboard activation, shortcuts, navigation,
restoration, and product actions.

Run `dartitect ui audit --strict` and the analyzer plugin. Errors cover objective
low-level custom-button primitives and orientation locks. Warnings cover
orientation/device sizing, broad MediaQuery subscriptions, gesture controls
without evident semantics, visual literals outside themes, and unlabeled icon
actions. Reviewed suppressions require code, narrow path, owner, reason, and
expiry.

Use goldens only for genuinely shared compact, medium, and expanded layouts on
a pinned runner, font, and renderer. Do not multiply goldens per screen or
platform. Semantics and behavior remain the release gate. Neither tests nor
audits send screenshots, semantics, or content to telemetry.
