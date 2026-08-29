## 1.0.0-rc.6

- Complete this package's lockstep RC6 vertical-platform contracts.

## 1.0.0-rc.5

- Join the lockstep RC5 paved-road source cohort without creating a tag,
  release, or publication.

## 1.0.0-rc.4

- Promote the modular modeling cohort without package-specific API changes.

## 1.0.0-rc.3

- Promote the lockstep hardening candidate without package-specific public API
  changes.

## 1.0.0-rc.2

- Promote the lockstep candidate cohort without public Dart API changes and
  bind release validation to the RC.2 source and evidence matrix.

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.
- Add `clearOwnedState()` so package removal can delete the plugin-owned legacy
  Android authorization-history bit without touching permissions or assets.
- Distinguish initial and denied legacy Android permission states, avoid legacy
  requests on Android 10+, use iOS read-write photo access for album support,
  and complete method-channel callbacks on the main thread.
- Add explicit Android/iOS gallery permission and typed image-save boundary.
