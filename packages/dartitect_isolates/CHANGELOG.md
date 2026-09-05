# Changelog

## Unreleased

- Prepare the `1.2.0` GitHub-only lockstep cohort while preserving the recorded `v1.1.0` distribution.
- Add optional bounded HTTP retry feedback, shared admission budgets, and durable outbox deferral.

## 1.1.0 - 2026-09-03

- Join the `1.1.0` bounded lifecycle-evidence cohort in lockstep.
- Add fixed-size `IsolateWorkerPool` execution with bounded in-flight and FIFO
  queue admission, ordered or completion-order stream mapping, and drain-first
  disposal.
- Add fail-pool and bounded worker-replacement crash policies without replaying
  requests whose effects may already have applied.
- Add optional drain-aware request cancellation to `IsolateWorker` and preserve
  `TransferableTypedData` ownership transfer without runtime materialization.
- Version-only stable release; isolate diagnostics remain payload-free.

## 1.0.0

- Promote the validated RC10 source cohort to the stable GitHub-only release.

## 1.0.0-rc.10

- Join the RC10 business-neutral UI quality and evidence cohort.

## 1.0.0-rc.9

- Join the RC9 fresh-graph and mandatory isolate-canary cohort.

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

- Upgrade the worker protocol to version 2 and correlate wire envelopes with a
  generation-local, monotonic internal nonce instead of the reusable public
  request ID.
- Make acceptance and result Futures safe to await independently while
  preserving their original terminal errors for direct callers.

## 1.0.0-rc.2

- Promote the lockstep candidate cohort without public Dart API changes and
  bind release validation to the RC.2 source and evidence matrix.

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate and freeze internal
  dependencies at `>=1.0.0-rc.1 <1.0.0`.

- Restrict internal Dartitect dependencies to the exact lockstep 1.0
  prerelease series.

- Use an injected core `IdGenerator` for supervisor request correlation.
- Add versioned typed workers, readiness, ACK correlation, heartbeat,
  deadlines, remote failure/crash handling, and safe-stop lifecycle.
