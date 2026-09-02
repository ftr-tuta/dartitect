# Platform and background tests

- Privacy: prove construction and status are prompt-free, request occurs only
  after an explicit consumer action, unknown status fails closed, unsupported
  hosts make no channel call, and no status or choice enters telemetry.
- Media: cover Android legacy/current permission separation, iOS limited access,
  save-without-request, partial native rollback, main-thread completion,
  unsupported hosts, and `clearOwnedState()` residue. Never retain paths, names,
  bytes, album data, or native messages in test diagnostics.
- Transfer: corrupt or reorder chunks, cancel and resume, fail durable commit,
  preserve the idempotency key, and prove checkpoints advance only after a
  durable chunk commit. Pair a deterministic transport with the selected real
  provider adapter.
- Jobs and Workmanager: validate envelope versions, deduplication, bounds,
  deadline/cancellation, terminal receipts, fresh graph creation, teardown in
  `finally`, supported plugin callbacks, preview limitations, and typed
  unsupported hosts.
- Isolates: use a real isolate for readiness, ACK/result correlation, heartbeat,
  deadlines, crash/exit, stale envelope rejection, safe stop, and zero ports,
  timers, or requests after supervisor disposal.
- Resilience: inject clock, scheduler, randomness, and failure classification;
  cover bounds and never retry an uncertain mutation or an unexpected crash.
- DevTools: keep diagnostics v2 at exactly three read-only service extensions;
  test `ext.dartitect.observabilityPrivacy` as a separate registration. Reject
  mutation methods and payload-bearing facts, isolate registrations by runtime
  isolate, and prove product builds register nothing.
