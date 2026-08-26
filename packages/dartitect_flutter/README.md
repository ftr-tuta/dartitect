# dartitect_flutter

[Português (Brasil)](README.pt-BR.md)

## Purpose

Thin Flutter primitives for owned/borrowed ViewModels, async commands,
selected rebuilds, stable composition scope, and foreground Flutter errors.

## When to use it

Use it when native `ChangeNotifier`, `Listenable`, and widget lifecycle are
enough but ownership and command state need explicit contracts. It does not
replace Flutter navigation, widgets, or a domain layer.

The established `dartitect_flutter.dart` library remains thin. Advanced
headless reactive APIs are introduced through the opt-in
`dartitect_flutter_reactive.dart` entrypoint. Material rendering remains in the
consumer application.

## When not to use it

Do not import it into pure-Dart domain/application code. Do not opt into the
reactive entrypoint when the thin `ChangeNotifier`, command, and
ViewModel lifecycle APIs already satisfy the feature.

## Recommended combinations

Combine the thin entrypoint with `dartitect`; add the reactive entrypoint for
hot/warm/cold resources and local-authority pages. Build Material/Cupertino
presentation in the application. Add provider adapters behind repositories. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_flutter: 1.0.0-rc.2` and use the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md)
to pin it and `dartitect` to the protected tag.

## Minimal example

```dart
final command = Command0<int, String>(
  () async => const Ok(42),
  concurrency: const CommandConcurrency.join(),
);
final execution = await command.execute();
await command.disposeAsync();
```

See `example/dartitect_flutter_example.dart` for an executable widget example.

## Public API tour

- `Command0<T, F>`, `Command1<A, T, F>`, and the dedicated
  `KeyedCommand1<K, A, T, F>` expose bounded reject, join, drop, sequential,
  restart-latest, concurrent, and per-key policies. State includes exact
  running/queued counts and accepted/terminal execution IDs.
- `ViewModelHost.create` owns a value and calls its optional `start` once
  without delaying the first build; `ViewModelHost.value` only borrows it.
- `ListenableSelector` rebuilds only when its selected value changes and
  detaches while its surrounding `TickerMode` is disabled.
- `DartitectScope<T extends DartitectScopeValue>` marks an explicit
  composition boundary. Its opaque `scopeIdentity` must remain identical for
  the lifetime of the inherited widget; it is not a service locator.
- `EffectChannel<E>` is a bounded, single-consumer FIFO owned by an explicit
  application/session/route generation. `EffectListener` alone uses the
  currently mounted context. `SessionStateController<S>` carries replayable
  shell/logout state separately from one-shot effects.
- `FlutterBindingBuildEvent` reports only binding kind, count, duration,
  local-handle count, and ticker status; it never carries domain payloads.
- `FlutterErrorBinding` chains and restores handlers through an injected
  `ErrorReporter`.
- The opt-in reactive entrypoint exposes `ReactiveOwner`, atomic `update`
  transactions, typed-key values/computeds that directly implement
  `ValueListenable<T>`, per-node equality, and deterministic diagnostics.
  Each outer update can emit one sanitized `ReactiveChangeEvent` through an
  explicitly owned or borrowed observer; custom causes must be pre-registered
  static identities.
- `ResourceLifecycle` separates data from hot/warm/cold temperature;
  `ReactiveObservation` and `AsyncLifecycleBarrier` bound activity and teardown.
- `LiveResource<T, F>` opens one activation-local `ReactiveSource` session and
  applies explicit `everyEmission`, microtask, frame, or latest-while-busy
  backpressure. The default permits at most the active read plus one rerun.
- `FutureReactiveSource`, `StreamReactiveSource`, `ListenableReactiveSource`,
  and `ValueListenableReactiveSource` adapt existing async/native primitives
  into fresh activation-local sessions without taking ownership of borrowed
  listenables.
- `InvalidationGroup<K>` shares typed invalidations: hot resources refresh,
  warm snapshots become stale until reactivation, and cold resources do no
  work. `ReactiveOwner.invalidationGroup` owns group teardown.
- `RemoteRefresh`, `LocalCommitRefresh`, and `ObservedLocalRefresh` encode three
  distinct completion points. The observed form matches a
  `LocalCommitReceipt<R>` to `ObservedValue<T, R>` with a required typed timeout.
- `ResourceFamily<K, T, F>` shares resources only inside one owned family.
  Explicit `FamilyLease` values retain active entries; idle entries are bounded
  by TTL, count, and weight with stable recreation-cost/LRU ordering. `prewarm`
  owns its observation and timer.
- `LiveCollection<K, T>` exposes separate keys, length, item, and change signals.
  Choose `replaceAll`, `diffByKey`, or `versionedByKey` explicitly; versioned
  updates reuse projections and notify only changed item nodes. Removed items
  remain bounded tombstones while observed or warm.
  `updateProjected` remains inline by default; explicit background execution
  requires an injected `ProjectionExecutor` and publishes only a matching,
  non-cancelled generation of transferable outputs. A worker crash preserves
  the snapshot and stays diagnostic as `CollectionProjectionStatus.crashed`
  until an explicit later projection succeeds.
- `ReactiveSelector<S, T>` derives a headless equality-aware value, while
  `DebouncedReactiveValue<T>` owns and cancels its injected quiet-period timer.
- `PagedLiveResource<C, K, T, F>` requests remote `PageBatch` values, removes
  duplicate keys, and passes them to a consumer-owned local transaction. Its
  `LiveCollection` changes and cursor advance only after the borrowed local
  source observes the exact `PageWriteReceipt` revision. Refresh joins,
  load-more drops reentrancy, and search uses restart-latest cancellation.
- `ReactiveValueBuilder`, `LiveResourceBuilder`, `LiveCollectionBuilder`, and
  `PagedLiveBuilder` are headless, borrow their inputs, and listen only while
  `TickerMode` is enabled. Collection structure and individual item rebuilds
  remain separate. Their optional build observer receives the same sanitized
  facts as the thin selector.

## Ownership

Create ViewModels at the nearest composition boundary. A `.create` host calls
its disposer; a `.value` host never disposes the borrowed value. Install one
`FlutterErrorBinding` and restore it during shutdown.

## Limitations

Keep `BuildContext` out of ViewModels, services, repositories, domain, and data.
Expected command failures are state and are not automatically reported.
Expected source failures retain last-known data. Unexpected source crashes are
reported once, close the upstream, and require an explicit `retry()`.

## Extending

ViewModels can implement native `Listenable`; reporting uses
`dartitect_observability` contracts, so custom providers need no Flutter API.

## Testing

Run `flutter test`. Cover busy/disposed rejection, retry, stale completion,
selector fan-out, debounce teardown, causal page timelines, unexpected rethrow,
selected rebuilds, TickerMode pause/resume, semantics, keyboard actions, text
scaling, keyed reorder, and handler chain/restore.

## Links

See [commands/results/effects](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/commands-results-effects.md),
[reactive runtime migration](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/reactive-runtime-migration.md),
[lifecycle/isolate composition](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/composition-lifecycle-isolates.md), and the [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
