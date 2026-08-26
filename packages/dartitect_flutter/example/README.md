# Reactive offline-first examples

`reactive_offline_first_example.dart` imports only the headless reactive
entrypoint. It owns a route-scoped paged resource, observes an in-memory local
authority, and renders item-specific listenables. Consumer applications compose
those builders with their own Material or Cupertino widgets.

The example is credential-free and uses no network or generated database.
The route owns teardown: paged work/listeners close before the local source.
Production repositories should implement the same contracts with a real local
transaction and durable outbox.
