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
