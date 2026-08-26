# Changelog

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
