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

/// Repository inclusion gate appended to every managed skill entrypoint.
const String dartitectSkillInclusionGate = '''## Dartitect inclusion gate

Before adding a capability, answer:

> Is it business-neutral, difficult to implement correctly, and a source of
> repetitive infrastructure in consumer applications?

All three answers must be “yes”. Otherwise reusable infrastructure belongs in
a typed project-local extension and business behavior stays in the application.
''';

/// Materializes the complete managed-skill snapshot from the canonical catalog.
Map<String, Map<String, String>> buildDartitectManagedSkillFiles() =>
    <String, Map<String, String>>{
      for (final template in dartitectSkillCatalog)
        template.name: <String, String>{
          for (final entry in template.files.entries)
            entry.key: entry.key == 'SKILL.md'
                ? '${entry.value.trimRight()}\n\n$dartitectSkillInclusionGate'
                : entry.value,
          'agents/openai.yaml': template.openAiYaml,
        },
    };

/// Typed skill templates distributed by `dartitect codex sync`.
const List<DartitectSkillTemplate>
dartitectSkillCatalog = <DartitectSkillTemplate>[
  DartitectSkillTemplate(
    name: 'dartitect-design',
    displayName: 'Dartitect Design',
    shortDescription: 'Select greenfield Dartitect packages and routes',
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
Route detailed Dart semantics, incremental execution, performance, runtime,
reactive, offline-first, telemetry, adapter, testing, CLI, or MCP work to the
matching focused skill after suitability and the stack are decided.

## Invariants

Choose the smallest stack that satisfies the feature. Riverpod, BLoC, Provider,
GetIt, MobX, Signals, and equivalent architecture runtimes are incompatible with
the Native Strict application graph. Keep domain/application contracts
provider-neutral, use constructor injection, and make every resource owned or
borrowed. Do not add a container, global runtime, provider package, or remote
telemetry without a stated requirement.
For config v3 consumers, prefer generated concrete `ApplicationGraph`,
`SessionGraph`, feature runtime/factory, and `FeatureHost` surfaces. Keep manual
assemblies and ownership primitives as advanced low-level escape hatches.

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

Select only rows justified by a concrete boundary. The matrix lists all 25
stable packages so an omitted package is an explicit decision.

| Package | Select for | Route or boundary |
| --- | --- | --- |
| `dartitect` | Result, ownership, commands, credentials, composition, and opt-in incremental operations | `$dartitect-runtime`, `$dartitect-incremental`, `$dartitect-dart` |
| `dartitect_flutter` | Basic Flutter ViewModels, hosts, forms, queries, or opt-in reactive/incremental entrypoints | `$dartitect-runtime`, `$dartitect-reactive`, `$dartitect-incremental` |
| `dartitect_flutter_testing` | Dev-only semantics, accessibility, contrast, tap-target, and paired UI matrices | `$dartitect-ui`, `$dartitect-testing` |
| `dartitect_sync` | Durable mutation/outbox, dataset DAGs, checkpoints, leases, and headless sync | `$dartitect-offline-first` |
| `dartitect_resilience` | Bounded retry, single-flight, breaker, bulkhead, or rate limiting | `$dartitect-runtime`, `$dartitect-testing` |
| `dartitect_jobs` | Versioned job envelopes, bounded dispatch, deadlines, receipts, and fencing ports | `$dartitect-offline-first`, `$dartitect-testing` |
| `dartitect_transfer` | Resumable chunks or attachment staging with durable checkpoints | `$dartitect-adapters`, `$dartitect-testing` |
| `dartitect_devtools` | Diagnostics v2 plus a separate development-only, read-only, payload-free privacy extension | `$dartitect-observability`, `$dartitect-testing` |
| `dartitect_isolates` | Versioned workers, bounded pools, ACK/readiness/heartbeat/deadline lifecycle | `$dartitect-runtime`, `$dartitect-incremental`, `$dartitect-dart`, `$dartitect-testing` |
| `dartitect_observability` | Destination-aware privacy, prepared logs/errors/tracing, and payload-free diagnostics | `$dartitect-observability` |
| `dartitect_dio` | Explicit Dio ownership, typed transport failures, and metadata-only or classified capture | `$dartitect-adapters` |
| `dartitect_drift` | Lifecycle and operational adapters around a consumer-generated Drift database | `$dartitect-adapters`, `$dartitect-offline-first` |
| `dartitect_objectbox` | Native Store/query/watch/projection lifecycle around a consumer-generated model | `$dartitect-adapters`, `$dartitect-offline-first` |
| `dartitect_sentry` | Borrowed-Hub legacy or prepared telemetry after the consumer selects and initializes Sentry | `$dartitect-adapters`, `$dartitect-observability` |
| `dartitect_testing` | Deterministic failure, lifecycle, provider, and residual-resource harnesses | `$dartitect-testing` |
| `dartitect_cli` | Config v3, inspect/scan/doctor, execution-model inspection, generators, fleet, contracts, and Codex sync | `$dartitect-tooling`, `$dartitect-performance` |
| `dartitect_lints` | Analyzer-host Native Strict and modeling diagnostics | `$dartitect-tooling` |
| `dartitect_locale_br` | Structural Brazilian postal-code value handling only | `$dartitect-design` |
| `dartitect_geometry` | Finite planar polygon/polylabel values only | `$dartitect-design` |
| `dartitect_privacy` | Explicit iOS ATT status/request boundary | `$dartitect-adapters` |
| `dartitect_media` | Explicit Android/iOS image-save permission and action boundary | `$dartitect-adapters` |
| `dartitect_mcp` | Local bounded interactive context, previews, and reviewed writes | `$dartitect-mcp` |
| `dartitect_workmanager` | Workmanager callbacks adapted to a fresh job graph per execution | `$dartitect-adapters`, `$dartitect-offline-first` |
| `dartitect_modeling` | Opt-in immutable values, JSON, projections, lenses, and pure mappers | `$dartitect-modeling` |
| `dartitect_modeling_analyzer` | Tooling-only semantic compilation and model diagnostics | `$dartitect-modeling`, `$dartitect-tooling` |

Generated `FeatureHost` and `CommandStateBuilder` remain Material-neutral;
product UI stays consumer-owned. Scheduling, recurrence, schemas, transactions,
conflict/retry/authentication policy, provider configuration, and semantic
mappings stay consumer-owned. ObjectBox has no web support. CLI and MCP run on
the Dart VM. Provider adapters never belong in domain, application, ViewModel,
or presentation layers.

Native Strict does not provide an overlap or coexistence mode for competing
application architecture runtimes.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-audit',
    displayName: 'Dartitect Audit',
    shortDescription: 'Audit Native Strict conformance without writes',
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
   Treat schema-2 `architectureTax` as a zero budget, while `generatedTax` is
   additive infrastructure evidence and `productCode` never blocks.
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
    shortDescription: 'Own Result, command, graph, and Flutter lifecycles',
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
hosts, generated `FeatureHost`, versioned UI restoration, isolate graphs, and the basic
`dartitect_flutter.dart` entrypoint.

## When not to use

Use `$dartitect-reactive` for `ReactiveOwner`, `LiveResource`, resource families,
live collections, or advanced builders. Use `$dartitect-offline-first` for local
authority, paging, durable mutations, or outbox recovery. Use
`$dartitect-incremental` for cold incremental producers, partial aggregates,
and bounded worker-pool sequences.

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
Generated application/session graphs open each declared context once at its
configured scope. A feature host closes its ViewModel before its feature graph
and rejects publication after cancellation or disposal.

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

All Flutter commands implement `DartitectCommand<T, F>` and
`DartitectObservableResource`, so ownership is compile-time safe. Consume
`CommandState` through exhaustive `match` callbacks for idle, running,
succeeded, failed, crashed, and cancelled states; each callback receives the
complete state.

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

Use `CommandStateBuilder<T, F>` when a widget needs exhaustive command-state
rendering. It has no Material, text, layout, navigation, or visual defaults and
pauses its listener while `TickerMode` is disabled.

Use `ApplicationHost` for named cancellable bootstrap, retry, atomic graph
publication, and teardown. Use `SessionRuntimeController`/`SessionHost` for
login, logout, tenant switch, and route-confirmed generation replacement.
Versioned restoration accepts only consumer codecs/migrations and ephemeral UI
payloads; invalid data falls back safely. `BoundedLocalHistory` is value-only
and cannot claim to undo persistence, HTTP, upload, sync, or another effect.

For generated config-v3 features, prefer `<Feature>FeatureHost`: provide the
correct application/session graph and typed factory, let it create/start the
ViewModel, and keep loading/failure/ready presentation consumer-owned.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-reactive',
    displayName: 'Dartitect Reactive',
    shortDescription: 'Build hot, warm, and cold causal Flutter resources',
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
    shortDescription: 'Build durable local authority, outbox, and sync',
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
In config-v3 generated graphs, the feature factory supplies repositories,
ports, mapping/idempotency/conflict policy, datasets, and ViewModels; Dartitect
owns outbox/sync/scheduler/diagnostics/cancellation/disposal plumbing. Use the
generated pull authority only when `LocalStore.watch/read` is authoritative.

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

Borrow a consumer-owned `RetryBudget` through `MutationCommand.retryBudget`
when delivery shares a bootstrap/reconnect admission window. Budget rejection
preserves pending data and identity. Pass typed HTTP feedback through
`MutationFailurePolicy.queued(retryAfter: ...)`; invalid/excessive feedback
defers delivery, and valid server minimums survive jitter. Dispose borrowers
before the budget's borrowed `Bulkhead`; budgets do not own providers.
''',
      'references/sync-execution.md': r'''# Sync execution

Dataset DAG synchronization and headless synchronization are separate flows.
Use `SyncEngine` for a validated dataset DAG, checkpoints, journals, leases/
fencing, progress, and deadlines. Use `HeadlessSyncEndpoint` for a versioned
sync definition adapted through `dartitect_jobs`, bounded duplicate retention,
separate acceptance and terminal acknowledgements, and a fresh graph per
admitted request.

Opt into `package:dartitect_sync/dartitect_sync_titect.dart` only for explicitly
selected Titect wire contracts. Keep opaque cursors and exact numeric tokens;
require checked narrowing, bounded reads and parser allocation, explicit
capabilities, and the same retry/read budgets at leaf attempts. The consumer
owns transport, authentication, schemas, integrity policy, durable application
proof and atomic authority checks. Confirm the checkpoint before the next page.
Run the pinned Python/Dart VM/Chrome corpus and real persistent recovery;
preliminary or divergent evidence cannot establish release compatibility.

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
stops retry. Share one `RetryBudget` across the leaf operations used by refresh,
reconnect, outbox, and headless sync in the same isolate. Queue and retry waits
consume the scope window. Keep retries at one layer and pass the same budget
to participating executors; no cross-isolate authority is inferred.
Use `JobDispatcher` for generic bounded headless definitions and
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
    shortDescription: 'Design sanitized provider-neutral telemetry',
    defaultPrompt: r'Use $dartitect-observability to design sanitized Dartitect telemetry.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-observability
description: Configure Dartitect destination-aware privacy, provider-neutral logging/reporting/tracing, bounded sanitization, prepared destinations, and payload-free diagnostics. Use for telemetry contracts and policy; use the adapters skill for provider-specific wiring.
---

# Configure Dartitect observability

## When to use

Use this skill for `ObservabilityRuntime.withPrivacy`, profiles,
classifications, masking, bounded sanitization, prepared destination queues,
error reporting, W3C propagation, Flutter error capture, or payload-free
runtime diagnostics. Use the compatible runtime only when preserving a 1.0
composition.

## When not to use

Use `$dartitect-adapters` for Dio, Drift, ObjectBox, Sentry, or custom provider wiring.
Do not add remote telemetry merely because observability contracts exist.

## Invariants

Create the runtime explicitly; generated graphs start with the `balanced`
profile and a prepared local developer destination. Remote destinations are
opt-in. Resolve each leaf classification through its hierarchy, then combine
multiple decisions as `deny > mask > allow`. High-risk remote allows require
explicit risk acceptance. Only immutable prepared events enter independent
destination queues; never retain raw input or call `toString()` on unknown
objects/keys. Errors/fatal are never sampled away. Destination failure stays
isolated.

## Workflow

Define the data classes and local/remote/named policy first, then choose
owned/borrowed prepared sinks, reporter, tracer, propagator, Flutter binding,
reactive observers, and diagnostic detail. Bound depth, collections, total
nodes, text, frames, and classification work. End every span exactly once and
define reverse flush/disposal. Use only emitter-owned opaque IDs; keep buffers
bounded and clear them on dispose.

Read [references/telemetry-contract.md](references/telemetry-contract.md),
[references/flutter-and-providers.md](references/flutter-and-providers.md), or
[references/reactive-events.md](references/reactive-events.md) for the boundary
being configured.

## Validate

Test the profile/local/remote/named matrix, precedence, raw-secret sentinels,
cycles, key collisions, Unicode masking, structural budgets, unsampled
error/fatal delivery, destination isolation, detailed flush, exact-once span
end, `traceparent`/`tracestate` validation, borrowed provider lifetime, and
payload-free diagnostics.
''',
      'references/telemetry-contract.md': r'''# Telemetry contract

Accept only valid W3C `traceparent`. Validate `tracestate` under its own policy;
never convert it into an attribute, tag, or baggage item. Keep baggage off by
default. Transfer only validated context between isolates. End operation spans
exactly once in `finally`.

Expected `Err<F>` remains command state and is not automatically reported.
Unexpected crashes may be reported once with sanitized mechanism, handled state,
fingerprint, and allowlisted attributes, then are rethrown with the original
stack. Errors and fatal events bypass sampling. Every destination has
independent sampling and a bounded queue containing only private-constructor
prepared events, with explicit overflow behavior. It never stores a closure
retaining raw input. One destination failure cannot affect the application or
another destination. `flushDetailed` reports outcomes by destination while
compatible `flush(Duration)` remains available.

Diagnostics protocol v2 permits only fixed enums, opaque process-local IDs,
counters, generations, revisions, and monotonic time. It rejects metadata,
URLs, domain keys, dynamic errors, stacks, and user identifiers. Optional
Diagnostics-v2 DevTools registration is explicit, isolate-local,
development-only, and exposes exactly capabilities, snapshot, and event-delta
reads; disposal clears the ring. The separate
`ext.dartitect.observabilityPrivacy` RPC exposes only profile, effective actions,
queue/failure counts, and sanitizer counts—never values, samples, or reasons.
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
The diagnostics-v2 bridge registers exactly `capabilities`, `snapshot`, and
`events` RPCs per isolate. The observability privacy RPC is a separate
registration and does not alter v2. Both have no mutation surface and are
absent from product builds.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-adapters',
    displayName: 'Dartitect Adapters',
    shortDescription: 'Wire provider SDKs at infrastructure composition',
    defaultPrompt:
        r'Use $dartitect-adapters to integrate a Dartitect provider safely.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-adapters
description: Integrate Dartitect with transport, storage, telemetry, native capability, transfer, or background providers using explicit ownership. Use for infrastructure wiring; do not use to select application architecture or define domain policy.
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
- Privacy and media plugins: [references/privacy-and-media.md](references/privacy-and-media.md)
- Transfer and Workmanager: [references/transfer-and-workmanager.md](references/transfer-and-workmanager.md)
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

Generated OpenAPI operation wrappers receive `DioJsonClient`, never raw `Dio`,
and inherit cancellation, deadline, credentials, and observability from the
selected transport context. Only operations declared by the feature enter its
graph. Keep status semantics, DTO/domain mapping, retry, authentication, and
idempotency policy consumer-owned.

Credential requests carry `CredentialGeneration` in Dio request extras. Bind
waiting to `CancelToken`, invalidate only that generation, and deduplicate
concurrent 401 logout. Authenticated replay stays disabled unless the consumer
supplies both a retry client and an explicit semantic idempotency policy. Permit
at most one replay and never repeat streams or multipart/upload bodies.

Opt into `DioRetryAfterPolicy` on `DefaultDioJsonClient` or
`captureDioException` for bounded typed metadata. Inject `RetryAfterParser`
limits and the receipt clock; no raw headers are retained and no retry
interceptor is installed. The consumer classifies 429/503 and uncertain writes.

Use `DioObservabilityCapturePolicy.metadataOnly()` by default for fixed
method/protocol/status/error-type facts and zero payload. Diagnostic capture is
explicit, requires classifications, and accepts only already-materialized
JSON-safe structures; never consume streams, multipart values, bytes, or files.
Remove `LogInterceptor`, propagate only through the configured W3C propagator,
and reject duplicate Dartitect/`sentry_dio` capture. Test with Dio's real
interceptor/adapter boundary and deterministic no-network responses. Dispose an
owned Dio only after requests and instrumentation drain.
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

Legacy adapters remain defensive and redact direct compatible-runtime input.
For `ObservabilityRuntime.withPrivacy`, use only
`SentryLogSink.sanitizedInput`, `SentryErrorReporter.sanitizedInput`, and
`SentryTracer.sanitizedInput`; prepared input is not redacted twice. Map only
approved bounded context/extra data, limit tags, and never create a `SentryUser`.
Avoid duplicate Flutter error, Dio, or tracing capture. Test through a fake Hub
with zero network, including destination failure and borrowed lifetime. Dispose
Dartitect adapters before the consumer closes the Hub.
''',
      'references/privacy-and-media.md': r'''# Privacy and media adapters

`dartitect_privacy` is only an iOS ATT status/request boundary, not an
observability classification or destination-sanitization contract. Construction and
status reads are prompt-free; only a consumer-owned interaction calls
`request()`. Preserve every native state, return typed not-supported outcomes
without channel calls elsewhere, emit no telemetry, and keep disclosure text,
usage descriptions, request timing, analytics policy, and legal review in the
application.

`dartitect_media` saves one consumer-selected image on Android or iOS. Status
reads and `saveImage` never request permission. The consumer owns source-file
lifetime, album naming, UX, and legal/platform review. The plugin owns only
request coordination and its Android legacy-request history bit. Await
`clearOwnedState()` before package removal; a cleanup failure blocks a
zero-residue claim. Never log paths, names, bytes, albums, native messages, or
receipts. Test unsupported hosts without channel calls and supported hosts
through the real method-channel/native lifecycle boundary.
''',
      'references/transfer-and-workmanager.md':
          r'''# Transfer and Workmanager adapters

`dartitect_transfer` owns provider-neutral chunk planning, checksums, progress,
and checkpoints. Remote protocol, Range/ETag semantics, authentication,
idempotency, retry classification, picker/share/gallery ports, and durable
metadata/outbox transactions remain consumer-owned. A checkpoint advances only
after the chunk commit is durable. Use `dartitect_dio` only as the selected
transport adapter and never retry an uncertain mutation implicitly.

`dartitect_workmanager` adapts a consumer-initialized Workmanager callback to a
versioned `JobDispatcher`. Build a fresh graph per accepted execution, validate
the envelope, preserve deadline/cancellation/receipt semantics, and close the
graph in `finally`. The consumer owns registration, recurrence, platform policy,
constraints, and provider lifecycle. Test Android/iOS/macOS through supported
plugin boundaries, preserve preview limitations on web/Linux, and return typed
unsupported on Windows.
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
    name: 'dartitect-ui',
    displayName: 'Dartitect UI',
    shortDescription: 'Build consumer-owned adaptive accessible Flutter UI',
    defaultPrompt: r'Use $dartitect-ui to design and verify Dartitect Flutter presentation.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-ui
description: Build business-neutral Flutter presentation around Dartitect state using consumer-owned Material or Cupertino controls, adaptive layouts, accessibility, localization, focus, navigation, forms, and UI tests. Use for Flutter UI implementation or review; do not use to invent an SDK design system.
---

# Build Dartitect presentation

## When to use

Use this skill when a Flutter consumer needs to render Dartitect commands,
forms, queries, effects, or reactive resources; choose responsive layouts;
design navigation and focus; or establish semantic, keyboard, accessibility,
and UI-matrix tests.

## When not to use

Use `$dartitect-runtime` for ownership and ViewModel design,
`$dartitect-reactive` for resource behavior, and `$dartitect-testing` for
non-UI lifecycle matrices. Do not create Dartitect-branded buttons, fields,
switches, dialogs, navigation, themes, copy, localization, or visual tokens.

## Invariants

The consumer owns `ThemeData`, `ColorScheme`, component themes,
`ThemeExtension`, typography, visible text, localization, navigation, brand,
and product composition. Use official Material 3 controls directly; use
adaptive or Cupertino controls only for established platform conventions.
Choose layout from finite available space, never device labels or orientation.
Keep ViewModels, controllers, focus nodes, navigation state, and restoration
above responsive branch replacement. Dartitect builders borrow state and never
dispose it.

## Workflow

1. Identify the authoritative command, form, query, effect, or resource. Do not
   introduce another async envelope.
2. Keep product state and actions in a ViewModel/controller above the layout;
   drain one-shot effects at the mounted View boundary.
3. Build controls directly from Material 3. Use `.adaptive` or Cupertino only
   when Flutter or an Apple convention defines a meaningful difference.
4. Use `DartitectResponsiveWindowBuilder` for the full surface and
   `DartitectResponsiveRegionBuilder` for a finite nested region. Supply all
   compact, medium, and expanded branches.
5. Render every state with `CommandStateBuilder`,
   `DartitectFormSnapshotBuilder`, `DartitectQueryStateBuilder`, or
   `ResourcePresentationBuilder`. Preserve stale content when the domain policy
   calls for it and distinguish expected failure from crash.
6. Localize all visible labels and semantics. Define traversal order, initial
   focus, shortcuts, and restoration in consumer code; keep actions reachable
   without pointer input.
7. Test the paired `DartitectUiMatrix`, then add product-specific focus,
   keyboard, navigation, and action assertions.

Read [references/presentation.md](references/presentation.md) for state,
responsive layout, navigation, forms, focus, and effects. Read
[references/verification.md](references/verification.md) for semantics,
accessibility, matrix, audit, and golden guidance.

## Validate

Run Flutter analyze/tests plus `dartitect ui audit --strict`. Prove all size
classes, 100%/200% text, LTR/RTL, light/dark, high contrast, reduced motion,
semantics, focus, keyboard activation, expected failures, crashes, stale and
empty states. Keep golden coverage small and secondary to behavior. Tests and
audits must not upload screenshots, semantics, or screen content.

''',
      'references/presentation.md': r'''# Presentation architecture

## State and actions

Treat existing authorities as final: `DartitectCommand` for an action,
`DartitectFormController` for form snapshots/submission,
`DartitectQueryController` for query state, `EffectChannel` for one-shot UI
effects, and `LiveResource` plus `ResourcePresentationState` for reactive local
authority. Do not wrap them in a second loading/error model. Builders borrow
controllers and resources, observe only while `TickerMode` is enabled, catch up
on reactivation, and never dispose what they receive.

Keep validation policy in the form controller and render official `TextField`,
`TextFormField`, selection, and button controls with localized labels, errors,
hints, and announcements. Keep submit commands exhaustive and prevent duplicate
submission through command policy rather than a widget-local flag.

Drain effects from a mounted View boundary. Navigation, snack bars, dialogs,
and platform intents are consumer presentation behavior; ViewModels emit typed
effects but do not retain `BuildContext`.

## Responsive layout and navigation

Use the Material 3 width thresholds 600 and 840 and height thresholds 480 and
900 unless the app supplies validated alternatives. An exact threshold belongs
to the larger class. Window classification records width and height separately;
branch selection uses available width. A nested region must have finite width.

The responsive builders choose no `Scaffold`, route, navigation control, color,
or copy, and they preserve no state implicitly. Put route state, selected
destination, scroll controllers, focus nodes, forms, and restorable state above
the branch. A consumer may select `NavigationBar`, `NavigationRail`, drawer,
split view, or a product-specific composition without changing domain state.

## Platform, focus, and localization

Prefer Material 3 everywhere. Choose `.adaptive` when Flutter provides it for
the same semantic control. Use Cupertino directly only for a deliberate Apple
convention, not as a wholesale platform fork. Do not infer layout from
`Platform`, device models, or orientation.

Every visible string, tooltip, semantic label, validation message, and action
name belongs to consumer localization. Use Flutter `Localizations`/gen-l10n and
locale-aware directionality. Define focus traversal and shortcuts explicitly
for dialogs, forms, split panes, menus, and desktop/web commands. Test keyboard
activation and restoration as product assertions rather than generic harness
behavior.
''',
      'references/verification.md': r'''# UI verification

Use `dartitect_flutter_testing` only as a dev dependency. The standard matrix is
five paired rows: 360x640, 430x932, 768x1024, 1024x768, and 1440x900. Across
those rows it covers 100%/200% text, LTR/RTL, light/dark, normal/high contrast,
and normal/reduced motion without a Cartesian explosion. The consumer supplies
the root widget, themes, locales, and scenario exercises.

`DartitectUiHarness` configures and restores the Flutter test view, platform,
MediaQuery, accessibility features, and semantics even after failure. Its
policy uses Flutter's official labeled-target, contrast, and mobile tap-target
guidelines and fails on framework exceptions or overflow. Add explicit
assertions for focus order, keyboard activation, shortcuts, navigation,
restoration, and product actions.

Run `dartitect ui audit --strict` and the analyzer plugin. Errors cover objective
low-level custom-button primitives and orientation locks. Warnings cover
orientation/device sizing, broad MediaQuery subscriptions, gesture controls
without evident semantics, visual literals outside themes, and unlabeled icon
actions. Reviewed suppressions require code, narrow path, owner, reason, and
expiry.

Use goldens only for genuinely shared compact, medium, and expanded layouts on
a pinned runner, font, and renderer. Do not multiply goldens per screen or
platform. Semantics and behavior remain the release gate. Neither tests nor
audits send screenshots, semantics, or content to telemetry.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-flutter-quality',
    displayName: 'Dartitect Flutter Quality',
    shortDescription: 'Prove executable Native Strict Flutter quality',
    defaultPrompt: r'Use $dartitect-flutter-quality to implement and prove this Flutter quality change.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-flutter-quality
description: Implement or audit executable Flutter quality in a Native Strict Dartitect application. Use for responsive constraints, previews, MVVM/repositories, DevTools runtime evidence, multi-platform behavior, tests, or structural performance; coordinate Flutter's official skills instead of copying them.
---

# Prove Flutter quality

## When to use

Use this skill when Flutter quality must be demonstrated by source, previews,
runtime inspection, tests, platforms, or deterministic Actions evidence.

## When not to use

Use `$dartitect-ui` for ordinary presentation composition and the focused
runtime, offline-first, testing, or performance skill for a non-Flutter
boundary. Do not install plugins or claim unavailable MCP tools.

## Invariants

Apply Native Strict. Keep widgets value/callback-only, ViewModels responsible
for state/commands/effects, repositories provider-neutral, and exactly one
store selected at composition. Previews are dev-only, synthetic, immutable,
and free of I/O, adapters, plugins, globals, and app lifecycle.

## Workflow

Route the task by name to the applicable official skills:
`flutter-apply-architecture-best-practices`,
`flutter-build-responsive-layout`, `flutter-fix-layout-issues`,
`flutter-add-widget-preview`, `flutter-add-widget-test`, and
`flutter-add-integration-test`. Use only skills actually discovered from
`dart-flutter@dart-flutter`; do not duplicate their instructions.

Read [references/architecture-and-previews.md](references/architecture-and-previews.md)
for MVVM, repositories, responsive composition, and preview safety. Read
[references/runtime-devtools-and-mcp.md](references/runtime-devtools-and-mcp.md)
when live inspection is applicable. Read
[references/tests-and-evidence.md](references/tests-and-evidence.md) for the
verification matrix. Read [references/performance.md](references/performance.md)
for structural budgets and informative measurements.

## Validate

Require explicit analyze, strict audit, preview compilation, runtime inspection,
tests, and platform evidence. Mark unavailable MCP or a missing applicable
dimension as not evidenced. Never store transcripts, screenshots, semantics,
or visible content in test or Actions artifacts.
''',
      'references/architecture-and-previews.md': r'''# Architecture and previews

Use the route `Page -> ViewModel -> Repository -> store/outbox -> remote
service`. The Page owns route lifecycle, controllers, mounted navigation, and
effect delivery. The View observes one ViewModel. Reusable content, rows,
details, and diagnostics receive immutable values and callbacks, never
sessions, roots, providers, Stores, clients, or internal payloads.

A provider-neutral repository coordinates local-first behavior and selects
exactly one Memory, Drift, or ObjectBox store at composition. Never dual-write
or migrate engines implicitly. Fence restart-latest search generations and
publish only the current aggregate. Keep query, selection, scroll, and focus
above compact/medium/expanded branch replacement; use lazy builders and
row-scoped selectors.

Use `DartitectPreviewMatrix` only for device size, brightness, and text scale.
Keep RTL, contrast, reduced motion, semantics, focus, and keyboard in
`DartitectUiMatrix`. Preview functions live in permitted dev-only locations
and return widgets from immutable synthetic view data and pure callbacks.
They cannot reach native I/O, FFI, network, stores, adapters, plugins, global
initialization, or application lifecycle.
''',
      'references/runtime-devtools-and-mcp.md': r'''# Runtime, DevTools, and MCP

Discover Flutter tools at runtime from the official
`dart-flutter@dart-flutter` plugin and its `dart mcp-server`. Do not infer a
tool name or fabricate output. If the plugin, MCP server, a running target, or
a necessary tool is absent, record the exact missing evidence and continue
with the applicable static and test evidence.

Inspect finite layout constraints, widget/runtime errors, overflow, rebuild
scope, focus, scroll, interaction paths, first useful state, and cleanup.
Runtime evidence stays payload-free: record counts, statuses, tool identity,
and digests, not screen text, semantics, screenshots, or transcripts.

`dartitect codex doctor --flutter` is read-only and offline. Plugin installation
is a manual user action with `codex plugin add dart-flutter@dart-flutter`.
Dartitect setup manages only catalog assets and never creates or edits
`.vscode/mcp.json`.
''',
      'references/tests-and-evidence.md': r'''# Tests and evidence

Test ViewModel transitions, generation cancellation, mounted effects, and the
common repository contract for Memory, Drift, and ObjectBox. Widget tests cover
all visible states, callback purity, diagnostics view data, responsive branch
replacement, selection, scroll, focus, keyboard, mouse, and touch. Integration
journeys cover smoke, resize, commands, offline/reconnect, search/toggle,
forced logout, and the 10,000-item fixture.

Compile discovered previews from a temporary copy with
`flutter widget-preview start --no-launch-previewer`. Run `dart analyze`,
`flutter analyze`, the strict Dartitect UI audit, focused and complete tests,
Chrome, and supported hosted builds. Prove previews and widget tests invoke no
network or plugin boundary.

The coordinated GitHub Actions graph must pass the exact merge candidate. Its
eight job identifiers cover nine hosted executions because Linux runs both the
Flutter floor and current stable cells. `CI / Required` fails closed if any
coordinated job fails, is cancelled, or is skipped.
''',
      'references/performance.md': r'''# Performance evidence

Collect first frame/useful state, FrameTiming build/raster p50/p95, frames over
budget, rebuilds, rows materialized, queue depth, first search result,
cancel/dispose, and residual subscriptions/watchers/timers/workers inside
canary support only. Do not add a public performance API.

Block zero-overflow, zero-framework-error, zero-late-publication,
zero-residual-resource, fewer than 100 rows materialized before scrolling
10,000 items, state preservation on resize, no heavy/provider work in
presentation, no network/plugin in previews or widget tests, and constrained
images.

Treat time and memory as informative until runner, Flutter version, build
mode, fixture, and measurement window match an equivalent baseline. Do not
turn one machine's measurements into portable release thresholds.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-testing',
    displayName: 'Dartitect Testing',
    shortDescription: 'Verify failure, lifecycle, provider, and leak contracts',
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
For a public feature profile, run the matching `FeatureContractMatrix.local`,
`.online`, `.cache`, `.replica`, or `.offlineFull`; each required row gets a fresh typed
runtime driver. The matrix owns faults, event journal, observed store,
acknowledgements, graph registrations, and `ResourceCensus`; fixtures never
return facts or a residual map. Derive success, expected failure, crash,
cancellation, concurrency, restart, and teardown evidence from those observed
instruments.
Prefer the generated `<Feature>FeatureHarness` in `test/support`; consumers add
only domain fixtures, selected policies, and domain assertions.

Read [references/runtime-and-reactive.md](references/runtime-and-reactive.md),
[references/sync.md](references/sync.md),
[references/provider-fixtures.md](references/provider-fixtures.md),
[references/platform-and-background.md](references/platform-and-background.md), or
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
- Drift: use a consumer-generated test database and real executor; test owned
  and borrowed close, failed configuration cleanup, commit/rollback, watches,
  checkpoint/journal fencing, migration/reopen, and web worker/assets where
  applicable.
- ObjectBox: use consumer-generated entities/model/Store/query/watcher; test
  transactions, same-path locking, cleanup, and isolate attachment on supported
  native hosts.
- Sentry: use a fake Hub, no DSN and zero network; test sanitized mapping,
  prepared-input no-double-redaction, defensive legacy mapping, no automatic
  `SentryUser`, destination failure, duplicate capture prevention, and borrowed
  lifetime.
- Observability privacy: run strict/balanced/diagnostic matrices across local,
  remote, and named destinations; assert `deny > mask > allow`, raw-secret
  absence, cycles, key collisions, Unicode bounds, structural budgets,
  independent slow/failing queues, ownership, snapshots, and detailed flush.
- Custom providers: pair deterministic contract tests with at least one real SDK
boundary fixture that proves version and lifecycle compatibility.
''',
      'references/platform-and-background.md':
          r'''# Platform and background tests

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
''',
      'references/tooling.md': r'''# Tooling tests

Use temporary roots and injected process/filesystem boundaries. Cover read-only
commands, dry-run/apply separation, unknown config rejection, strict findings,
expiring suppressions, stale plans, conflicts, recovery journals, symlink/path escape,
permissions, Unicode and spaces, and idempotent managed-skill sync.

Run consumer-tax schema-2 fixtures for local through offline-full. Require zero
semantic `architectureTax`; scale `generatedTax` by declared axes; reject
string-based architecture tests and structural-only fakes; never charge
consumer domain/UI `productCode`. Analyzer/build timings ratchet only on the
same CI runner.

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
    shortDescription: 'Generate opt-in values, codecs, and pure mappers',
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
    shortDescription: 'Operate config v3, CLI, generators, lints, and gates',
    defaultPrompt:
        r'Use $dartitect-tooling to operate or extend Dartitect tooling.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-tooling
description: Operate or extend the Dartitect CLI, config, verify, scan, doctor, fleet, bounded OpenAPI contracts, lints, semantic compiler, generators, native setup, and release gates. Use for shell/CI architecture tooling; MCP configuration and protocol work belongs to the MCP skill.
---

# Operate Dartitect tooling

## When to use

Use this skill for CLI commands/services, config v3 and migrations,
verify/scanner/doctor policy, bounded local OpenAPI contracts, analyzer
diagnostics, generators, Codex sync, native fixture setup, or repository
release gates.

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
revalidation and hold it through commit, rollback, or recovery. Migrate legacy
pre-stable ownership only when manifest metadata, recorded digest, and current
bytes match.
Every generated file operation has a stable `rendererId`; the formal canary
catalog must cover every package, public entrypoint, renderer, profile,
capability, provider, scope, and target.

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
and bounded. Accept exactly config v3 with `native_strict`; migrate v2 through
the versioned transactional migration chain and reject
experimental versions, unknown keys, credentials, and opaque plugin data.
Destination-aware observability is additive and introduces no config v4.
The target-aware `features` section declares `local`, `online`, `cache`,
`replica`, or `offline-full`, typed factory sources, ownership scopes, and exact
contract operations. Semantic compilation resolves annotations and concrete
method types without loading consumer classes. `verify` checks declarative
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
Sensitive metadata needs a recognized telemetry sink. Keep analyzer/CLI parity
for `DT1050` sensitive logger interpolation, `DT1051` Dio `LogInterceptor`,
`DT1052` production risk acceptance, `DT1053` unclassified custom capture, and
`DT1054` legacy Sentry registration in a prepared runtime. Generated fallback
needs both a reviewed header and configured suffix. Invalid analyzer config is
an explicit diagnostic, never a silent strict-default outcome. Generated
developer observability wiring selects `balanced` and a prepared local sink;
Sentry wiring accepts a prepared runtime callback. Enforce scanner and analyzer
performance budgets with stable machine-readable schemas.

`fleet report`, `fleet inventory`, and `fleet impact` stay read-only. Upgrade
uses a versioned migration chain whose preview records apply/no-op, recovery,
and rollback. Local blueprints use a closed non-executable manifest, digest
lock, project confinement, and preview/apply. Keep process execution in the separate
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
fixtures, clean package archives, and exact-tag Git-consumption canaries in
proportion to the change and as required by the repository workflow.

Pin external Actions by full commit SHA. OSV exceptions are exact advisory IDs
with justification, analysis link, and short expiry; package-wide ignores and
PackageOverrides are forbidden. Distribution is GitHub-only. Distinguish the
workspace cohort/channel from the latest distributed stable cohort and whether
a derivable candidate tag is materialized. Candidate validation uses clean
archives and a local disposable-tag canary; it never authorizes a remote tag,
workflow run, GitHub Release, publication, or promotion. Release rejects
prerelease cohorts before external writes. Platform-specific evidence must run
on its supported host, and builds must leave tracked files unchanged.

For documentation and skill changes, require the documentation classification,
link/include, changelog-cohort, skill-reference, managed snapshot/hash, and MCP
catalog gates. Normal config accepts v3 only; v1/v2 are transactional fleet
migration inputs. `sdkVersion` follows the workspace cohort; public consumption
continues to use the recorded materialized distributed stable cohort. A newer
prepared stable cohort keeps `tagMaterialized` false. Release assets use the
prepared workspace version and record the prior distribution; the immutable
GitHub Release and attestation establish actual publication.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-dart',
    displayName: 'Dartitect Dart',
    shortDescription: 'Apply safe Dart stream and isolate semantics',
    defaultPrompt:
        r'Use $dartitect-dart to review Dart runtime semantics safely.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-dart
description: Apply Dart language and runtime semantics to Dartitect producers, streams, cancellation, cleanup, and isolate data transfer. Use when correctness depends on generator, subscription, stack, or isolate behavior; do not use as a general Dart tutorial or architecture selector.
---

# Apply Dart runtime semantics

## When to use

Use this skill when Dartitect or consumer infrastructure depends on exact
`sync*`/`async*`, single-subscription stream, cancellation, cleanup, stack
preservation, sendability, or transferable-data behavior.

## When not to use

Use `$dartitect-incremental` for the higher-level incremental operation,
Flutter command, sync, or worker-pool contracts. Use `$dartitect-performance`
when the question is primarily capacity, algorithmic complexity, or benchmark
evidence. Do not invoke this skill for ordinary syntax or business logic.

## Invariants

Create cold sources per execution and reject broadcast streams where one owner
must control consumption. Await consumer work before requesting the next item.
Cancellation stops admission, awaits subscription cancellation and producer
`finally`, and fences late publication. A plain `Iterator` has no cancel/close
protocol; resource-owning synchronous sources need an explicit cleanup seam.
Preserve original errors and stacks. Never infer retries or make a VM-only
boundary run silently on the web or main isolate.

## Workflow

Identify the source kind, its owner, the cancellation path, and the terminal
cleanup order before coding. Then check sendability and platform support for
every isolate boundary.

Read [references/streams-and-cancellation.md](references/streams-and-cancellation.md)
for producer and subscription behavior, and
[references/isolate-data.md](references/isolate-data.md) for worker messages and
transferable bytes.

## Validate

Test list, `sync*`, `async*`, consumer failure, producer failure with original
stack, cancellation during work, exact-once cleanup, nested stream behavior,
unsupported web use, and zero late values or residual workers.
''',
      'references/streams-and-cancellation.md': r'''# Streams and cancellation

A producer factory is an execution boundary: invoke it again for every run.
Single-subscription streams let the owner pause or cancel consumption; a
broadcast stream does not provide that ownership contract. Await the per-item
callback before pulling again rather than relying on an `async` listen callback
whose upstream continues unchecked.

On cancellation or deadline, stop accepting values, await
`StreamSubscription.cancel()`, and let an `async*` producer finish its
`finally` before exposing the terminal result. Fence generation/publication so
an already scheduled callback cannot publish afterward. Keep synchronous CPU
work bounded between emissions because cancellation cannot preempt it.

Do not promise cleanup for an arbitrary `Iterable`: Dart's `Iterator` has no
close method. Use finite resource-free iterables, or an owned source with an
explicit idempotent close callback. Cleanup errors stay named and retain their
original cause and stack.
''',
      'references/isolate-data.md': r'''# Isolate data and workers

Create a fresh isolate-local graph and exchange only sendable messages. Do not
transfer live clients, Stores, subscriptions, commands, owners, or closures
that capture them. Handler functions must satisfy the supported VM isolate
entry contract; fail explicitly on unsupported platforms.

`TransferableTypedData` transfers ownership after construction without an
automatic intermediate materialization. Keep it opaque through dispatch and
materialize only at the endpoint that needs bytes.

Cancellation acknowledges completion only after handler cleanup. A worker
crash never proves whether an admitted request applied, so replacement may
serve future work but must not replay the crashed request. Drain admitted work
before safe-stop unless an explicit terminal failure makes completion
impossible.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-incremental',
    displayName: 'Dartitect Incremental',
    shortDescription: 'Build bounded incremental Dartitect operations',
    defaultPrompt:
        r'Use $dartitect-incremental to build a bounded incremental flow.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-incremental
description: Build bounded incremental Dartitect operations across core, Flutter, sync datasets, and isolate worker pools. Use when work must stream items with backpressure, partial aggregates, cancellation, or bounded admission; do not use for ordinary one-shot commands.
---

# Build incremental operations

## When to use

Use this skill when a workload should expose the first result before the whole
input completes, reduce an explicit aggregate item by item, checkpoint each
confirmed sync step, or dispatch a bounded sequence across isolates.

## When not to use

Keep a finite one-shot command or dataset one-shot when partial progress has no
consumer value. Use `$dartitect-dart` when only language-level stream/isolate
semantics need review and `$dartitect-performance` for profiling or hot-path
changes unrelated to the incremental API.

## Invariants

Import opt-in incremental entrypoints. Bound both item count and cumulative
weight, reject the item that would cross either limit, and retain nothing unless
the caller explicitly folds, collects within a bound, or supplies a ring
buffer. Stop at the first typed `Err`; preserve crashes and stacks. Cancellation
or deadline awaits cleanup before the terminal and prevents late publication.

Flutter coalescing changes notifications only: every admitted item still passes
through the reducer. Sync confirms a checkpoint before pulling the next item.
Worker pools bound workers, in-flight requests, queued requests, and completed
results waiting for order.

## Workflow

Choose the source ownership model, limits and weight, aggregate, expected
failure type, concurrency policy, publication policy, and terminal receipt.
Make the producer factory cold and explicit, then connect only the integrations
the workload requires.

Read [references/operations.md](references/operations.md) for core execution and
[references/flutter-sync-and-pools.md](references/flutter-sync-and-pools.md) for
the Flutter, dataset, and isolate projections.

## Validate

Test zero/one/many items, slow consumers, first `Err`, crashes with original
stack, count/weight boundaries, cancellation/deadline cleanup, partial
aggregate, bounded retention, restart/dispose fencing, checkpoint-before-pull,
pool capacity, ordered/unordered mapping, and zero late work.
''',
      'references/operations.md': r'''# Incremental operations

Use `package:dartitect/dartitect_incremental.dart`. Construct
`IncrementalOperation.sync`, `.syncCloseable`, or `.async` with a factory that
creates a fresh source for each execution. Plain sync producers are only for
finite resource-free iterables; owned synchronous resources use the closeable
variant.

`IncrementalLimits` defaults to 100,000 emissions and 100,000 weight units.
Without `weightOf`, each successful item weighs one. Sequence numbers start at
one and timestamps use the injected UTC clock. `consume` retains no item;
`fold` returns the explicit aggregate and report; `collectBounded` returns the
explicit bounded items and report. Use `BoundedRingBuffer<T>` only when ordered
recent retention is an actual requirement.

Await `onValue` before the next emission. The first `Err` is terminal. Reject a
broadcast stream. Limit violations exclude the crossing item. A cancellation
or deadline cancels and awaits the subscription/source cleanup before returning
a cancelled or deadline report.
''',
      'references/flutter-sync-and-pools.md':
          r'''# Flutter, sync, and worker pools

Import `dartitect_flutter_incremental.dart` for the no-argument
`IncrementalCommand`. Each execution begins from a fresh initial aggregate.
Choose `everyEmission`, `coalesceMicrotask`, or `coalesceFrame`; coalescing never
skips reducer calls. Terminal states retain the partial aggregate, count,
weight, execution ID, and payload-free receipt. Use `restartLatest` only when
old execution publication is generation-fenced. The state builder accepts a
static child and stays Material-neutral.

`SyncDataset.incremental` serializes each successful checkpoint before asking
for another item. Sequential is the default; bounded DAG parallelism admits
ready nodes in plan order, runs only independent nodes, continues unrelated
branches after typed failure, blocks descendants, and fails fast on crashes.
Checkpoint, lease, and journal ports remain single-flight even when nodes run
in parallel.

`IsolateWorkerPool.spawn` requires explicit size, in-flight, and queue bounds.
`mapSequence` pauses input at capacity and bounds completed values waiting for
preserved order. Consumer cancellation drains input and admitted requests.
`failPool` is the default crash policy; `replaceWorker` spends a finite budget
without replaying an uncertain request. `disposeAsync` closes admission, drains,
then safely stops workers.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-performance',
    displayName: 'Dartitect Performance',
    shortDescription: 'Bound and measure Dartitect runtime efficiency',
    defaultPrompt:
        r'Use $dartitect-performance to bound and measure a runtime path.',
    files: <String, String>{
      'SKILL.md': r'''---
name: dartitect-performance
description: Diagnose, improve, and benchmark Dartitect runtime efficiency with bounded structures and structural complexity gates. Use for hot queues, listener dispatch, DAG scheduling, retention, scan throughput, or benchmark evidence; do not use for speculative micro-optimization.
---

# Bound runtime efficiency

## When to use

Use this skill when a repeated path may grow with emissions, listeners,
dependencies, destinations, files, queued work, or retained history, or when a
change needs reproducible latency, memory, or throughput evidence.

## When not to use

Do not optimize an unmeasured cold path or trade away public ordering,
ownership, cancellation, privacy, or failure semantics. Use
`$dartitect-incremental` to design the incremental contract and
`$dartitect-dart` to resolve language-runtime correctness first.

## Invariants

Every in-memory queue and history has a visible capacity or eviction policy.
FIFO front removal is constant-time, retained weight is maintained in O(1),
listener dispatch is reentrancy-safe O(N), and topological scheduling uses
dependents plus indegrees rather than repeated full scans. Preserve stable
public order and isolate callback failures.

Structural complexity and bounds are release gates. Wall time, RSS, first item,
p50, and p95 are informative unless compared on the same controlled runner.
Never weaken cleanup, backpressure, or privacy to improve a benchmark.

## Workflow

State the input scale and required bound, inspect the execution model, identify
the retained state and asymptotic path, make the smallest semantics-preserving
change, then measure a curated set of representative cases.

Read [references/hot-paths.md](references/hot-paths.md) for implementation
patterns and [references/measurement.md](references/measurement.md) for the
benchmark and evidence contract.

## Validate

Prove capacity rejection/eviction, stable order, reentrant removal, isolated
callback crashes, linear DAG/listener behavior, bounded slow-consumer state,
cancellation cleanup, and identical public results. Run positive and negative
execution-model fixtures and record benchmark environment with every metric.
''',
      'references/hot-paths.md': r'''# Hot paths and bounded state

Use `ListQueue` for FIFO admission and `BoundedRingBuffer<T>` for explicit
ordered recent retention. Do not use `List.removeAt(0)` or rebuild a retained
collection merely to append or evict. Track cumulative retained weight during
insert/evict rather than rescanning history.

For listeners, keep stable registrations with tombstones. Dispatch over the
current stable registry once, allow removal during callbacks, defer compaction
while dispatch is nested, and isolate one callback failure without a snapshot
plus repeated membership checks.

For DAG work, compile a dependent map and indegree count once. Admit ready nodes
through a stable queue, update only their dependents, and preserve declared
topological order in reports. For destination policy, compile winner lookup and
sanitize a classified/projected structure once before fan-out.

Run `dartitect inspect execution-model [--json]` for DT2200-DT2211 evidence.
Heuristics are informational; structurally strong findings may warn, but the
inspection remains non-blocking unless usage or internal execution fails.
''',
      'references/measurement.md': r'''# Measurement and evidence

Start with structural gates: bounded queues/retention, one classification per
node, no quadratic readiness scan, backpressure, exact cleanup, no late
publication, and no residual request/worker. These are portable correctness
claims and may block release.

Use a curated matrix rather than a full Cartesian product. Cover 0, 1, 32,
1,000, and 100,000 emissions where practical; eager inputs, generators, and
batches; slow consumers and cancellation; multiple telemetry destinations;
and representative Flutter, sync, isolate, and CLI paths. Measure first item,
total time, RSS or retained state, throughput, and p50/p95 where the harness can
do so reproducibly.

Record SDK/runtime, OS, CPU architecture, mode, warmup, iteration count, input,
and bounds. Treat absolute time and memory as informational across different
runners. Compare regressions only on the same runner and preserve raw receipts
or machine-readable summaries needed to reproduce the conclusion.
''',
    },
  ),
  DartitectSkillTemplate(
    name: 'dartitect-mcp',
    displayName: 'Dartitect MCP',
    shortDescription: 'Use bounded local MCP tools and reviewed writes',
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
config v3. There is no free-form file resource. Results include structured
content plus compatible JSON text. Read tools/previews are annotated read-only;
only apply is mutable/destructive.
Privacy-bypass diagnostics `DT1050` through `DT1054` are catalog resources.
Route destination policy to `$dartitect-observability`; MCP never reads runtime
telemetry payloads or exposes the DevTools privacy RPC.
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
