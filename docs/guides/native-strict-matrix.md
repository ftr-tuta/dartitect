# Native Strict Flutter-to-Dartitect matrix

Dartitect 1.0 defines a Native Strict profile for Dartitect-owned code. Existing
projects may adopt a feature or boundary incrementally beside another runtime,
provided each feature has one composition/state/lifecycle authority and no
provider or service-locator API leaks into the Dartitect-owned graph.

| Flutter/application responsibility | Native Strict contract | Primary Dartitect surface | Consumer-owned boundary |
| --- | --- | --- | --- |
| View | Receives a ViewModel or immutable presentation input; never locates repositories, clients, Stores, or application services from `BuildContext` | `ViewModelHost`, builders, `EffectListener` | Widget tree, Material/Cupertino presentation, routing |
| ViewModel | Constructed at an explicit app/session/feature/route root; owns only its declared lifetime | `dartitect_flutter`, `ResourceOwner`, `OwnedGraph` | Feature policy and injected application ports |
| Writes | Relevant writes are methods, Commands, or explicit transactions; getters, selectors, computeds, and `build` are effect-free | `Command0`/`Command1`, command lanes, reactive transactions | Domain mutation policy and provider transaction implementation |
| Expected failure | Exhaustive typed success/failure; unexpected exceptions remain crashes with their original stack | `Result<T, F>` | Domain/application failure types and user-facing rendering |
| Dependency injection | Constructor injection from visible composition roots; no service locator or context lookup | Owned graphs and explicit constructors | Which concrete repository/client/provider is selected |
| Repository | Application/domain port points inward; SDK types stay in infrastructure | Optional Dio/ObjectBox adapters at composition only | Entities, schema, database/HTTP operations, serialization, idempotency, conflict and retry policy |
| Unidirectional data flow | Authoritative state publishes down; intent travels through a method/Command; reads never write | Values, computeds, resources, collections, Commands | Feature-specific state shape and event-to-intent mapping |
| Session lifetime | One generation owns session resources; logout/switch removes routes, closes admission, drains, then disposes | `OwnedRuntimeSlot`, `SessionStateController` | Authentication, credentials, tenant/account policy |
| One-shot effects | Typed, bounded, at-most-once local delivery; context exists only in the mounted Flutter consumer | `EffectChannel`, `EffectListener` | Navigation, dialogs, snack bars, and route-active policy |
| Local-first state | Local repository publication is presentation authority; remote work writes through the repository and waits for causal observation | `LiveResource`, `PagedLiveResource`, mutation/outbox and sync orchestration contracts | Store transaction, durable outbox, checkpoint codec, scheduling, fencing support and distributed protocol |

Riverpod, BLoC, Provider, GetIt, MobX, Signals, and similar runtimes may remain
outside a Dartitect-owned feature boundary. They are incompatible only when
they become a second composition/state/lifecycle authority for the same graph.
This is a scope contract, not a quality judgment about those packages.

Use `dartitect scan --no-baseline` as the canonical conformance gate for a new
project. Baselines describe reviewed legacy debt only and never weaken that
greenfield gate.
