/// Immutable template for one skill distributed by `dartitect codex sync`.
final class DartitectSkillTemplate {
  /// Creates a complete managed-skill template.
  const DartitectSkillTemplate({
    required this.name,
    required this.displayName,
    required this.shortDescription,
    required this.defaultPrompt,
    required this.files,
  });

  /// Stable directory and invocation name.
  final String name;

  /// Human-facing name used by Codex interfaces.
  final String displayName;

  /// Short human-facing summary used by Codex interfaces.
  final String shortDescription;

  /// Skill-specific prompt inserted by Codex interfaces.
  final String defaultPrompt;

  /// Relative skill files, excluding generated metadata and manifest.
  final Map<String, String> files;

  /// Complete UI metadata generated alongside the skill.
  String get openAiYaml =>
      '''interface:
  display_name: "$displayName"
  short_description: "$shortDescription"
  default_prompt: "$defaultPrompt"
policy:
  allow_implicit_invocation: true
''';
}

/// Typed skill templates distributed by `dartitect codex sync`.
const List<DartitectSkillTemplate>
dartitectSkillCatalog = <DartitectSkillTemplate>[
  DartitectSkillTemplate(
    name: 'dartitect-design',
    displayName: 'Dartitect Design',
    shortDescription: 'Choose the smallest Dartitect package set',
    defaultPrompt:
        r'Use $dartitect-design to select a minimal Dartitect architecture.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-design
description: Select the smallest Dartitect package and skill stack for a new Dart/Flutter application or feature. Use for architecture choices; do not use for conformance auditing or detailed implementation.
---

# Design with Dartitect

## When to use

Use this skill before implementing a new application, feature, composition root,
or provider boundary when the required Dartitect packages are not yet clear.

## When not to use

Use `$dartitect-audit` to inspect a Dartitect-created project without changing it.
Route detailed runtime, reactive, offline-first, telemetry, adapter, testing,
CLI, or MCP work to the matching focused skill after suitability and the stack
are decided.

## Invariants

Choose the smallest stack that satisfies the feature. Riverpod, BLoC, Provider,
GetIt, MobX, Signals, and equivalent architecture runtimes are incompatible with
the Native Strict application graph. Keep domain/application contracts
provider-neutral, use constructor injection, and make every resource owned or
borrowed. Do not add a container, global runtime, provider package, or remote
telemetry without a stated requirement.

## Workflow

1. Decide whether Dartitect's constructor-injection, single-owner, typed-failure,
   local-authority, and sanitized-telemetry principles fit the target. If they
   do not, recommend not adopting Dartitect.
2. Classify the target as pure Dart, basic Flutter, reactive UI, durable
   mutation/outbox, dataset sync, headless sync, provider integration, or
   development tooling.
3. Identify platforms, authoritative data source, failure model, lifecycle
   owner, isolate boundaries, and telemetry policy.
4. Select only the packages and focused skills needed for those boundaries.
5. Reject provider leakage, service location, duplicate ownership, and
   competing application runtimes.
6. Record explicit exclusions so optional packages do not become defaults.

Read [references/selection-matrix.md](references/selection-matrix.md) when
choosing packages or routing the implementation.

## Validate

Confirm every selected package owns a concrete responsibility, every provider
stays at infrastructure composition, and removing any unneeded package would not
break a stated requirement.
''',
      'references/selection-matrix.md': r'''# Selection matrix

- Pure Dart result/ownership/composition: `dartitect` plus `$dartitect-runtime`.
- Immutable values, explicit JSON, projections, or pure boundary mappers: add
  `dartitect_modeling` and `$dartitect-modeling`; capabilities remain separately
  opt-in and Analyzer tooling stays out of runtime.
- Basic Flutter ViewModels and commands: add `dartitect_flutter` and keep the
  established `dartitect_flutter.dart` entrypoint.
- Hot/warm/cold resources, causal refresh, families, collections, selectors, or
  advanced builders: use the opt-in reactive entrypoint and
  `$dartitect-reactive`.
- Local-authority paging or durable mutations/outbox: combine the reactive
  runtime with `$dartitect-offline-first`; add a storage adapter only after the
  application chooses its provider.
- Dataset DAG orchestration, checkpoints, leases, progress, or headless ACKs:
  add `dartitect_sync` and `dartitect_jobs` with `$dartitect-offline-first`;
  keep scheduling, recurrence, conflicts, storage transactions, and provider
  resources consumer-owned.
- Bounded retry, single-flight, breaker, bulkhead, or rate limiting: add
  `dartitect_resilience`; expected-failure classification remains
  consumer-owned and uncertain mutation results are never retried.
- Resumable chunk transfer: add `dartitect_transfer` and optionally
  `dartitect_dio`; checkpoints follow durable chunk commits, while remote
  protocol, authentication, Range, ETag, and idempotency remain consumer-owned.
- Neutral logs/reporting/tracing: add `dartitect_observability` and
  `$dartitect-observability`; add `dartitect_sentry` only for an already selected
  and consumer-initialized Sentry Hub.
- Dio, Drift, or ObjectBox integration: add only the matching adapter and use
  `$dartitect-adapters`.
- Deterministic consumer tests: add `dartitect_testing` as a dev dependency and
  use `$dartitect-testing`.
- Inspection, generators, policy, or CI gates: use `dartitect_cli` and/or
  `dartitect_lints` with `$dartitect-tooling`.
- Local bounded agent context: add `dartitect_mcp` as a dev dependency and use
  `$dartitect-mcp`; scripts should call the CLI directly.

ObjectBox has no web support. CLI and MCP run on the Dart VM. Material widgets
belong only in Material presentation code. Provider adapters never belong in
domain, application, ViewModel, or presentation layers.

Native Strict does not provide an overlap or coexistence mode for competing
application architecture runtimes.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-audit',
    displayName: 'Dartitect Audit',
    shortDescription: 'Audit Native Strict conformance read-only',
    defaultPrompt: r'Use $dartitect-audit to audit Native Strict conformance.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-audit
description: Audit a Dartitect-created project for Native Strict conformance without changing it. Use for read-only evidence after development or a Dartitect SDK upgrade.
---

# Audit Dartitect conformance

## When to use

Use this skill when a project created with Dartitect must revalidate its
architecture, globals, providers, lifecycle, or SDK upgrade evidence.

## When not to use

Use `$dartitect-design` for implementation choices. Do not use this skill to
perform migration or authorize provider leakage, service location, duplicate
ownership, or concrete runtime boundaries.

## Invariants

Inspection is read-only. Report evidence without modifying code, dependencies,
configuration or generated files. Treat `dartitect verify` and `dartitect scan`
as canonical read-only evidence. Installed Riverpod, BLoC,
Provider, GetIt, MobX, Signals, or equivalent architecture runtimes are Native
Strict errors. Provider leakage, service location, duplicate ownership, and
dual-write are also errors.

## Workflow

1. Record tests, analyzer, `dartitect doctor`, `dartitect scan`, and
   `dartitect inspect --consumer-tax --json`.
2. Inventory composition roots, owners, disposal order, repositories,
   background entrypoints, provider SDKs, and telemetry paths.
3. Classify each boundary as conforming, non-conforming, or not evidenced.
4. Record prohibited runtime packages separately from advisory alternatives and
   approved consumer-owned infrastructure.
5. Return a conformance report, upgrade observations, and the exact commands
   used; do not mutate or claim adoption or automatic conversion.

Read [references/inventory.md](references/inventory.md) for evidence collection
and [references/conformance-audit.md](references/conformance-audit.md) for the
CLI/MCP boundary.

## Validate

Confirm the report is reproducible, contains no write or migration action, uses
the strict scan, and distinguishes unsupported architecture runtimes from
consumer-owned infrastructure packages.
''',
      'references/inventory.md': r'''# Dartitect project inventory

Record:

- app, session, route, and background-isolate composition roots;
- global singletons, service locators, clients, Stores, subscriptions, timers,
  commands, ViewModels, and error handlers;
- which resources are created, borrowed, disposed, or leaked at each root;
- domain/application contracts and infrastructure imports crossing inward;
- expected failure types versus unexpected exceptions;
- local versus remote data authority, queues/outboxes, retry and conflict rules;
- logging, error capture, tracing, redaction, and duplicate provider hooks;
- generated code and consumer-owned schemas that Dartitect must not replace.

Keep an evidence table with current behavior, owner, Native Strict boundary,
test evidence, and conformance status. Do not add a proposed migration slice.
''',
      'references/conformance-audit.md': r'''# Conformance audit

Start with read-only CLI operations. `inspect`, `scan`, and `doctor` do not write.
Run `dartitect scan` as the canonical gate. Greenfield projects cannot hide
architecture findings behind debt baselines.

The local MCP may assist discovery with bounded inspect, scan, doctor, explain,
conformance, and preview tools. `dartitect_audit_conformance` reports strict
evidence; it never performs migration. Preview/apply
tools are separate capabilities and are outside a conformance audit.

Report constructor boundaries, ownership, provider leakage, runtime conflicts,
and missing evidence. Riverpod, BLoC, Provider, GetIt, MobX, Signals, and
equivalent architecture runtimes are prohibited. Provider leakage, service
location, duplicate ownership, concrete boundary crossings, and dual-write are
errors.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-runtime',
    displayName: 'Dartitect Runtime',
    shortDescription: 'Build core and basic Flutter runtimes',
    defaultPrompt:
        r'Use $dartitect-runtime to implement an owned Dartitect runtime.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-runtime
description: Implement Dartitect Result, ownership, composition, commands, ViewModels, isolates, and basic Flutter bindings. Use for core or thin Flutter runtime work; route advanced reactive and offline-first behavior to their focused skills.
---

# Build a Dartitect runtime

## When to use

Use this skill for `Result<T, F>`, resource ownership, composition roots, typed
progress, bounded local history, `Command0`, ViewModels, application and session
hosts, versioned UI restoration, isolate graphs, and the basic
`dartitect_flutter.dart` entrypoint.

## When not to use

Use `$dartitect-reactive` for `ReactiveOwner`, `LiveResource`, resource families,
live collections, or advanced builders. Use `$dartitect-offline-first` for local
authority, paging, durable mutations, or outbox recovery.

## Invariants

Use constructor injection. Record every resource as owned or borrowed and
dispose dependents before dependencies. Build a fresh graph per app, session,
route, or background isolate. Transfer configuration and validated trace
context—not clients, Stores, subscriptions, or other live resources.

Expected failures use `Result<T, F>`. Unexpected exceptions remain crashes, may
be reported once, and are rethrown with their stack. Keep `BuildContext` out of
ViewModels, domain, repositories, and services.
Application bootstrap extends `ResourceTransaction`; do not create parallel
ownership primitives. Replace session graphs only after explicit route-removal
confirmation, and let application resources outlive them.

## Workflow

Define failure types and contracts, build the smallest composition root, wire
commands/ViewModels, then document ownership and reverse disposal. Select
`ViewModelHost.create` for owned values and `.value` for borrowed values.

Read [references/results-and-commands.md](references/results-and-commands.md),
[references/ownership-and-isolates.md](references/ownership-and-isolates.md), or
[references/basic-flutter.md](references/basic-flutter.md) only for the boundary
being implemented.

## Validate

Test `Ok`/`Err`, crash rethrow, cancellation or busy policy, disposal order,
owned/borrowed host behavior, stale completion, and zero notifications or
resources after disposal.
''',
      'references/results-and-commands.md': r'''# Results and commands

Use `Result<T, F>` only for expected failures a caller can handle. Do not erase
failure types, stringify them at the domain boundary, or translate an unexpected
exception into `Err` without an explicit recovery contract.

`Command0<T, F>`, `Command1<A, T, F>`, and dedicated
`KeyedCommand1<K, A, T, F>` expose expected `Err<F>` as state and do not report
it automatically. Reject is the default; join, drop, bounded sequential,
restart-latest, bounded concurrent, and bounded keyed policies are explicit. An
unexpected exception transitions to crashed, can be reported once through an
injected reporter, and is rethrown. A disposed command is terminal and does not
notify. One-shot navigation/snackbar effects use a bounded, route-owned,
single-consumer channel rather than being replayed as command data.

Use `OperationProgress<P>` and `CommandExecutionContext<P>` for typed bounded
progress. Execution IDs fence old work and sequences increase within one
execution. `ProgressCommand0`, `ProgressCommand1`, and `KeyedProgressCommand1`
retain the established concurrency contracts and reject late progress.
''',
      'references/ownership-and-isolates.md': r'''# Ownership and isolates

The composition root creates dependencies from longest-lived to shortest-lived
and disposes them in reverse. Dispose bindings and commands, then subscriptions,
watchers and queries, then clients and Stores, then flush/dispose owned
observability. Consumer-owned providers close after all Dartitect borrowers.

Each isolate creates a fresh graph from transferable configuration. Validate
incoming trace context before using it. Never transfer a live client, Store,
owner, command, ViewModel, subscription, timer, or callback closure that captures
one. Close isolate-local resources in `finally`.
''',
      'references/basic-flutter.md': r'''# Basic Flutter runtime

Use `ViewModelHost.create` when the widget subtree creates and owns the ViewModel;
use `ViewModelHost.value` when a route/composition root owns it. The host must not
dispose a borrowed value. `ViewModelHost.create` may call `start` exactly once;
the first build never waits for it, and readiness remains explicit state. Use
selected listenable builders to narrow rebuilds and pause their local listeners
under disabled `TickerMode`.

Create commands and bounded `EffectChannel` values outside `build`, bind their
state/effects declaratively, and drain them with their owner. Only
`EffectListener` uses its current mounted context. Keep `BuildContext` and
navigation out of the ViewModel. Use replayable `SessionState`, not an effect,
for forced logout and remove routes before closing the old session graph. For
hot/warm/cold resources or advanced list/page builders, switch to
`$dartitect-reactive` instead of growing the basic runtime ad hoc.

Use `ApplicationHost` for named cancellable bootstrap, retry, atomic graph
publication, and teardown. Use `SessionRuntimeController`/`SessionHost` for
login, logout, tenant switch, and route-confirmed generation replacement.
Versioned restoration accepts only consumer codecs/migrations and ephemeral UI
payloads; invalid data falls back safely. `BoundedLocalHistory` is value-only
and cannot claim to undo persistence, HTTP, upload, sync, or another effect.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-reactive',
    displayName: 'Dartitect Reactive',
    shortDescription: 'Build causal reactive Flutter runtimes',
    defaultPrompt:
        r'Use $dartitect-reactive to implement a causal reactive feature.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-reactive
description: Implement Dartitect ReactiveOwner, hot/warm/cold lifecycle, LiveResource, causal refresh, families, collections, selectors, and headless builders. Use for the opt-in advanced Flutter reactive runtime; do not use for basic commands/ViewModels or durable offline mutations.
---

# Build a reactive Dartitect runtime

## When to use

Use this skill when a feature needs explicit dependency tracking, temperature,
authoritative live sources, causal refresh, bounded keyed resources, incremental
collections, explicit-dependency derived async resources, selectors, debounce,
or reactive Flutter builders.

## When not to use

Use `$dartitect-runtime` for basic commands and ViewModels. Use
`$dartitect-offline-first` when paging or mutation correctness depends on local
database authority, an outbox, retries, conflicts, or crash recovery.

## Invariants

One `ReactiveOwner` owns a graph; disposed owners are terminal. Resource data
state is separate from hot/warm/cold temperature. Sources create activation-local
sessions and borrow injected providers. Refresh completion must name its causal
boundary. Collections publish complete validated updates atomically. Widgets
borrow resources and never dispose them from `build`.

## Workflow

Choose owner and activation policy, model the authoritative source, select the
required refresh completion type, then add bounded families/collections and the
smallest builder entrypoint. State backpressure, retry, retention, and disposal
semantics explicitly.
For a derived resource, also name every dependency, stale-data policy, equality
rule, cancellation behavior, and generation guard. Reuse the existing family
boundary rather than creating a parallel key cache.

Read [references/lifecycle-and-resources.md](references/lifecycle-and-resources.md),
[references/families-and-collections.md](references/families-and-collections.md),
or [references/selectors-and-builders.md](references/selectors-and-builders.md)
for the feature being implemented.

## Validate

Test hot/warm/cold transitions, stale-publication rejection, expected failure,
crash-and-explicit-retry, backpressure, exact causal refresh, bounded eviction,
atomic collection failure, selected rebuilds, TickerMode pause, and complete
graph cleanup.
''',
      'references/lifecycle-and-resources.md':
          r'''# Lifecycle and live resources

Nested `ReactiveOwner.update` calls join the outer transaction; listeners run
only after affected computed values stabilize. A compute crash preserves the
prior graph snapshot, is reported through the injected reporter, and is
rethrown. Disposal removes every edge and listener.

`ReactiveLazyComputed<T>` declares dependencies explicitly, evaluates on first
read or observation, marks dirty while unobserved, and recomputes atomically
while observed. A compute failure preserves its last valid value and remains
dirty. Hot reload uses explicit `rebind`; never add ambient read tracking.

`LiveResource<T, F>` separates waiting/ready/failed/crashed data from hot/warm/
cold temperature. A hot resource owns an active source session, warm retains
last-known data without upstream activity, and cold discards both. Use an
`AsyncLifecycleBarrier` so disposal closes admission, cancels cooperatively,
drains admitted work, and rejects stale publication.

`DerivedAsyncResource<T, F>` is stable and accepts a non-empty, identity-unique
list of explicit Flutter `Listenable` dependencies. It uses
restart-latest cancellation plus dependency and lifecycle generation guards;
an old non-cooperative result never publishes. Select preserve, discard, or
stale-while-revalidate last-data policy and explicit equality. It wraps one
`LiveResource`; return `.liveResource` from an existing `ResourceFamily`
factory so typed key, leases, TTL, count/weight limits, and eviction remain
family-owned. Do not add implicit read tracking or replace global hooks.

Select `RemoteRefresh`, `LocalCommitRefresh`, or `ObservedLocalRefresh` according
to the completion the caller needs. Observed refresh waits for the exact typed
revision and requires a positive timeout mapped explicitly to `F`.
''',
      'references/families-and-collections.md': r'''# Families and collections

`ResourceFamily<K, T, F>` shares equal keys only inside one explicit family.
Acquire and release a `FamilyLease` per retained consumer. Bound idle entries by
positive TTL, count, and weight. Never evict active leases, observers, or hot
resources. Remove an entry from the index before asynchronous disposal so a
reacquisition creates a new generation.

`LiveCollection<K, T>` keeps stable item nodes and publishes membership, order,
length, and item changes separately. Select `replaceAll`, `diffByKey`, or
`versionedByKey` explicitly. Validate keys and the entire projection before one
atomic publication. Duplicate keys, projection crashes, cancellation, or stale
background completion preserve the prior snapshot. Removed nodes retain a
tombstone only while listeners or configured warm retention require it.
''',
      'references/selectors-and-builders.md': r'''# Selectors and builders

`ReactiveSelector<S, T>` owns one subscription to a borrowed `Listenable` and
notifies only when its configured equality changes. `DebouncedReactiveValue<T>`
owns its timer, publishes only the latest distinct value, supports explicit
`flush()`, and cancels pending publication on dispose.

Import `dartitect_flutter_reactive.dart` for headless `ReactiveValueBuilder`,
`LiveResourceBuilder`, `LiveCollectionBuilder`, and `PagedLiveBuilder`.
Material or Cupertino rendering stays in consumer presentation. Collection
builders observe structure; render stable `LiveItem` values separately so one
item does not rebuild the list. TickerMode pauses observations and offscreen
rebuilds. Route/composition owners drain and dispose borrowed resources outside
`build`. Consumer views require localized labels, stable semantics, keyboard
access, and supported text-scale tests.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-offline-first',
    displayName: 'Dartitect Offline First',
    shortDescription: 'Build local-authority pages and outboxes',
    defaultPrompt: r'Use $dartitect-offline-first to implement a durable local-first flow.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-offline-first
description: Implement Dartitect local-authority pagination, mutations, durable outbox delivery, idempotency, retries, conflicts, compensation, and crash recovery. Use for offline-first correctness; do not use for generic reactive UI or provider setup alone.
---

# Build offline-first Dartitect flows

## When to use

Use this skill when the local store is authoritative for presentation and a
page, durable mutation/outbox, dataset DAG, or headless sync command crosses an
explicit durable or process boundary.

## When not to use

Use `$dartitect-reactive` for live UI without persistence/delivery semantics.
Use `$dartitect-adapters` to wire a chosen database or transport provider after
the repository contracts are defined.

## Invariants

Remote data never patches presentation state directly. The repository-owned
local transaction is authoritative. A mutation changes domain data and enqueues
its outbox operation atomically. Reuse one non-empty consumer-scoped idempotency
key for every at-least-once attempt. Persist acknowledgement before reporting
synced. Never auto-rollback queued or uncertain changes.

## Workflow

First select the mechanism: local-authority paging, durable mutation/outbox,
dataset DAG synchronization, or headless synchronization. Do not use an outbox
as a checkpoint, a run journal as domain data, or a headless receipt as proof
of exactly-once remote work. Then define local snapshot/revision or durable
record contracts, map expected failures, choose retry/conflict/compensation
ownership, and specify recovery. Add provider integration only at the
infrastructure composition root.

Read [references/local-first-pagination.md](references/local-first-pagination.md)
for pages, [references/mutations-and-outbox.md](references/mutations-and-outbox.md)
for writes and recovery, or [references/sync-execution.md](references/sync-execution.md)
for foreground/headless dataset orchestration.

## Validate

Test duplicate remote items, cancellation before local commit, exact-revision
observation, stale search, same-key serialization, different-key concurrency,
idempotent retries, rejection/conflict/uncertain outcomes, compensation,
acknowledgement persistence failure, crash recovery, and zero residual work.
''',
      'references/local-first-pagination.md': r'''# Local-first pagination

`PagedLiveResource<C, K, T, F>` requests a `PageBatch`, deduplicates by the
consumer key callback, and gives a `PageWrite` to the repository-owned local
transaction. The transaction returns a `PageWriteReceipt`; advance the cursor
only after the borrowed `LiveResource<PagedLocalSnapshot<K, T>, F>` publishes
that exact revision. Update the exposed `LiveCollection` only from the local
snapshot.

Refresh uses a joining lane, load-more drops reentrant calls, and search uses
restart-latest. Check cancellation before local write so a stale search cannot
patch the database. Expected request, write, or observation-timeout failure
preserves last local data and the valid cursor. Keep the synchronous timeline
bounded to phase facts rather than domain payloads.
''',
      'references/mutations-and-outbox.md': r'''# Mutations and outbox

`MutationCommand<A, K, T, F>` serializes operations per entity key. The
`MutationOutboxStore.applyLocalAndEnqueue` implementation performs the domain
write and persists `OutboxOperation` in one transaction. Dartitect does not
define entities, outbox schema, endpoints, or conflict rules.

Map expected delivery failures through `MutationFailurePolicy` to pending,
rejected, conflicted, or uncertain. Only definitive rejection may run an
explicit compensation transaction. Transient retries are opt-in, bounded, and
reuse the operation/idempotency key. An unexpected delivery crash is reported
once and rethrown; if delivery may have committed, persist uncertainty and stop
only that key lane until repository audit, a deliberate pending decision, and
`resume(key)`. On a new session, `recoverPending()` deduplicates idempotency keys
and drains pending records only; uncertain records require human/domain policy.
''',
      'references/sync-execution.md': r'''# Sync execution

Dataset DAG synchronization and headless synchronization are separate flows.
Use `SyncEngine` for a validated dataset DAG, checkpoints, journals, leases/
fencing, progress, and deadlines. Use `HeadlessSyncEndpoint` for a versioned
sync definition adapted through `dartitect_jobs`, bounded duplicate retention,
separate acceptance and terminal acknowledgements, and a fresh graph per
admitted request.

For a dataset run, the repository operation commits remote results into the authoritative local
transaction before returning a confirmed checkpoint. A failed dependency blocks
only downstream datasets; independent branches continue.

Treat checkpoint, lease, and optional cleanup ports as borrowed. With a lease,
call `context.authority.ensureAuthority()` immediately before the dataset commit
and atomically compare/commit its fencing token in a capable consumer Store.
Persist the same token with checkpoint writes. If storage cannot enforce the
token, explicitly declare dataset fencing unsupported. Inspect application,
checkpoint, journal, lease-release, and cleanup receipts before retrying a
`SyncRunTerminalException`.

For headless work, validate payloads before graph creation, create a fresh `OwnedGraph`
per accepted request, deduplicate request IDs, and transfer data rather than
provider objects. Retry, scheduling, authentication, conflicts, schemas, and
durable cross-process deduplication remain consumer policy. Expected failure
returns `Err`; an unexpected exception preserves its cause/stack and is never
retried automatically.

Use `RetryExecutor` only with explicit expected-failure classification, budget,
deadline, and injected timing/randomness in tests. An uncertain result always
stops retry. Use `JobDispatcher` for generic bounded headless definitions and
one graph per job; scheduling, recurrence, credentials, schemas, and durable
cross-process policy remain outside the SDK. Use `TransferEngine` for chunks,
pause/resume/cancel, checksums, and post-commit checkpoints; remote protocol,
ETag, Range, auth, and idempotency remain consumer policy.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-observability',
    displayName: 'Dartitect Observability',
    shortDescription: 'Configure private provider-neutral telemetry',
    defaultPrompt: r'Use $dartitect-observability to design sanitized Dartitect telemetry.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-observability
description: Configure Dartitect provider-neutral logging, reporting, W3C tracing, redaction, Flutter bindings, and payload-free reactive events. Use for telemetry contracts and policy; use the adapters skill for provider-specific wiring.
---

# Configure Dartitect observability

## When to use

Use this skill for `ObservabilityRuntime`, redaction/sampling/dispatch policy,
error reporting, W3C propagation, Flutter error capture, or reactive diagnostic
events and the versioned payload-free topology/lifecycle protocol.

## When not to use

Use `$dartitect-adapters` for Dio, Drift, ObjectBox, Sentry, or custom provider wiring.
Do not add remote telemetry merely because observability contracts exist.

## Invariants

Create the runtime explicitly; local developer logging is the safe default and
remote destinations are opt-in. Sanitize before every destination. Never record
credentials, authorization, cookies, bodies, headers, query strings, DSNs,
identity, identifying paths, domain payloads, or dynamic error text in reactive
events. Errors/fatal are never sampled away. Destination failure stays isolated.

## Workflow

Define the data policy first, then choose owned/borrowed sinks, reporter, tracer,
propagator, Flutter binding, reactive observers, and diagnostic detail. End every
span exactly once and define reverse flush/disposal. Use only emitter-owned
opaque IDs; keep buffers bounded and clear them on dispose.

Read [references/telemetry-contract.md](references/telemetry-contract.md),
[references/flutter-and-providers.md](references/flutter-and-providers.md), or
[references/reactive-events.md](references/reactive-events.md) for the boundary
being configured.

## Validate

Test redaction at every destination, unsampled error/fatal delivery, sink
isolation, queue bounds, exact-once span end, trace-context validation,
handler chaining/restoration/recursion, borrowed provider lifetime, and absence
of payload or identity in reactive events.
''',
      'references/telemetry-contract.md': r'''# Telemetry contract

Accept only valid W3C `traceparent`, forward optional `tracestate`, and keep
baggage off by default. Transfer only validated context between isolates. End
operation spans exactly once in `finally`.

Expected `Err<F>` remains command state and is not automatically reported.
Unexpected crashes may be reported once with sanitized mechanism, handled state,
fingerprint, and allowlisted attributes, then are rethrown with the original
stack. Errors and fatal events bypass sampling. Bounded destination queues must
have explicit overflow behavior, and one destination failure cannot affect the
application or another destination.

Diagnostics protocol v2 permits only fixed enums, opaque process-local IDs,
counters, generations, revisions, and monotonic time. It rejects metadata,
URLs, domain keys, dynamic errors, stacks, and user identifiers. Optional
DevTools registration is explicit, isolate-local, development-only, and exposes
capabilities, snapshot, and event-delta reads only; disposal clears the ring.
''',
      'references/flutter-and-providers.md': r'''# Flutter and providers

Install one `FlutterErrorBinding`. Chain the previous Flutter/platform handlers,
prevent recursion, and restore exactly those handlers on disposal. Keep
foreground capture separate from background-isolate reporting.

Provider SDK initialization, credentials, release/environment configuration,
consent, and shutdown belong to the consumer. Provider adapters borrow injected
SDK objects unless their registration explicitly owns them. For Sentry, borrow
the consumer-initialized Hub; never initialize, configure, or close it. Reject
duplicate capture or tracing such as simultaneous Dartitect Dio instrumentation
and `sentry_dio`.
''',
      'references/reactive-events.md': r'''# Payload-free reactive events

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
`DiagnosticsTopologyHarness`. Construction/reporting APIs are stable under ADR
0044 and install no remote destination or global Flutter hook.
The optional DevTools bridge registers exactly `capabilities`, `snapshot`, and
`events` RPCs per isolate; it has no mutation surface and is absent from product
builds.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-adapters',
    displayName: 'Dartitect Adapters',
    shortDescription: 'Integrate explicit provider boundaries',
    defaultPrompt:
        r'Use $dartitect-adapters to integrate a Dartitect provider safely.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-adapters
description: Integrate Dartitect with Dio, Drift, ObjectBox, Sentry, or a custom provider using isolated provider references and explicit ownership. Use for infrastructure wiring; do not use to select application architecture or define domain policy.
---

# Integrate Dartitect adapters

## When to use

Use this skill after the application has selected a transport, storage, or
telemetry provider and needs to wire its Dartitect adapter at composition.

## When not to use

Use `$dartitect-design` to decide whether a provider is needed,
`$dartitect-observability` for neutral telemetry policy, and
`$dartitect-offline-first` for repository/outbox semantics.

## Invariants

Create adapters in an app/session/isolate infrastructure composition root.
Provider SDKs, generated models, credentials, and configuration remain
consumer-owned. No global client, Store, Hub, or adapter crosses into domain,
application, ViewModel, or presentation. Record owned/borrowed lifetime and
dispose borrowers before providers. Storage schemas have one consumer-owned
writer; never introduce dual-write, automatic cross-engine migration, a schema
bridge, or a cross-engine transaction.

## Workflow

Select exactly one provider reference below, define the application-owned
contract it implements, wire ownership and sanitized telemetry, then test the
real SDK boundary plus deterministic failure cases.

- Dio: [references/dio.md](references/dio.md)
- Drift: [references/drift.md](references/drift.md)
- ObjectBox: [references/objectbox.md](references/objectbox.md)
- Drift + ObjectBox coexistence: [references/coexistence.md](references/coexistence.md)
- Sentry: [references/sentry.md](references/sentry.md)
- Another provider: [references/custom-provider.md](references/custom-provider.md)

## Validate

Verify typed failure mapping, cancellation/concurrency where applicable,
minimal telemetry, provider ownership, reverse disposal, no duplicate
instrumentation, real boundary compatibility, and zero residual resources.
''',
      'references/dio.md': r'''# Dio adapter

Create `DioOwner` or borrow an injected Dio instance in infrastructure. Map
cancellation, transport, HTTP, and configuration failures distinctly. Preserve
the caller's cancellation and concurrency semantics.

Credential requests carry `CredentialGeneration` in Dio request extras. Bind
waiting to `CancelToken`, invalidate only that generation, and deduplicate
concurrent 401 logout. Authenticated replay stays disabled unless the consumer
supplies both a retry client and an explicit semantic idempotency policy. Permit
at most one replay and never repeat streams or multipart/upload bodies.

Record only allowlisted method/protocol/status facts—never body, headers, query,
credentials, or identifying path. Propagate only through the configured W3C
propagator. Reject duplicate tracing/capture between Dartitect and `sentry_dio`.
Test with Dio's real interceptor/adapter boundary and deterministic no-network
responses. Dispose an owned Dio only after requests and instrumentation drain.
''',
      'references/objectbox.md': r'''# ObjectBox adapter

The consumer owns entities, annotations, model JSON, generated Dart code, and
Store configuration. Never edit generated files or treat the adapter as an ORM
abstraction. ObjectBox has no web support.

Use `ObjectBoxStoreOwner.create` for an owned Store and `.value` for a borrowed
one. `ObjectBoxQuerySource` owns one query watcher and its queries per hot
activation; `ObjectBoxStoreWatchSource` owns typed Store-watch subscriptions
and delegates the authoritative pull. Versioned projections borrow the Store
and collection. `ObjectBoxProjectionExecutor` uses `Store.runAsync`; dispose it
before the original Store.

Keep domain and outbox writes in one synchronous
`ObjectBoxMutationTransaction`. Checkpoint and journal adapters borrow the Store
and delegate entities, codecs, and fencing comparison to consumer callbacks.
Across isolates, send `objectBoxStoreReference` bytes, attach an isolate-local
Store with the generated model, and close it in `finally`; never send a live
Store. Close resource sessions, watchers, queries, projection executors, and
observation owners before the Store. Use a real generated fixture for locking,
transaction, async projection, isolate attachment, and teardown evidence.
''',
      'references/drift.md': r'''# Drift adapter

The consumer owns the `GeneratedDatabase`, tables, DAOs, migrations, codecs,
executor, database path, and web assets/storage policy. `dartitect_drift`
provides lifecycle, transaction, checkpoint, journal, and sanitized tracing
around those injected choices; it is not an ORM or universal database layer.

Use a consumer conditional export with a stub, `dart.library.ffi` for native,
and `dart.library.js_interop` for web. Native may use
`NativeDatabase.createInBackground`; web uses app-owned `WasmDatabase.open`, a
compatible worker and `sqlite3.wasm`, correct MIME/COOP/COEP policy, and a
multi-context-safe storage implementation. Reject unsafe IndexedDB/in-memory
for multi-context durability.

Use `DriftDatabaseOwner.create` only when the composition root owns the
database; use `.value` for borrowed databases. Keep domain and outbox writes in
one `DriftMutationTransaction`: `Ok` commits, typed `Err` rolls back and returns
unchanged, and unexpected exceptions roll back with their original stack. Pass
fencing tokens unchanged to consumer-owned checkpoint callbacks, and keep
journal schema/query reconstruction consumer-owned. Adapt `Selectable.watch()`
with `StreamReactiveSource`. Dispose observations, sync, and repositories before
the database. Never claim a transaction across Drift and another engine.
''',
      'references/coexistence.md': r'''# Drift and ObjectBox coexistence

Use separate bounded contexts, repositories, schemas, files/directories, and
database owners. ViewModels depend only on application/domain contracts. Keep
one writer per dataset or partition and dispose observations, sync runs, and
repositories before either engine.

Do not dual-write, bridge engines, share a schema, or imply a cross-engine
transaction. A change of engine is an explicit, resumable application
migration with validation and compensation. Prove coexistence with both real
generators and both real databases open simultaneously.
''',
      'references/sentry.md': r'''# Sentry adapter

The consumer initializes and configures Sentry, supplies the DSN through its own
secure configuration, and closes the SDK. Dartitect adapters borrow an injected
Hub and never initialize, reconfigure, or close it.

Map only sanitized logs, errors, spans, mechanisms, fingerprints, and allowlisted
attributes. Avoid duplicate Flutter error, Dio, or tracing capture. Test through
a fake Hub with zero network, including destination failure and borrowed
lifetime. Dispose Dartitect sinks/reporters/tracers before the consumer closes
the Hub.
''',
      'references/custom-provider.md': r'''# Custom provider

Implement an application-owned or small reusable adapter against Dartitect's
public contracts. Keep provider imports in infrastructure and accept provider
objects/configuration through constructor injection.

A reusable adapter needs an isolated optional package, explicit ownership,
minimal/redacted telemetry, deterministic no-network tests, a real SDK boundary
test, supported-platform documentation, dependency/version rationale, compatible
license, and supply-chain review. Do not add a generic abstraction that hides
provider constraints or changes the domain contract.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-testing',
    displayName: 'Dartitect Testing',
    shortDescription: 'Test failures, lifecycles, and providers',
    defaultPrompt:
        r'Use $dartitect-testing to design a Dartitect verification matrix.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-testing
description: Test Dartitect consumers, failure and lifecycle matrices, real provider fixtures, and residual-resource cleanup with deterministic fakes. Use for verification or leak diagnosis; do not use as a substitute for implementation design.
---

# Test Dartitect boundaries

## When to use

Use this skill when selecting fakes, fixtures, public entrypoints, lifecycle/
failure scenarios, provider boundary tests, or cleanup assertions.

## When not to use

Use the focused implementation skill to define the behavior first. Do not mock
away the SDK boundary whose compatibility the test is meant to prove.

## Invariants

Test through public entrypoints. Prefer deterministic fakes from
`dartitect_testing`; inject clocks, IDs, destinations, executors, process
runners, and filesystem roots. Use real generated/provider fixtures where code
generation or SDK lifecycle is the contract. Disable network. Every test owns
and disposes what it creates and proves no residual resources.

## Workflow

Build a matrix across success, expected failure, unexpected crash,
cancellation/concurrency, lifecycle temperature, disposal, and provider failure.
Choose deterministic fakes for policy and real fixtures for integration.
For a public feature profile, run the matching `FeatureContractMatrix.online`,
`.cache`, `.replica`, or `.offlineFull`; each required row gets a fresh typed
runtime driver. The matrix owns faults, event journal, observed store,
acknowledgements, graph registrations, and `ResourceCensus`; fixtures never
return facts or a residual map. Derive success, expected failure, crash,
cancellation, concurrency, restart, and teardown evidence from those observed
instruments.

Read [references/runtime-and-reactive.md](references/runtime-and-reactive.md),
[references/sync.md](references/sync.md),
[references/provider-fixtures.md](references/provider-fixtures.md), or
[references/tooling.md](references/tooling.md) for the boundary under test.

## Validate

Assert observable state and ownership rather than internal wording. Include
original-stack rethrow, exact-once reporting/span end, stale-completion
rejection, handler restoration, sink isolation, timers/subscriptions/isolates
drained, and zero network or leaked filesystem artifacts.
''',
      'references/runtime-and-reactive.md': r'''# Runtime and reactive tests

Cover `Ok`, `Err`, unexpected rethrow with original stack, every bounded command
policy, disposed terminal state, `start` once, owned/borrowed hosts, effects
before/after listener, FIFO/overflow/second consumer, forced logout after route
removal, and reverse disposal.

For reactive work, cover hot/warm/cold transitions, activation-local sessions,
backpressure, retry after crash, exact-revision refresh, family sharing and
eviction, atomic collection failure, tombstone expiry, background projection
staleness, selector equality, debounce cancellation, TickerMode pause,
payload-free rebuild diagnostics, and localized Material semantics. End with no
listeners, timers, effects, sessions, source sessions, family leases,
projection workers, or graph edges.

For `DerivedAsyncResource`, use an old loader that deliberately ignores
cancellation and prove it cannot publish over a newer dependency generation.
Verify activation-local dependency listener counts, each stale-data policy,
deduplication, family key/eviction ownership, and terminal cleanup. For
diagnostics, feed only protocol events to `DiagnosticsTopologyHarness`, cover
all fixed subject categories, ordering violations, off semantics, reporter
failure isolation, bounded overflow, and zero retained events after disposal.
''',
      'references/sync.md': r'''# Sync tests

Use `OwnedGraphHarness` to prove rollback, drain-before-close, failed swap
retention, and exact zero admitted work. Use `SyncContractHarness` with manual
clock, sequence IDs, checkpoints, crash fault points, and fencing leases for a
deterministic DAG matrix.

Cover missing/duplicate/cyclic dependencies, stable plan order, downstream-only
blocking, independent branches, cancellation, deadlines, lease refusal/loss,
authority expiry, atomic stale-token rejection at the dataset commit, checkpoint
write failure, journal/release/cleanup fault injection, receipt boundaries,
progress bounds, terminal exception with original cause/stack, duplicate
headless requests, protocol rejection, fresh graph per accepted request, and
shutdown drain. Add one real generated storage fixture for fencing-capable
dataset/checkpoint transactions without moving consumer schema or conflict
policy into the adapter.

Test durable mutation/outbox separately: atomic domain-plus-enqueue commit and
rollback, same-key order, bounded cross-key concurrency, stable idempotency keys,
at-least-once duplicates, acknowledgement persistence failure, bounded retry,
conflict and uncertainty, explicit compensation, crash-lane recovery, and
session recovery that does not auto-deliver uncertain records.
''',
      'references/provider-fixtures.md': r'''# Provider fixtures

- Dio: use the real Dio adapter/interceptor boundary with mock transport; test
  cancellation, concurrency, typed failure, minimal attributes, propagation,
  and duplicate instrumentation without network.
- ObjectBox: use consumer-generated entities/model/Store/query/watcher; test
  transactions, same-path locking, cleanup, and isolate attachment on supported
  native hosts.
- Sentry: use a fake Hub, no DSN and zero network; test sanitized mapping,
  destination failure, duplicate capture prevention, and borrowed lifetime.
- Custom providers: pair deterministic contract tests with at least one real SDK
  boundary fixture that proves version and lifecycle compatibility.
''',
      'references/tooling.md': r'''# Tooling tests

Use temporary roots and injected process/filesystem boundaries. Cover read-only
commands, dry-run/apply separation, unknown config rejection, strict findings,
expiring suppressions, stale plans, conflicts, recovery journals, symlink/path escape,
permissions, Unicode and spaces, and idempotent managed-skill sync.

Run consumer-tax fixtures for local through offline-full. Require zero manual
assembly plumbing, no untyped/null capability slots, explicit dependency
closure, bounded generated bytes, and recorded analyzer/build timing ratchets.

Native setup tests remain offline by injecting download, archive, host, temp
root, and atomic replacement. Cover supported mappings, pinned hashes, corrupt
or truncated archives, missing exact members, unsupported hosts, read-only
destinations, cache revalidation, and cleanup. MCP protocol tests also cover
expiry, replay, concurrency/lock, output sanitization, and clean shutdown.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-modeling',
    displayName: 'Dartitect Modeling',
    shortDescription: 'Generate opt-in Dartitect modeling capabilities',
    defaultPrompt:
        r'Use $dartitect-modeling to define and synchronize Dartitect models.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-modeling
description: Define, generate, validate, or review opt-in Dartitect values, JSON codecs, projections, lenses, and boundary mappers. Use for consumer-owned modeling and model sync/check/migration; exclude provider schema, DI, ViewModels, state, and HTTP clients.
---

# Model values with Dartitect

## When to use

Use this skill for the independent `@DartitectValue()`, `@DartitectJson()`,
`@DartitectProjection()`, and `@DartitectMapper()` capabilities, generated
value semantics, codecs, projections/lenses, pure mappers, ownership manifests,
or `model sync/check/migrate primary`.

## When not to use

Use provider-specific tooling for provider DTO/entity schema or native generators. Use
the runtime, reactive, adapters, or tooling skill for ViewModels, state, HTTP,
DI, and unrelated CLI behavior.

## Invariants

Keep annotations passive in `dartitect_modeling`; generation belongs to host
tooling. A source library may contain multiple annotated final classes and owns
one deterministic Dartitect part. Models use a primary constructor, extend
`ValueEquality`, expose immutable typed fields, and may be generic, const, use
defaults, records, and parts when the shared semantic compiler validates them.

Use `ImmutableValueList`, `ImmutableValueSet`, and `ImmutableValueMap` for
structural collection fields. JSON, projections, and mappers are never enabled
by the value marker. Unknown JSON keys reject by default, untrusted limits are
64 depth/10,000 items/100,000 nodes, and any trusted or custom limit choice is
explicit. Mappers automate only assignable lossless fields; renames and static
consumer hooks are explicit. Never infer narrowing, enum/string, dates, IDs,
relations, or flattening. Provider-owned generators use distinct outputs.

## Workflow

Use `dartitect model sync` for a read-only preview, or `--dry-run` for an
explicit preview. Only `dartitect model sync --apply` may recover and converge
outputs. Run `dartitect model check` in CI. Commit every
`*.dartitect.g.dart` output and namespaced manifest so a clean
checkout compiles without installing the CLI.

New model generators and analyzer quick fixes emit the required primary
constructor syntax directly. The public CLI does not convert existing models.

Never hand-edit or force-adopt a generated model. A digest conflict means the
consumer bytes must be reviewed and ownership restored explicitly. A pending
journal is inspected by preview/check and recovered only by `sync --apply`.

## Validate

The generated model surface supplies `equalityFields`, descriptors/lenses, and
typed `copyWith`. Nullable fields preserve on omission, replace on a non-null
value, and clear with `clear<Field>: true`; passing a value and clear together
must fail. Non-nullable fields have no clear flag. Do not generate equality,
hashing, or `toString` because `ValueEquality` centralizes those semantics.

Test primary constructors, generics, const/defaults, records, multiple models,
preserve/replace/clear behavior, defensive structural collections, JSON
round-trip/malformed/bounds, projection selection, lossless/lossy mapping and
hooks. Also cover create/update/no-op/orphan convergence, migration preview/
apply/recovery, consumer edits, manifest corruption/path escapes, CRLF,
concurrency, pending recovery, and stable JSON/SARIF/exit codes.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-tooling',
    displayName: 'Dartitect Tooling',
    shortDescription: 'Operate CLI, lints, generators, and gates',
    defaultPrompt:
        r'Use $dartitect-tooling to operate or extend Dartitect tooling.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-tooling
description: Operate or extend the Dartitect CLI, config, verify, scan, doctor, fleet, bounded OpenAPI contracts, lints, semantic compiler, generators, native setup, and release gates. Use for shell/CI architecture tooling; MCP configuration and protocol work belongs to the MCP skill.
---

# Operate Dartitect tooling

## When to use

Use this skill for CLI commands/services, stable config v2, verify/scanner/doctor policy,
bounded local OpenAPI contracts, analyzer diagnostics, generators, Codex sync, native fixture setup,
or repository release gates.

## When not to use

Use `$dartitect-mcp` for local MCP tools, resources, protocol, previews, or
opt-in MCP writes. Use runtime skills for application behavior.

## Invariants

Inspection and `dartitect verify` are strictly read-only. Mutations preview by default or provide explicit
dry-run/apply separation. Reject experimental versions and keep config blocks
closed and typed. Generators stage, validate, refuse
conflicts, and recover transactionally. Codex sync replaces only valid
manifest-owned skills and preserves consumer-owned files/directories.
Every reviewed project change binds only its semantic inputs in a sorted
SHA-256 manifest. Partition generated ownership, reports, and journals by
`GenerationNamespace`. Acquire the cross-process project lock before
revalidation and hold it through commit, rollback, or recovery. Migrate RC3
ownership only when manifest metadata, recorded digest, and current bytes match.

## Workflow

Identify the command contract and exit codes, resolve roots by real path
segments, construct a deterministic preview, validate the complete staged
result, then commit atomically. Update tests, docs, diagnostics, catalogs, and
release gates that expose the behavior.

Read [references/cli-scan-and-lints.md](references/cli-scan-and-lints.md),
[references/generation-and-native.md](references/generation-and-native.md), or
[references/release-gates.md](references/release-gates.md) as applicable.

## Validate

Test idempotency, conflicts, stale state, interrupted recovery, path/symlink
confinement, permissions, CRLF, Unicode/spaces, unknown-key preservation, stable
JSON/exit codes, irrelevant-asset stability, real cross-process exclusion,
generated-consumer behavior, and unchanged tracked files after verification.
''',
      'references/cli-scan-and-lints.md': r'''# CLI, scan, and lints

Keep `inspect`, `scan`, and ordinary `doctor` read-only. Deep doctor is explicit
and bounded. Accept exactly stable config v2 with `native_strict`; reject
experimental versions, unknown keys, credentials, and opaque plugin data.
The target-aware `features` section declares `local`, `online`, `cache`,
`replica`, or `offline-full` and refers to named provider blocks. `verify` checks declarative
compatibility; behavioral guarantees remain contract-matrix evidence.

`dartitect contracts check|sync` accepts only confined local OpenAPI 3.1 JSON
or YAML and local refs. Keep network access, streaming, multipart, callbacks,
webhooks, automatic security execution, and inferred domain mapping outside the
generator. Preview before apply and classify additive versus breaking changes.

Scan only declared roots using real path segments; ignore nested caches and
generated code. Every finding fails strict scan. Local suppressions require an
owner, reason, and expiry, and release doctor rejects all suppressions. Keep CLI
and official analyzer-plugin diagnostics semantically aligned
through the versioned true/false-positive corpus while respecting their
different hosts and entrypoints. Prefer element/library identity when resolved.
Sensitive metadata needs a recognized telemetry sink. Generated fallback needs
both a reviewed header and configured suffix. Invalid analyzer config is an
explicit diagnostic, never a silent strict-default outcome. Enforce scanner and
analyzer performance budgets with stable machine-readable schemas.

`fleet report` stays read-only and aggregates versions, profiles, providers,
and bounded matrix-source detection. Keep process execution in the separate
`DartitectFleetCanaryService`: require an exact commit, use only an archive and
temporary consumer copy, run a closed command allowlist, sanitize receipts,
compare original SHA/worktree/tree state, and remove the copy after failure.
''',
      'references/generation-and-native.md': r'''# Generation and native setup

Stage generated content outside the destination, validate it, refuse
consumer-owned collisions, record a journal, and replace only the declared
target. Recover the old data on interruption. Generated-once files become
consumer-owned; fully generated files need an ownership manifest before update.
For project-service changes, the semantic manifest excludes unrelated assets;
the OS lock spans revalidation through all journal cleanup.

Native fixture setup accepts only reviewed host/artifact mappings, verifies a
pinned hash before extracting one exact member, installs through same-directory
staging, and revalidates ignored cache markers. Keep download, archive, host,
temporary-root, and atomic replacement injectable for offline tests. Never run
provider code generation by hand or edit its output.
''',
      'references/release-gates.md': r'''# Release gates

Run formatting, analysis, public API snapshots, package/example tests,
generated-consumer matrices, public documentation/link checks, skills coverage,
MCP catalog freshness, CI/security policy, license/SBOM/advisory checks, native
fixtures, and publish dry-runs in proportion to the change and as required by
the repository workflow.

Pin external Actions by full commit SHA. OSV exceptions are exact advisory IDs
with justification, analysis link, and short expiry; package-wide ignores and
PackageOverrides are forbidden. A dry-run never authorizes publishing or tags.
Platform-specific evidence must run on its supported host, and builds must
leave tracked files unchanged.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-mcp',
    displayName: 'Dartitect MCP',
    shortDescription: 'Use the bounded local Dartitect MCP',
    defaultPrompt:
        r'Use $dartitect-mcp to inspect this project through local MCP.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-mcp
description: Configure, use, or extend the local Dartitect MCP server, bounded tools/resources, reviewed previews, and opt-in writes. Use for MCP-specific workflows; exclude shell automation, remote services, application access, and CI scripting.
---

# Use the local Dartitect MCP

## When to use

Use this skill when a local MCP client needs typed Dartitect inspection,
diagnostics, conformance context, public guide resources, reviewed previews, or the
server's guarded write flow.

## When not to use

Use `$dartitect-tooling` and the CLI directly for shell scripts, CI, generators,
release gates, or native setup. The MCP is not a remote service, HTTP/OAuth
endpoint, ChatGPT web plugin, shell bridge, arbitrary file reader, or debugger
for a running application.

## Invariants

The server is local STDIO and read-only by default. Stdout is JSON-RPC only.
Roots are preconfigured and canonical; tool paths are relative and confined.
Never expose secrets, environment, arbitrary files, raw internal errors, or
unbounded results. Tool/resource schemas stay closed and generated resources
come from maintained repository sources.

## Workflow

Configure a trusted root, use inspect/scan/doctor/explain/conformance/resource
reads first, then request a preview. Enable server writes only for an intended,
reviewed local change and retain client approval.

Read [references/setup-and-surface.md](references/setup-and-surface.md) for
configuration/tools/resources and [references/reviewed-writes.md](references/reviewed-writes.md)
for mutation security.

## Validate

Test real-process startup/shutdown, stdout purity, structured plus text output,
bounded pagination, root/path/symlink rejection, resource catalog freshness,
write-disabled behavior, preview/apply annotations, expiry, replay, stale state,
confirmation, locking, revalidation, and sanitized failures.
''',
      'references/setup-and-surface.md': r'''# Setup and surface

Run `dart run dartitect_mcp:dartitect_mcp --root .` and register that local STDIO
command in the MCP client. Multiple roots must already exist and are addressed
by configured names. Do not put credentials in command arguments or environment.

The closed read surface provides inspect, verify, bounded scan, doctor, finding
explanation, conformance auditing, and modeling migration previews. Generated resources expose
package metadata, diagnostics, canonical English guides, and credential-free
config v2. There is no free-form file resource. Results include structured
content plus compatible JSON text. Read tools/previews are annotated read-only;
only apply is mutable/destructive.
''',
      'references/reviewed-writes.md': r'''# Reviewed writes

Start the server with `--allow-writes` only when a reviewed local mutation is
intended. The flag alone grants nothing. Apply requires all of:

1. server write opt-in;
2. a prior read-only preview;
3. an opaque plan ID that is unexpired and unused;
4. `confirmed: true` after user review;
5. client MCP approval;
6. complete root, state, and operation revalidation;
7. in-process serialization plus an exclusive filesystem lock.

Plans are single-use even after a failed attempt. Expiry, replay, stale state,
concurrency, path, permission, and I/O errors remain structured and sanitized.
Do not bypass the flow, broaden roots, or use MCP writes as CI automation.
''',
    },
  ),
];
