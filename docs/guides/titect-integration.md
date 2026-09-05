# Titect integration

## Status and ownership

The optional `package:dartitect_sync/dartitect_sync_titect.dart` entrypoint adds
closed wire values and a binding over `SyncDataset.incremental`. It introduces
no transport, database, authentication provider, schema authority, broker client,
or new runtime. The consumer owns capability selection, HTTP resources, durable
transactions, session authority, conflict decisions and mutation reconciliation.

Paired acceptance is currently preliminary. The Python reference is
`0537fde22b0ae881c21359c004ffabe7425a085c`; the source and bundle identities are
recorded in `tool/titect_fixture/pin.json`. This pin is not integrated into Python
`main`. Do not claim final compatibility or release readiness from these probes.

The 156-vector corpus currently exposes eight divergences on both Dart targets:
Python 3.14's acceptance of `24:00:00`; message canonicalization for decimal
precision, exponent spelling and underflow; CPython's default 4,300-digit integer
bound; and raw transport/allocation bounds for excessive whitespace and
overwritten duplicate values. Python sync validation receives an already parsed
mapping, so those last two raw-wire cases lose their original allocation history.
These results distinguish source package versions (`1.2.0` and `1.6.0rc1`) from
the protocol versions. A stable Python release is not required. The pinned sync profile validates SHA-256 digest shape and item
count, but does not specify the page bytes to hash. Those contracts require
resolution with the Python owner in issue #40 before final acceptance. The gate
records disagreements and fails; it never rounds numbers or invents page hash
semantics to make the implementations agree.

## Wire values and allocation

`TitectSyncCodec` reads sessions, dataset descriptors, bootstrap requests and
responses, snapshot and delta pages, reset requests, generation mismatches,
readiness, individual mutation outcomes and outcome batches. Constructors run
through `fromPayload`, which validates and deeply freezes the payload.

`TitectNumber` retains the original JSON numeric token. Protocol integer fields
use `BigInt`. `toIntExact()` accepts only the portable exact integer range;
`toDoubleExact()` compares the decimal value to its binary64 representation and
rejects loss of precision. Consumer payloads retain numeric tokens at arbitrary
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
new connections. The 20 scenarios cover local/remote commits, lost responses, interrupted
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

Run the tools with an explicit Python checkout, Chrome executable and disposable
PostgreSQL DSN. Build the native actor with:

```console
dart build cli --root-package dartitect_drift \
  -t tool/titect_fixture/composition/native_actor.dart -o /tmp/titect-native
```

Use `--preliminary` only while the Python pin is unintegrated. Missing services,
missing references and substituted evidence fail. Final acceptance requires an
integrated pin, a clean source tree, resolved protocol differences, current-SHA
reports and all required CI checks. Historical Python reports establish only
the SHAs recorded in those reports.
