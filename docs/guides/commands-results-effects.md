# Commands, results, and effects

[Português (Brasil)](commands-results-effects.pt-BR.md)

## Expected failures

Return `Result<T, F>` for expected domain/application failure. Callers must
handle both `Ok<T>` and `Err<F>`. Do not catch an arbitrary exception and turn
it into success or an unrelated expected failure.

## 1.0 command scheduling matrix

`Command0<T, F>`, `Command1<A, T, F>`, and dedicated
`KeyedCommand1<K, A, T, F>` use the same pure-Dart lane contracts. Every
retained FIFO, configured concurrency lane, and active-key set has an explicit
positive bound.

| Policy | Bound and admission | A busy call | Ordering and terminal publication |
| --- | --- | --- | --- |
| `reject` (default) | One running execution | `rejected(busy)` | The accepted execution publishes its terminal |
| `join` | One running execution | Returns the identical future; argument commands join only an equal running argument in the same key, otherwise `rejected(busy)` | One execution and one terminal identity |
| `drop` | One running execution | `dropped`; it does not start, queue, or replace retained state | The running execution alone may publish |
| `sequential(maxQueue)` | One running plus positive bounded FIFO; default queue is 64 | Queues FIFO or `rejected(queueFull)` | Every accepted execution runs in admission order |
| `restartLatest` | One publishable generation; superseded work may still drain cooperatively | Cancels/supersedes prior generations and starts a new one | Only the latest accepted generation may publish |
| `concurrent(maxConcurrent)` | Positive running bound; default is 4 | Starts within the bound or `rejected(concurrentLimit)` | A terminal publishes only if its execution ID is not older than the retained terminal |
| `keyed(perKey, maxConcurrent)` | Positive active-key bound, default 4; one non-keyed bounded policy per key | Applies the per-key result or `rejected(keyLimit)` for a new key | Keys schedule independently; a crash stops only its key |

## Command outcomes, cancellation, and crashes

Each distinct accepted call gets a monotonic execution ID. Observable state is
exhaustive (`idle`, `running`, `success`, expected `failure`, `cancelled`, or
`crashed`) and reports running/queued counts plus latest-accepted and retained-
terminal IDs. Call results remain separate:

- `succeeded(value)` and `failed(F, stack)` are accepted domain terminals;
  `Err<F>` is never reported as an unexpected error.
- `rejected(reason)` and `dropped` did not start and never replace retained
  terminal state.
- `cancelled(reason)` is control flow, never `F`. Cancellation is cooperative:
  the caller completes promptly, the action observes its lane-owned
  `CancellationSignal`, and owner disposal still drains the underlying action.
- An unexpected exception is reported at most once for that execution, retained
  as crash state, and rethrown with its original stack. It stops one lane or
  keyed lane until `resume()` after running work settles.

Late completion from a cancelled, superseded, older concurrent, or disposed
generation cannot publish state or notify listeners. `reset()` clears a
retained terminal only while the command is fully idle. Disposal is idempotent:
it closes admission, rejects queued work as disposed, requests cancellation,
drains running actions, clears Flutter future mappings, and sends no
post-disposal notification.

## 1.0 reactive resource matrix

Resource data (`waiting`, `ready`, expected `failed`, or unexpected `crashed`)
is independent from upstream temperature. Failed/crashed states may explicitly
retain nullable last-known data through `hasData`.

| Axis/value | Source activity | Retention/backpressure | Terminal or recovery rule |
| --- | --- | --- | --- |
| Temperature `hot` | One activation-local source session is active | Snapshot retained; reads admitted | Only current-generation publication is accepted |
| Temperature `warm` | No source session or read is active | Last-known snapshot may remain | Reactivation opens a fresh source session |
| Temperature `cold` | No source session or read is active | Snapshot and stale marker are discarded | Activation starts a fresh generation |
| `alwaysHot` | `start()` activates without observers | Hot until owner disposal | Disposal alone makes it cold |
| `whileObserved` | Hot while a ticker-enabled observation has a listener or a `ResourceLease` exists | No warm retention | Last activity release makes it cold |
| `keepWarm(duration)` | Same activity rule as `whileObserved` | Positive TTL retains a warm snapshot; reacquisition cancels the timer | TTL expiry makes it cold |
| `manual` | Only explicit `activate()` starts upstream | `deactivate(retainSnapshot: true)` is warm; `false` is cold | Leases/observers do not override manual control |
| `everyEmission` | One read at a time | Preserves every signal in a serial backlog; use only with an externally bounded source | Closing clears pending signals and cancels/drains the active read |
| `coalesceMicrotask` | One read at a time | At most one scheduled microtask and one dirty rerun while busy | Signals inside the boundary coalesce |
| `coalesceFrame` | One read at a time | At most one scheduled frame and one dirty rerun while busy | Signals inside the frame boundary coalesce |
| `latestWhileBusy` (default) | One read at a time | At most one dirty rerun while busy | A burst becomes the active read plus one latest rerun |

Each `ReactiveSource.open()` creates a fresh session that owns its watcher,
subscription, query, or cursor and borrows injected providers. An expected read
`Err<F>` publishes `ResourceFailed` without reporting or stopping the hot
session. An expected open failure suspends after publishing failure. An
unexpected open/read/stream error publishes `ResourceCrashed`, reports once per
source generation, closes the session, and suspends warm or cold according to
retention. Only explicit `retry()` resumes and opens a new generation.

A `ReactiveObservation` is caller-owned and contributes activity only while it
has a listener and ticker is enabled. Passive `LiveResource.addListener()` does
not activate upstream. A `ResourceLease` is owner-invalidated, idempotent, and
keeps automatic policies hot until its awaited release reconciles temperature.
Listener and reporter failures are isolated from state. `ResourceFamily` idle
retention is bounded by a positive TTL and non-negative count/weight budgets;
leased, observed, or hot entries are not evicted.

Resource disposal closes admission, invalidates leases and observations,
requests cooperative cancellation, drains reads, cancels the signal
subscription, closes the activation-local session, discards the snapshot,
clears listeners/bindings/timers, and aggregates independent cleanup failures.
Concurrent disposal shares one completion, and every late publication is
rejected.

## Effects

Use an owned `EffectChannel<E>` only for typed, immutable, transient UI
reactions. Its positive capacity is bounded; overflow and post-disposal emits
return explicit results. One logical consumer receives accepted effects once
in FIFO order. `EffectListener` borrows the channel and invokes the callback
with its current mounted context; the channel and ViewModel never retain
`BuildContext`.

Authentication/session truth is not an effect. Drive the application shell
from replayable `SessionStateController<S>`, remove authenticated routes on
`SessionForcedLogout`, then drain and close the old session graph. A new owner
generation gets a new effect channel and cannot receive pending effects from
the old generation.

## Test matrix

Cover every policy, success, expected failure, unexpected rethrow, queue/key
limits, busy/disposed, cancellation, stale completion, reporting once, effect
FIFO/overflow/detach/consumer failure, all data states and temperatures,
activation/lease/TTL transitions, every backpressure boundary, explicit retry,
forced logout during navigation, and no running, queued, pending-effect,
observer, lease, timer, read, source-session, family, or session resources after
disposal.
