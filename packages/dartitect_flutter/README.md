# dartitect_flutter

## Purpose

Flutter primitives for owned or borrowed ViewModels, bounded asynchronous
commands, selected rebuilds, explicit scope identity, one-shot effects, session
state, foreground error binding, and an opt-in owned reactive runtime.

## When to use

Use the default entrypoint when native `Listenable`/`ChangeNotifier` plus visible
ViewModel ownership are sufficient. Add the reactive entrypoint when a feature
needs typed graph state, hot/warm/cold resources, families, collections, or
local-authority paging.

## When not to use

Do not import this package into pure-Dart domain/application layers. Do not add
the reactive runtime when a small native listenable is enough. It does not
provide navigation, Material/Cupertino design, repositories, persistence, a
provider container, or widget-context service lookup.

## Platforms and entrypoints

Flutter is required on its supported platforms.

- `package:dartitect_flutter/dartitect_flutter.dart` is the thin lifecycle,
  command, scope, effect, session, and error-binding entrypoint.
- `package:dartitect_flutter/dartitect_flutter_reactive.dart` is an opt-in
  entrypoint for the owned reactive runtime. It does not export Material
  widgets.

## Mental model and data flow

A composition root constructs a ViewModel and injects application ports.
Authoritative state flows down through native listenables; user intent travels
up through methods or Commands. A `ViewModelHost` owns or borrows the ViewModel
explicitly. One-shot UI reactions travel through a bounded `EffectChannel` and
are consumed by one mounted `EffectListener`; replayable session truth uses
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

- `ViewModelHost.create`/`value`, `ViewModelStarter`,
  `ViewModelReassembler`, and `ViewModelDisposer` define ViewModel lifetime.
- `Command0`, `Command1`, and `KeyedCommand1` expose reject, join, drop,
  sequential, restart-latest, concurrent, and bounded per-key policies with
  exhaustive `CommandState` and `CommandExecution` types.
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
- `LiveResource`, `ReactiveSource`, `ReactiveSourceSession`, activation policies,
  source adapters, backpressure, observations, and leases define causal reads.
- `DerivedAsyncResource` is an experimental generation-guarded derivation from
  explicit Flutter listenables.
- `ResourceFamily` bounds shared resources by TTL, count, weight, and leases.
- `LiveCollection` separates structure from item nodes and supports replace,
  diff-by-key, and versioned projection policies.
- `PagedLiveResource` writes remote batches through a consumer local transaction
  and advances only after the matching local revision is observed.
- `ReactiveSelector` and `DebouncedReactiveValue` provide headless derived
  values. Reactive/resource/collection/paged builders borrow their input and
  listen only while ticker-enabled.

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

Derived resources and diagnostic construction remain experimental. Background
projection requires transferable inputs/outputs and cannot interrupt native
work already running.

## Testing

Run `flutter test`. Cover owned versus borrowed hosts, start/reassemble/dispose,
all chosen command policies, stale completions, selected rebuilds, ticker/route
pause-resume, effect FIFO/overflow/detach, session replacement, expected and
unexpected resource failures, family eviction, item-level notifications, causal
page timelines, text scaling, semantics, and keyboard actions.

## Related packages and guides

Use `dartitect` for pure-Dart results/ownership, `dartitect_sync` for durable
mutation and dataset sync, a persistence adapter for provider-backed sources,
and `dartitect_testing` for deterministic harnesses. Read
[commands/results/effects](../../docs/guides/commands-results-effects.md),
[reactive runtime](../../docs/guides/reactive-runtime.md), and
[composition/lifecycle/isolates](../../docs/guides/composition-lifecycle-isolates.md).

## Availability

The workspace contains the `1.0.0-rc.4` source candidate. Supported experimental
Git consumption requires a matching tag and published GitHub Release plus the
complete cohort coordinates in its notes. Without that Release, there is no
supported consumption path. See the
[experimental consumption guide](../../docs/guides/git-candidate-consumption.md).
