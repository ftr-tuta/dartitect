# Titect integration

## Status and ownership

The optional `package:dartitect_sync/dartitect_sync_titect.dart` entrypoint adds
closed wire values and a binding over `SyncDataset.incremental`. It introduces
no transport, database, authentication provider, schema authority, broker client,
or new runtime. The consumer owns capability selection, HTTP resources, durable
transactions, session authority, conflict decisions and mutation reconciliation.

The committed Python reference and source versions are recorded in
`tool/titect_fixture/pin.json`. While `integrated` is false, all evidence is
candidate evidence and the PR stays in draft. Final acceptance requires reruns
against the Python commit integrated through protected `main`; no Python release
is required. The distributed Dartitect cohort stays `1.1.0` until publication
of the prepared `1.2.0` cohort.

The Python-owned corpus contains 232 cases with explicit byte and error
expectations. Its original 156 vectors are preserved unchanged. Dart only
renders that corpus for VM and Chrome; it does not redefine expectations.
The three copied bundles are `titect-sync/1`, `titect-message/1` and
`titect-message/2`. Their manifest hashes, inventories and bundle digests are
verified independently.

## Wire values and allocation

`TitectSyncCodec` reads sessions, dataset descriptors, bootstrap requests and
responses, snapshot and delta pages, reset requests, generation mismatches,
readiness, individual mutation outcomes and outcome batches. Constructors run
through `fromPayload`, which validates and deeply freezes the payload.

`TitectNumber` retains the original JSON numeric token. Protocol integer fields
use `BigInt`. `toIntExact()` accepts only the portable exact integer range;
`toDoubleExact()` compares the decimal value to its binary64 representation and
rejects loss of precision, overflow and nonzero underflow. Valid JSON exponents
are never expanded or limited by binary64. Consumer payloads retain numeric tokens at arbitrary
JSON positions. Supplying a `double` to the encoder is rejected; choose an exact
token explicitly. Cursors remain opaque strings, including their Unicode and
punctuation.

The default parser admits at most 1 MiB, depth 32 and 10,000 JSON values.
Strings and object keys are checked while parsing, before retention; upsert
payloads also obey the Python core's 16,384-scalar string limit. Invalid UTF-8,
unpaired surrogates, unknown fields and unsupported document versions fail with
a payload-free `TitectWireException`. Transport reads stop at the byte limit
without trusting `Content-Length`. Duplicate keys follow Python's last-value
rule, while every parsed occurrence still consumes allocation budget.

`requireCapabilities` checks an explicitly supported subset. Unknown capability
names remain legal bootstrap wire values, as in the pinned profile, and must be
rejected during adoption when unsupported. Reading advertised limits does not
authorize a larger local allocation budget or infer an endpoint schema.

## Exact encoding and integrity selection

Sync and the `/2` message fixture encode keys by Unicode scalar order, preserve
numeric tokens, use the normative JSON escapes, and emit no extra whitespace.
The `/1` message fixture explicitly selects legacy Python binary64 decimal
interpretation and formatting. No profile fallback is automatic.
`TitectWireProblem.code` exposes `syntax`, `limits`, `shape`,
`unsupported_profile`, `integrity` and `precision` without payload excerpts.

Request `integrity-sha-256-exact-json-v1` during bootstrap and pass its
`Titect-Sync-Integrity` response header to
`TitectSyncIntegritySelection.select`. Supply the selected
`TitectExactJsonSha256Integrity` policy explicitly. Persist the capability with
the consumer session, restore the selection with the same policy, and pass it
to both `TitectSyncCodec(integrity: selection)` and
`titectSyncDataset(integrity: selection)`. Each HTTP read supplies the actual
response header through `acknowledgement`. A response read without that selection
cannot enter a binding that requires it.

Verification hashes the ASCII prefix
`titect-sync/1`, NUL, `integrity-sha-256-exact-json-v1`, NUL, followed by the
complete exact JSON envelope with only `payload.integrity` removed. It covers
the protocol, page kind, dataset, generation, ordered items, exact values and
cursor. Digest and item count must match before the page is returned. Missing,
unexpected or changed confirmation is rejected. Without a selection, legacy
structural validation remains available. Hash verification does not supply
authentication; the consumer owns trust and authorization.

## Incremental composition and retry placement

Create `titectSyncDataset` with a selected dataset/generation, cursor projection,
one-attempt `fetch`, durable `apply`, retry executor, shared retry budget, and
finite page/byte limits. Pass the supplied `TitectReadBudget` to
`TitectSyncResponse.read`; failed reads remain charged. The binding checks that
the response used that exact budget. A malformed response never enters the
transaction. An application failure is not replayed automatically.

