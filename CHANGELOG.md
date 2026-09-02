# Changelog

All notable changes to Dartitect are documented in this file.

Dartitect uses a permanent lockstep cohort. Package changelogs contain concise,
package-specific notes; this root changelog is the consumer-facing source of
truth for cross-package changes and migration guidance.

## Unreleased

### Candidate state

- Workspace cohort: `1.1.0-rc.1`.
- Channel: `candidate`.
- Latest stable distribution: `1.0.0` / `v1.0.0`.
- Derivable candidate tag: `v1.1.0-rc.1`.
- Candidate tag materialized: `false`.
- No tag, GitHub Release, publication, or stable promotion is authorized by
  this changelog.

### Added

#### Destination-aware privacy policy

- Add `ObservabilityPrivacyProfile` with `strict`, `balanced`, and `diagnostic`
  presets. Each preset defines separate local and remote defaults.
- Add hierarchical, extensible `ObservabilityDataClass` values for HTTP,
  credentials, identity, operational IDs, storage, files, errors, and
  application-owned `business.*` classifications.
- Add `allow`, `mask`, and `deny` rules with deterministic
  `deny > mask > allow` precedence.
- Add global, local/remote, and optional named-destination overrides.
- Require explicit risk acceptance before high-risk data can be allowed to a
  remote destination.
- Add a payload-free explanation API for tests, configuration previews, and
  read-only tooling.

#### Global masking modes

- Add complete masking with a constant replacement marker.
- Add edge-preserving and center-preserving masking.
- Add short-value fallback, Unicode code-point processing, validation that
  prevents full disclosure, and deny-only handling for binary values.

#### Bounded structured sanitization

- Add explicit classified values and classifiers for keys, headers, URIs,
  HTTP structures, errors, stacks, and common inline secret formats.
- Add deterministic budgets for depth, collection size, total nodes, text,
  frames, and classification work.
- Add identity-based cycle detection and collision-safe masked map keys.
- Represent unknown objects by an explicit safe projection without invoking
  arbitrary `toString()` implementations.

#### Destination-aware runtime

- Add `ObservabilityRuntime.withPrivacy` without changing the existing
  constructor.
- Add validated local and remote destination registrations, independent
  bounded queues, per-destination sampling, failure counters, ownership,
  detailed flush results, and immutable diagnostics snapshots.
- Sanitize destination-specific prepared events synchronously before anything
  is queued or retained; queues never capture raw events in closures.
- Add multiple error reporters and tracers with failure-isolated composite
  spans.

#### Dio and Sentry integrations

- Add explicit, classified, bounded Dio capture for safe JSON structures while
  retaining metadata-only behavior as the default.
- Never consume streams, multipart bodies, files, uploads, downloads, or
  binary values for telemetry.
- Add Sentry prepared-input adapters that consume runtime-sanitized types
  without applying a conflicting second privacy policy.
- Map approved error context to bounded Sentry extras/contexts without creating
  a `SentryUser` or promoting arbitrary values to tags.

#### Testing, lints, DevTools, CLI, and MCP

- Add privacy policy and paired-destination harnesses, raw-secret sentinels,
  ownership checks, and deterministic structural budget tests.
- Add equivalent analyzer and CLI scan diagnostics for sensitive
  interpolation, Dio `LogInterceptor`, production risk acceptance,
  unclassified capture, and legacy Sentry use inside a prepared registration.
- Add `ext.dartitect.observabilityPrivacy` as a separate read-only,
  payload-free service extension. Diagnostics v2 retains exactly its existing
  three extensions.
- Add `balanced` privacy scaffolding and refresh package, API, MCP, and managed
  skill catalogs.

#### Release tooling

- Separate the workspace cohort from the latest distributed stable cohort.
- Add a transactional, preview-first `tool/set_release_version.dart` command.
- Parameterize local disposable-tag canaries and make the `Release` workflow
  fail closed for prerelease workspace cohorts before release preparation.

### Changed

- Keep `Redactor` as the compatible strict boundary while recommending the new
  policy/sanitizer API for multi-destination runtimes.
- Apply sanitization independently for each destination instead of sharing one
  pre-sanitized event across every sink.
- Treat container `allow` as permission to preserve and traverse structure,
  never as a bypass for child classification, limits, or redaction.
- Validate `tracestate` under a dedicated policy and never convert it into an
  attribute, tag, or baggage value.
- Keep Drift, ObjectBox, jobs, transfer, isolates, Workmanager, and diagnostics
  payload-free by default.
- Keep `dartitect_privacy` exclusively focused on App Tracking Transparency.
- Allow all 25 package changelogs to carry non-empty package-specific
  `Unreleased` bodies while retaining `1.0.0` as the first numbered version.

### Security

- Values with multiple classifications use the most restrictive matching
  decision, so allowing HTTP headers cannot implicitly allow bearer tokens,
  cookies, or authorization values.
- Raw events are sanitized before queue admission; queued work contains only
  immutable prepared snapshots.
- Local and remote queues are independent, preventing a slow or failing remote
  provider from consuming local diagnostic capacity.
- Destination registrations reject invalid names, unsupported capabilities,
  duplicate instances, and conflicting ownership.
- Diagnostics and DevTools expose policy facts and counters only, never
  samples, messages, bodies, headers, paths, or masked values.

### Compatibility

- Existing `ObservabilityRuntime(...)`, `Redactor`,
  `DioTelemetryInterceptor`, `DioInstrumentation`, and legacy Sentry adapter
  constructors retain their `1.0.0` behavior and are not deprecated.
- Applications do not need to migrate unless they opt into destination-aware
  privacy.
- The `dartitect_sync` interface remains unchanged; its observability adapter
  is exposed from a separate observability entrypoint.
- All Dartitect packages move together to `1.1.0-rc.1`; packages without a
  functional change receive a version-only lockstep candidate entry.

### Migration from 1.0.0

No migration is required for applications that retain the existing runtime and
adapters.

To opt in, construct `ObservabilityPrivacyPolicy` from one of the three
profiles, choose the global masking policy, register local/remote destinations,
and create `ObservabilityRuntime.withPrivacy`. Use the prepared-input Sentry
adapters only behind that runtime; continue using legacy adapters for direct,
defensively redacted integration. Keep Dio metadata-only capture unless a
bounded classified capture policy has been explicitly reviewed.

The latest recommended public dependency remains `1.0.0` from `v1.0.0` until a
separate stable-release plan is authorized and completed.

## 1.0.0 - 2026-09-01

- Initial stable lockstep GitHub-only release.
