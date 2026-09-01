# Changelog

## Unreleased

- Add `SyncDataset.incremental`, confirmed-step progress, and strict
  checkpoint-before-next-pull backpressure with partial receipts.
- Add sequential and bounded-parallel DAG execution policies with stable report
  order, independent-branch continuation, and crash draining.
- Serialize borrowed checkpoint, lease, journal, and cleanup ports, and coalesce
  concurrent lease renewal.
- Retain recent sync progress in an O(1) bounded deque while preserving the
  existing stream contract.

## 1.0.0

- Promote the validated RC10 source cohort to the stable GitHub-only release.

## 1.0.0-rc.10

- Join the RC10 business-neutral UI quality and evidence cohort.

## 1.0.0-rc.9

- Make mutation commands implement the compile-time observable command/resource contracts used by generated feature runtimes.

## 1.0.0-rc.8

- Prepare the package for the RC8 greenfield platform baseline and compatible post-1.0 publication cohorts.
- Add durable operational storage-context registrations and explicit,
  coalescing `SyncTriggerCoordinator` state without hidden retries.

## 1.0.0-rc.6

- Complete this package's lockstep RC6 vertical-platform contracts.

## 1.0.0-rc.5

- Join the lockstep RC5 paved-road source cohort without creating a tag,
  release, or publication.

## 1.0.0-rc.4

- Promote primary-constructor data carriers and the modular modeling cohort
  without changing provider ownership or persisted sync schemas.

## 1.0.0-rc.3

- Expose optional `SyncAuthority` in each dataset context so fencing-capable
  consumer transactions can ensure/renew authority and atomically validate the
  token at the real dataset commit.
- Add application, checkpoint, journal, lease-release, and cleanup receipts;
  unexpected terminals now throw `SyncRunTerminalException` with the complete
  partial report and original cause/stack.

## 1.0.0-rc.2

- Promote the lockstep candidate cohort without public Dart API changes and
  bind release validation to the RC.2 source and evidence matrix.

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Use the core `IdGenerator` contract for sync runs and mutation idempotency.
- Add experimental dataset DAG, run, checkpoint, lease, progress, report, and
  headless command primitives.
