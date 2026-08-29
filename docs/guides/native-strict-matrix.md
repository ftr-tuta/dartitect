# Native Strict Flutter-to-Dartitect matrix

`native_strict` is the sole Dartitect 1.0 architecture profile. Feature
behavior profiles never relax it.

| Responsibility | Native-strict contract | Public surface | Consumer-owned seam |
| --- | --- | --- | --- |
| App startup | Binding, first-frame gate, atomic publication, teardown | `runDartitectApplication` | Widget returned for the committed graph |
| Composition | Direct constructors; no container, locator, nullable slot, or provider-name field | generated typed `ApplicationGraph`, `SessionModule`, and capability-closed `FeatureAssembly` | repositories, domain policy, mappings, UI |
| View/ViewModel | Constructor-injected state; no provider lookup | `ViewModelHost`, Commands, reactive APIs | presentation and application ports |
| Session | Typed route removal, 10-second default deadline, retry/abort | `SessionRuntimeController` | authentication and route policy |
| Persistence | One writer per dataset; local authority where declared | Drift/ObjectBox operational kits | domain schema, queries, migrations |
| Failure | Expected failures are values; crashes keep original stacks | `Result<T, F>` and sealed workflow results | domain failure types and rendering |
| Headless | Fresh owned graph, versioned envelope, deadline, receipt | jobs, sync, Workmanager | recurrence, credentials, payload codec |
| Diagnostics | Closed payload-free v2 facts; zero disabled subject allocation | core diagnostics and DevTools | provider destination selection |

Riverpod, BLoC, Provider, GetIt, MobX, Signals, and similar architecture
runtimes are not valid dependencies of a native-strict application. This is an
ownership contract, not a quality judgment about those packages.

Use `dartitect scan`, `dartitect doctor`, and `dartitect verify --root .` as the
project gate. A greenfield Native Strict project must resolve every finding;
architecture debt baselines are not supported.