The binding owns page-fetch retries. Refresh, reconnect, mutation outbox and
background operations in the same consumer scope borrow the same `RetryBudget`;
upper layers forward feedback and do not reset it. Queueing, execution and
backoff consume the scope window. Preserve server minimums after jitter and
defer invalid, excessive or unaffordable hints. See
[HTTP retry budgets](http-retry-feedback.md).

The consumer transaction must compare persistent authority, apply the page and
persist its application proof before returning a checkpoint. The checkpoint
store must compare authority again and require that proof in its transaction.
The engine awaits confirmation before pulling another page. An in-memory
authority check alone does not reject a stale database writer. Pending local
mutations and uncertain outcomes require durable retention and explicit policy;
absence of a remote receipt never authorizes another delivery automatically.

## Executable evidence

`tool/run_titect_conformance.py` verifies manifest file hashes separately from
bundle digests, verifies the Python checkout, then runs the same raw vectors in
Python, Dart VM and Chrome. The message fixture is broker-free. Reports retain
acceptance and round-trip differences and the identity of the executed corpus.

`tool/run_titect_recovery.py` imports the fixed FastAPI composition, uses actual
SQLAlchemy/PostgreSQL transactions, and drives a Drift/SQLite process through
pipe barriers and process termination. Assertions reopen both databases through
new connections. The 24 scenarios retain the original 20 and add corrupted-page rejection,
negotiated-policy mismatch, exact-number persistence and unchanged durable state
and checkpoint after integrity failure and reopening. The original scenarios cover local/remote commits, lost responses, interrupted
bootstrap, page application, checkpoints, expired cursors, storage failure and
persistent fences.
It also executes the Django persistent-mutation reference, bounded mixed-flow
storms and real Chrome reload/reopen scenarios.

The web fixture supports verified shared storage profiles: `sharedIndexedDb`,
`opfsLocks` and `opfsShared`. It rejects in-memory and unsafe IndexedDB fallbacks.
For Drift 2.34.3's IndexedDB delegate, the fixture issues an awaited standalone
statement after each transaction to force the pending VFS flush before external
effects or checkpoint publication. Actual reload testing found that transaction
completion alone was insufficient. The barrier remains consumer-owned and is
tested against the fixed provider; no process-local store is used as evidence
of cross-context authority.

`tool/run_titect_capacity.py` uses the compiled Dart actor and the real Python,
PostgreSQL and JetStream fixture. Seed 41 offers 100/800/100 operations over two
seconds at 50/400/50 operations per second. Dart concurrency is two and its queue
holds four; attempt, byte, record and elapsed budgets are shared within each
scenario. Recovery kills the server halfway through offering, waits 200 ms before
restarting it, and observes Dart disconnect, reconnect and reconciliation.
Drain is limited to 20 seconds. Reports count every offer and refusal, retain
latency percentiles and raw observations, reconcile receipts/outbox/inbox and
assert zero owned resources. Existing Python limits remain 512 MiB RSS, 100 tasks
and eight connections. No latency target is introduced. The historical 30-operation
storm and the Python soak at its original SHA remain separate evidence.

Run the tools with an explicit clean Python checkout, `CHROME_EXECUTABLE`,
`TITECT_POSTGRES_DSN` and `TITECT_NATS_URL`. Each output directory must be new or
empty; failed reports are retained. Build the native actor with:

```console
dart build cli --root-package dartitect_drift \
  -t tool/titect_fixture/composition/native_actor.dart -o /tmp/titect-native
```

Use `--preliminary` only while the Python pin is unintegrated. Conformance writes
a `reference.json`; pass it to recovery and capacity with `--reference-manifest`.
A Python-owned candidate manifest may identify the subsequent commit that pins
the Dart candidate without rewriting the Dart pin. It verifies the actual clean
sources, versions, trees, corpus and bundles and remains ineligible for release.
Integrated acceptance fetches and verifies the Python SHA against upstream
`main`; it does not require Python's historical Dart pin to follow each Dart
commit. Every native launch verifies the executable hash.

`tool/collect_titect_evidence.py` collects matching stages. Readiness and Release
require the exact committed Dart SHA, CI execution, reference, native actor,
checksums, raw byte/error outcomes and all recovery/capacity scenarios. Isolated
passing reports cannot establish release readiness. Historical Python reports
retain the SHAs and workloads they actually measured.
