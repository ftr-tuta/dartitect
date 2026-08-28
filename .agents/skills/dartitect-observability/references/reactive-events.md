# Payload-free reactive events

`ReactiveChangeEvent` may contain only its fixed source and outcome kind, an
exact pre-registered static `ChangeCause`, monotonic revisions/duration, and
listener count. It never contains values, keys, idempotency IDs, error text,
stack traces, or user identity. Reject reconstructed or dynamic causes before
state changes begin.

Diagnostics protocol v2 adds fixed owner/graph/node/command/resource/family/
effect/sync/isolate/job/transfer/host subjects and fixed lifecycle phases. An
event has only its exact schema version, emitter sequence, opaque process-local
IDs, generation, revision, and monotonic time. IDs come only from the emitter's
injected generator and never from application identifiers. The decoder rejects
unknown fields.

Register observers as explicitly owned or borrowed. `ReactiveJournal` is a
bounded memory-only local diagnostic ring and clears permanently on disposal.
`ReactiveObserverLoggerAdapter` emits the fixed `reactive.change` message plus
allowlisted facts; normal runtime redaction still runs. A failing observer is
reported once, disabled, and cannot change runtime state or the caller's error.

`DartitectDiagnosticBuffer` is bounded and clears every retained event on
dispose. `SafeDartitectDiagnosticReporter` isolates reentrancy and destination
failure. Off detail allocates no subject ID; lifecycle detail retains every
failure/crash terminal; topology detail supports
`DiagnosticsTopologyHarness`. Construction/reporting APIs remain experimental
under ADR 0034/0043 and install no remote destination or global Flutter hook.
The optional DevTools bridge registers exactly `capabilities`, `snapshot`, and
`events` RPCs per isolate; it has no mutation surface and is absent from product
builds.
