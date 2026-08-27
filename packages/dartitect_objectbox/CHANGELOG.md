# Changelog

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
