# Changelog

## Unreleased

- Validate the `1.1.0-rc.3` common local-first repository contract against one
  selected ObjectBox store without dual-write or automatic engine migration.
- Version-only lockstep candidate; ObjectBox telemetry remains payload-free with no automatic path, ID, or query capture.

## 1.0.0

- Promote the validated RC10 source cohort to the stable GitHub-only release.

## 1.0.0-rc.10

- Join the RC10 business-neutral UI quality and evidence cohort.

## 1.0.0-rc.9

- Join the RC9 context-owned graph and restart/fencing provider-canary cohort.

## 1.0.0-rc.8

- Prepare the package for the RC8 greenfield platform baseline and compatible post-1.0 publication cohorts.
- Freeze managed operational UIDs and validate regeneration/reopen without
  changing consumer entity ownership.

## 1.0.0-rc.6

- Complete this package's lockstep RC6 vertical-platform contracts.

## 1.0.0-rc.5

- Join the lockstep RC5 paved-road source cohort without creating a tag,
  release, or publication.

## 1.0.0-rc.4

- Pin ObjectBox 5.3.2 constructor compatibility to generated/runtime evidence
  while keeping entities, model files, and writers consumer-owned.

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

- Add a borrowed-Store sync checkpoint adapter whose transactional writes carry
  lease fencing tokens for consumer enforcement.
- Add `ObjectBoxProjectionExecutor` over `Store.runAsync` with borrowed Store
  ownership, cancellation-safe publication, and draining worker teardown.
- Add `ObjectBoxMutationTransaction`, which commits consumer domain/outbox
  writes together and rolls both back for typed `Err` or unexpected crashes.
- Add `ObjectBoxVersionedProjection` for consumer-owned entity IDs, versions,
  and incremental `LiveCollection` projections.
- Add activation-local `ObjectBoxQuerySource` watchers with one authoritative
  query, typed failure mapping, `findAsync`, and deterministic teardown.
- Initial native ObjectBox lifecycle adapter.
