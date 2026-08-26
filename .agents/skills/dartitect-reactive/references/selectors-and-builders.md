# Selectors and builders

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
