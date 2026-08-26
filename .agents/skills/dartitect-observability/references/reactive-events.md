# Payload-free reactive events

`ReactiveChangeEvent` may contain only its fixed source and outcome kind, an
exact pre-registered static `ChangeCause`, monotonic revisions/duration, and
listener count. It never contains values, keys, idempotency IDs, error text,
stack traces, or user identity. Reject reconstructed or dynamic causes before
state changes begin.

Register observers as explicitly owned or borrowed. `ReactiveJournal` is a
bounded memory-only local diagnostic ring and clears permanently on disposal.
`ReactiveObserverLoggerAdapter` emits the fixed `reactive.change` message plus
allowlisted facts; normal runtime redaction still runs. A failing observer is
reported once, disabled, and cannot change runtime state or the caller's error.
