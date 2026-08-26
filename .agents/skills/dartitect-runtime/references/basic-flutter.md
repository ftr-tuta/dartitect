# Basic Flutter runtime

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
