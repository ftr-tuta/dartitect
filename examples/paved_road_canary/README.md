# Paved-road canary

This synthetic Flutter application exercises the RC5 paved road without
credentials, private APIs, durable domain records, or product business rules.
Its `offline-full` declaration covers the largest public feature profile. The
tests verify hosts, typed progress, explicit lazy computation, versioned UI
restoration, bounded local history, resilience, jobs, transfer, and diagnostics.

DevTools registration occurs only inside an assertion, so the three read-only
service extensions are absent from product and release builds.

Run the canary with:

```sh
flutter test
flutter build web
```
