# Changelog

## Unreleased

- Replace FIFO shifts with deque-backed command queues and progress retention.
- Keep bounded local-history weight accounting in O(1).
- Add the opt-in `dartitect_incremental.dart` entrypoint with cold sync/async
  producers, bounded admission, backpressured consume/fold/collect operations,
  explicit closeable sync sources, reports, and fixed-capacity ring buffers.

## 1.0.0

- Promote the validated RC10 source cohort to the stable GitHub-only release.

## 1.0.0-rc.10

- Join the RC10 business-neutral UI quality and evidence cohort.

## 1.0.0-rc.9

- Add semantic factory annotations and concrete application/session graph contracts while retaining generic assembly primitives as low-level APIs.

## 1.0.0-rc.8

- Prepare the package for the RC8 greenfield platform baseline and compatible post-1.0 publication cohorts.
- Add target-aware feature profiles, typed project-local extension contracts,
  credential generations/leases, and generation-fenced invalidation.

## 1.0.0-rc.6

- Complete this package's lockstep RC6 vertical-platform contracts.

## 1.0.0-rc.5

- Join the lockstep RC5 paved-road source cohort without creating a tag,
  release, or publication.

## 1.0.0-rc.4

- Keep the core free of modeling annotations while retaining the shared
  `ValueEquality` and `Result` primitives reexported by `dartitect_modeling`.

## 1.0.0-rc.3

- Add experimental diagnostics protocol v1 with fixed payload-free subjects
  and phases, opaque emitter-owned IDs, bounded buffers, explicit reporter
  ownership, failure isolation, and off/lifecycle/topology detail.

- Report old-generation cleanup failures after a successful
  `OwnedRuntimeSlot` publication through
  `OwnedRuntimeReplacementCleanupException`, including the authoritative
  published generation.
- Make command-lane transition callbacks safe to cancel or dispose the lane
  reentrantly for every unkeyed and keyed scheduling policy.

## 1.0.0-rc.2

- Promote the lockstep candidate cohort without public Dart API changes and
  bind release validation to the RC.2 source and evidence matrix.

## 1.0.0-rc.1

- Assemble the reviewed lockstep 1.0 release candidate without public API
  changes from the development cohort.

- Add passive `DartitectValue`, injectable `IdGenerator`, and secure RFC 9562
  UUID v4 generation without global state.
- Add transactional `ResourceTransaction`, draining `OwnedGraph`, atomic
  `OwnedRuntimeSlot`, and immutable local-authority `ResourceSnapshot`.
- Add explicit inline/background projection execution, transferable
  generation-tagged requests/results, and a draining per-task isolate executor.
- Add registered static change causes, payload-free reactive events, explicit
  observer ownership, failure isolation, and an opt-in bounded memory journal.
- Add local-first `MutationCommand` lanes, durable outbox contracts, explicit
  idempotency, typed commit/sync states, bounded transient retries, session
  recovery, uncertain crash handling, and explicit compensation.
- Add cooperative cancellation plus bounded, typed no-argument and keyed
  command lanes.
- Initial Native-First Result and lifecycle contracts.
