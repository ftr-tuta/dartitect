# dartitect_flutter

## Purpose

Flutter primitives for owned or borrowed ViewModels, bounded asynchronous
commands, selected rebuilds, explicit scope identity, one-shot effects, session
state, foreground error binding, forms, queries, space-based layout, and an
opt-in owned reactive runtime.

## When to use

Use the default entrypoint when native `Listenable`/`ChangeNotifier` plus visible
ViewModel ownership are sufficient. Add the reactive entrypoint when a feature
needs typed graph state, hot/warm/cold resources, families, collections, or
local-authority paging. Add the incremental entrypoint when every item must
update a partial aggregate while UI notifications use a separate cadence.

## When not to use

Do not import this package into pure-Dart domain/application layers. Do not add
the reactive runtime when a small native listenable is enough. It does not
provide navigation, Material/Cupertino design, repositories, persistence, a
provider container, or widget-context service lookup.

## Platforms and entrypoints

Flutter is required on its supported platforms.

- `package:dartitect_flutter/dartitect_flutter.dart` is the thin lifecycle,
  command, scope, effect, session, and error-binding entrypoint.
- `package:dartitect_flutter/dartitect_flutter_forms.dart` exposes form state,
  validation, submission, drafts, history, restoration, and its exhaustive
  borrowed snapshot builder.
- `package:dartitect_flutter/dartitect_flutter_queries.dart` exposes filter,
  pagination, selection, restoration, and its exhaustive borrowed state
  builder.
- `package:dartitect_flutter/dartitect_flutter_reactive.dart` is an opt-in
  entrypoint for the owned reactive runtime. It does not export Material
  widgets.
- `package:dartitect_flutter/dartitect_flutter_incremental.dart` is the opt-in,
  Material-neutral projection of a core incremental operation into sealed
  command states and a borrowed state builder.
- `package:dartitect_flutter/dartitect_flutter_ui.dart` exposes only size
  classes, validated breakpoints, and space-based builders. It owns no visual
  control, theme, text, locale, navigation, or state.

## Mental model and data flow

A composition root constructs a ViewModel and injects application ports.
Authoritative state flows down through native listenables; user intent travels
up through methods or Commands. `DartitectViewModel` centrally owns commands
and feature-local resources, forwards their notifications, and drains them in
reverse order. A `ViewModelHost` owns or borrows the ViewModel explicitly.
One-shot UI reactions travel through a bounded `EffectChannel` and are consumed
by one mounted `EffectListener`; replayable session truth uses
`SessionStateController` instead.

In the reactive entrypoint, one `ReactiveOwner` owns typed values, computeds,
resources, groups, families, and collections. Each resource opens fresh
activation-local upstream state, borrows providers, and publishes only current
generation results.

## Minimal workflow

```dart
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

Widget counterFeature() => ViewModelHost<_Counter>.create(
  create: _Counter.new,
  builder: (context, counter) => ListenableBuilder(
    listenable: counter,
    builder: (context, child) => Text('${counter.value}'),
  ),
);

final class _Counter extends ChangeNotifier {
  int value = 0;

  void increment() {
    value += 1;
    notifyListeners();
  }
}
```

`ViewModelHost.value` is the borrowed equivalent. See the package example for a
route-owned reactive paging graph.

## Public API tour

Thin entrypoint:

- `DartitectObservableResource`, `DartitectCommand<T, F>`,
  `DartitectViewModel`, `ownCommand`, `own`, and `forward` provide compile-time
  command/resource ownership, notification forwarding, and idempotent
  reverse-order teardown.
- `ViewModelHost.create`/`value`, `ViewModelStarter`,
  `ViewModelReassembler`, and `ViewModelDisposer` define ViewModel lifetime.
- `Command0`, `Command1`, and `KeyedCommand1` expose reject, join, drop,
  sequential, restart-latest, concurrent, and bounded per-key policies with
  exhaustive `CommandState`, `CommandState.match`, and `CommandExecution`
  types.
- `CommandStateBuilder<T, F>` requires builders for all six command states,
  supplies no visual defaults, borrows its command, and pauses listening below
  disabled `TickerMode`.
- `ProgressCommand0`, `ProgressCommand1`, and `KeyedProgressCommand1` preserve
  those policies while injecting execution-fenced typed progress contexts.
- `ApplicationHost` owns bootstrap/retry/atomic publication and
  `SessionRuntimeController` plus `SessionHost` coordinate route-confirmed
  session replacement without closing application resources.
- `FeatureHost` transactionally creates one child feature graph and ViewModel,
  publishes loading/failure/ready, fences late attempts, and closes the
  ViewModel before feature resources without selecting Material or product UI.
- `VersionedRestorationCodec`, `RestorableVersionedValue`, and
  `LocalHistoryListenable` adapt explicitly bounded ephemeral UI state.
- `ListenableSelector` rebuilds only when the selected value changes and detaches
  while its `TickerMode` is disabled.
- `DartitectScope` marks a stable composition boundary; its opaque
  `scopeIdentity` is not a service locator.
- `EffectChannel`, `EffectSink`, `EffectSubscription`, and `EffectListener`
  implement bounded single-consumer transient delivery.
- `SessionStateController` and exhaustive session states model replayable shell
  and logout transitions separately from effects.
- `FirstFrameGate`, `FlutterErrorBinding`, crash reporters, and binding-build
  events cover explicit first-frame and foreground error integration.

