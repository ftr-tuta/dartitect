# Changelog

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
