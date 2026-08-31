# Paved-road canary

This synthetic Flutter application exercises the RC10 paved road without
credentials, private APIs, durable domain records, or product business rules.
Its cache declaration covers an application-local authority profile. The tests
verify hosts, typed progress, explicit lazy computation, versioned UI
restoration, bounded local history, resilience, transfer, and diagnostics.

The UI quality surface uses Material 3 `Scaffold`, `FilledButton`, `TextButton`,
`NavigationBar`, `NavigationRail`, adaptive controls, and one deliberate Apple
Cupertino convention directly. It proves the responsive window API, exhaustive
command/form/query/resource builders, the paired accessibility matrix, keyboard
activation, and fixed compact/medium/expanded shared-layout goldens. Product
themes, copy, localization, navigation, and visual identity remain app-owned.

DevTools registration occurs only inside an assertion, so the three read-only
service extensions are absent from product and release builds.

Run the canary with:

```sh
flutter test
flutter build web
flutter build linux
flutter build apk --debug
```

Windows, macOS, and no-codesign iOS builds run in their matching hosted CI
cells. Golden comparison runs only in the pinned Linux/Flutter floor cell;
semantics and behavior remain the primary cross-platform gate.