Reactive entrypoint:

- `ReactiveOwner` owns typed-key `ReactiveValue` and `ReactiveComputed` nodes,
  atomic updates, equality, diagnostics, and invalidation groups.
- `ReactiveLazyComputed` evaluates explicit dependencies only on first use,
  remains dirty after failed computation, and supports hot-reload rebinding
  without global read tracking.
- `LiveResource`, `ReactiveSource`, `ReactiveSourceSession`, activation policies,
  source adapters, backpressure, observations, and leases define causal reads.
- `DerivedAsyncResource` is a stable generation-guarded derivation from
  explicit Flutter listenables.
- `ResourceFamily` bounds shared resources by TTL, count, weight, and leases.
- `LiveCollection` separates structure from item nodes and supports replace,
  diff-by-key, and versioned projection policies.
- `PagedLiveResource` writes remote batches through a consumer local transaction
  and advances only after the matching local revision is observed.
- `ReactiveSelector` and `DebouncedReactiveValue` provide headless derived
  values. Reactive/resource/collection/paged builders borrow their input and
  listen only while ticker-enabled.
- `ResourcePresentationBuilder` exhaustively renders loading, content, empty,
  expected failure, and crash presentations, including stale content, while
  borrowing the resource and following `TickerMode`.

Incremental entrypoint:

- `IncrementalCommand` reduces every emitted item while
  `IncrementalPublication` controls only notification cadence. It reuses
  `CommandConcurrency`, including restart-latest, and fences scheduled
  callbacks after restart or disposal.
- Sealed incremental idle, running, succeeded, failed, cancelled, and crashed
  states retain partial aggregate facts and payload-free receipts.
- `IncrementalCommandStateBuilder` requires all six branches, borrows the
  command, accepts a static child, and follows `TickerMode` without Material.

Forms, queries, and UI entrypoints:

- `DartitectFormSnapshotBuilder` and `DartitectQueryStateBuilder` render their
  existing state authorities exhaustively, borrow their controllers, and
  recover the current state after ticker reactivation.
- `DartitectSizeClass`, `DartitectWindowClass`, and
  `DartitectLayoutBreakpoints` classify width and height independently. Exact
  thresholds enter the larger class.
- `DartitectResponsiveWindowBuilder` uses `MediaQuery.sizeOf`, while
  `DartitectResponsiveRegionBuilder` requires finite `LayoutBuilder` width.
  Both require compact, medium, and expanded branches and preserve no state
  implicitly.

## Ownership and lifecycle

Create ViewModels and reactive graphs at the nearest app, session, route, or
feature composition boundary. `ViewModelHost.create` disposes its value;
`ViewModelHost.value` never does. A reactive owner owns its nodes, but sources
borrow clients/databases and own only activation-local watchers, queries,
subscriptions, and cursors.

Dispose consumers before their sources: builders/listeners, paged resources,
families/collections, live resources, source sessions, then provider resources.
Install one `FlutterErrorBinding` and restore the previous handlers during
shutdown. Hot reload may rebind compatible definitions; hot restart builds a
new graph.

## Failure, cancellation, and concurrency

Commands distinguish expected `Err<F>`, unexpected crashes, rejected/dropped
admission, cooperative cancellation, and success. Queue/running/key bounds are
explicit. Restart-latest and concurrent modes reject stale terminal
publication. Disposal closes admission, cancels queued work, requests
cancellation, and drains active actions.

Resources keep data state separate from temperature. Expected open/read failures
publish `ResourceFailed`; unexpected failures publish `ResourceCrashed`, report
once, close the current session, and require explicit `retry()`. Source
backpressure is bounded. Paging joins refresh, drops reentrant load-more, and
uses restart-latest for search. Disposal prevents late publication and
aggregates independent cleanup failures.

## Prohibited uses and limitations

- No `BuildContext` in ViewModels, services, repositories, domain, or data.
- No provider/container lookup through `DartitectScope`.
- No second owner publishing the same feature state.
- No authentication/session truth encoded as a one-shot effect.
- No unbounded command queue, family cache, collection tombstone set, or source
  backlog.
- No persistence or atomicity claim without a consumer-owned local transaction.

Derived resources and diagnostics are stable. Background projection requires
transferable inputs/outputs and cannot interrupt native work already running.

## Testing

Run `flutter test`. Cover owned versus borrowed hosts, start/reassemble/dispose,
all chosen command policies, stale completions, selected rebuilds, ticker/route
pause-resume, effect FIFO/overflow/detach, session replacement, expected and
unexpected resource failures, family eviction, item-level notifications, causal
page timelines, text scaling, semantics, and keyboard actions.

## Related packages and guides

Use `dartitect` for pure-Dart results/ownership, `dartitect_sync` for durable
mutation and dataset sync, a persistence adapter for provider-backed sources,
`dartitect_testing` for deterministic runtime harnesses, and
`dartitect_flutter_testing` as a dev dependency for the paired UI matrix. Read
[commands/results/effects](../../docs/guides/commands-results-effects.md),
[reactive runtime](../../docs/guides/reactive-runtime.md), and
[UI quality](../../docs/guides/ui-quality.md). Incremental consumers should
read the [incremental operations guide](../../docs/guides/incremental-operations.md)
and [Flutter example](example/incremental_command_example.dart).

## Availability

Dartitect `1.0.0` is distributed only by the annotated `v1.0.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
