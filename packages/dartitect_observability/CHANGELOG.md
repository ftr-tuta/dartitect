# Changelog

## Unreleased

- Add destination-aware privacy profiles, masking, bounded structured sanitization, prepared telemetry, isolated destinations, diagnostics, safe tracing, and subsystem adapters while preserving every `1.0.0` API.
- Fail closed on incomplete classifiers, project binary inputs as metadata only, use one runtime-owned trace context across destinations, and support resumable bounded shutdown without disposing active dispatch.

## 1.0.0

- Promote the validated RC10 source cohort to the stable GitHub-only release.

## 1.0.0-rc.10

- Join the RC10 business-neutral UI quality and evidence cohort.

## 1.0.0-rc.9

- Join the RC9 context propagation and formal provider-canary cohort.

## 1.0.0-rc.8

- Prepare the package for the RC8 greenfield platform baseline and compatible post-1.0 publication cohorts.

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

- Add payload-free sync observation with static facts, exact-once span ending,
  and no dataset keys, request IDs, checkpoints, or payloads.
- Add a reactive observer adapter with a fixed message, allowlisted facts, and
  downstream redaction before local or Sentry destinations.
- Initial explicit observability runtime, redaction, logging, reporting, and tracing APIs.
