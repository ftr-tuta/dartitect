# RC5 paved-road platform

RC5 activates a set of provider-neutral paths that were previously deferred
for lack of independent evidence. RC5 is a development reference toward 1.0.0,
not a tag, release, publication, or promise that a consumer should adopt an
unreleased Git revision.

## Feature profiles

Choose one public behavior profile per feature:

| Profile | Authority and capability |
| --- | --- |
| `online` | Remote read authority; persistence must be `none` |
| `cache` | Remote authority with a consumer-owned durable local cache |
| `replica` | Locally queryable synchronized replica with optional headless sync |
| `offline-full` | Replica plus consumer-owned atomic mutation/outbox delivery |

The legacy blueprints remain aliases: `remote-read` maps to `online`,
`local-first` to `cache`, `sync-dataset` to `replica`, and
`offline-mutation` to the base of `offline-full`. `simple` remains a legacy
generated-once scaffold.

```console
dartitect create feature orders \
  --profile=offline-full \
  --persistence=drift \
  --transport=dio \
  --pagination=cursor \
  --headless-sync \
  --diagnostics=full
```

Generated-once entities, schemas, migrations, repositories, and business
rules become consumer-owned immediately. Dartitect may converge only manifests,
contract registries, and mechanical wiring. `verify` checks declarations;
behavioral guarantees belong in `FeatureContractMatrix` fixtures.

## Runtime path

`BootstrapCoordinator<R>` extends `ResourceTransaction` with named stages,
typed progress, cancellation, deadline handling, rollback, and a terminal
report. `ApplicationHost<R>` publishes only a fully committed application
graph and owns retry and teardown. `SessionRuntimeController<R, D>` and
`SessionHost` replace login, tenant, or forced-logout generations atomically.
The old session graph closes only after the consumer confirms that routes using
it were removed. Application resources outlive session resources.

`OperationProgress<P>` is the shared envelope. Its execution ID and sequence
are monotonic within an accepted operation. `CommandExecutionContext<P>` owns
cancellation, deadline checks, and bounded publication. Late progress from an
older command execution is rejected; existing command constructors remain
available.

`BoundedLocalHistory<T>` is synchronous, local, and value-only. It cannot
accept callbacks, futures, or streams and therefore cannot claim to undo HTTP,
upload, persistence, or sync. The Flutter listenable adapter is separate.

`VersionedRestorationCodec<T, F>` stores only a version and a consumer-coded
ephemeral UI payload in a Flutter restoration bucket. Invalid or future
versions return a typed failure and `RestorableVersionedValue` falls back to a
safe initial value. Do not store credentials, domain entities, repository
state, or outbox work in restoration.

`ReactiveLazyComputed<T>` declares every dependency explicitly. It evaluates
on first read or observation, stays dirty while unobserved, recomputes
atomically while observed, retains the last valid value after a failed compute,
and supports explicit hot-reload rebinding. It has no global read tracking.

## Resilience, jobs, and transfer

`dartitect_resilience` contains bounded retries, single-flight, circuit
breaker, bulkhead, and rate limiting. Inject clock, scheduler, and randomness
for deterministic tests. Retry only expected failures classified by the
consumer. An uncertain mutation result stops automatic retry; unexpected
exceptions still escape.

`dartitect_jobs` generalizes headless execution with versioned envelopes,
typed definitions and handlers, bounded dispatch, deduplication, deadlines,
cancellation, one `OwnedGraph` per job, and optional store/lease/fencing ports.
The consumer still owns scheduling, recurrence, credentials, payload schemas,
and cross-process policy. `dartitect_sync` adapts its headless endpoint through
this runtime without hidden retries.

`dartitect_transfer` coordinates source chunks, transport commits, checksums,
pause/resume/cancel, checkpoints, and typed progress. A checkpoint advances
only after the destination reports a durable chunk commit. ETag, Range,
idempotency, URL design, authentication, and remote protocol stay in the
consumer adapter. `DioTransferTransport` does not log URL, headers, body,
credentials, or chunk bytes.

## Diagnostics and DevTools

Diagnostics protocol v2 covers owners, graphs, commands, reactive nodes,
families, effects, sync, isolates, jobs, transfer, and hosts. The exact schema
contains closed enums, opaque process-local IDs, counters, generations,
revisions, and monotonic time. Arbitrary metadata, URLs, domain keys, error
messages, stack traces, and user identifiers are not accepted.

`dartitect_devtools` is optional and development-only. Explicit registration
installs exactly three isolate-local service extensions:

- `ext.dartitect.capabilities`
- `ext.dartitect.snapshot`
- `ext.dartitect.events`

They expose bounded payload-free data and no retry, cancellation, clearing, or
mutation command. Product builds do not register them. Disposal clears the
owned ring buffer. The bundled Flutter Web inspector follows the official
DevTools extension structure, while `examples/paved_road_canary` proves RPC
discovery, bounds, disposal, and release tree-shaking without tokens or private
services.

## Contract evidence

`dartitect_testing` provides `FeatureContractMatrix.online`, `.cache`,
`.replica`, and `.offlineFull`. Each matrix receives typed factories and
fixtures and returns framework-neutral row results. Every required row uses a
fresh fixture and attempts disposal. Add provider-native tests when the
contract depends on generated schemas, transactions, native SDKs, or platform
lifecycle.

`dartitect fleet report` aggregates declared versions, profiles, providers,
and detected matrix coverage without running a process. The separate
`DartitectFleetCanaryService` archives an exact commit, injects it only into a
temporary consumer copy, runs a closed command allowlist, sanitizes receipts,
verifies the original candidate and consumer are unchanged, and removes the
copy even after failure.
