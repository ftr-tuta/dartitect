# Config v3 and concrete graphs

`dartitect.json` accepts exactly `configVersion: 3` and the
`native_strict` architecture profile. Unknown fields fail with an exact JSON
Pointer. Normal loading does not accept older schemas; `fleet upgrade` owns the
versioned v1→v2→v3 migration chain and records every migration as `apply` or
`no-op`.

## Lifetimes and factories

Every storage context and transport declares a `scope` (`application` or
`session`) and a typed `factorySource`. A session-scoped context or feature
requires `session.factorySource`. Application features cannot borrow
session-scoped resources.

Factory sources must be importable Dart libraries inside the project. Their
declarations are concrete, final, non-generic classes with zero-argument
constructors and one resolved Dartitect annotation:

- `@DartitectApplicationContextFactory` or
  `@DartitectSessionContextFactory` for storage;
- `@DartitectTransportContextFactory` for transport;
- `@DartitectSessionFactory` for authenticated-session roots; and
- `@DartitectFeatureFactory` for a feature.

The semantic compiler resolves annotations, method signatures, concrete types,
ownership, and lifetime compatibility with Analyzer. It never loads or invokes
consumer code. Contract generation and consumer-owned factories are validated
before the generation transaction commits.

## Generated surface

`dartitect wiring sync` emits concrete types instead of capability-slot generic
lists:

- `ApplicationGraph` opens every application context exactly once;
- `SessionGraph` owns one session generation and disposes only after callers
  release its feature/routes;
- `<Feature>Infrastructure` contains only the selected contexts;
- `<Feature>Runtime` owns the exact repository, ports, policies, dataset,
  command, sync, and diagnostics closure selected by the profile; and
- `<Feature>FeatureHost` creates the runtime and ViewModel, publishes
  loading/failure/ready states, rejects late publication, and closes the
  ViewModel before the feature graph.

`DartitectAssemblyBinding`, `OwnedGraph`, and `BootstrapCoordinator` remain
available for advanced composition and generated code. They are not the normal
consumer-facing route.

## Feature and contract declarations

Each feature declares its typed `factorySource`, `localAuthority`
(`generated_pull` or `custom`), and exact OpenAPI operations. A contract names
one local spec, one generated output below `lib/` ending in
`.dartitect.g.dart`, and one Dio transport context. Only selected operations
enter a feature runtime as narrow `<OperationId>Operation` values over
`DioJsonClient`.

The application still owns status semantics, authentication policy, retry,
idempotency, domain models, DTO↔domain mappings, schemas, and migrations.

```json
{
  "configVersion": 3,
  "profile": "native_strict",
  "layers": {
    "domain": ["**/domain/**"],
    "application": ["**/application/**"],
    "data": ["**/data/**"],
    "infrastructure": ["**/infrastructure/**"],
    "presentation": ["**/presentation/**"]
  },
  "compositionRoots": ["lib/main.dart", "test/**", "**/composition/**"],
  "generatedInfrastructure": ["**/infrastructure/**/*.g.dart"],
  "generatedSuffixes": [".g.dart", ".dartitect.g.dart"],
  "suppressions": [],
  "targets": {"platforms": ["android", "web"]},
  "storageContexts": {
    "primary": {
      "provider": "drift",
      "mode": "durable",
      "scope": "application",
      "factorySource": {
        "source": "lib/composition/context_factories.dart",
        "declaration": "PrimaryStorageFactory"
      },
      "targets": ["android", "web"]
    }
  },
  "transports": {
    "api": {
      "provider": "dio",
      "scope": "application",
      "factorySource": {
        "source": "lib/composition/context_factories.dart",
        "declaration": "ApiTransportFactory"
      },
      "targets": ["android", "web"]
    }
  },
  "contracts": {
    "tasks_api": {
      "spec": "contracts/tasks.json",
      "output": "lib/contracts/tasks.contracts.dartitect.g.dart",
      "transport": "api"
    }
  },
  "observability": {"provider": "developer"},
  "scheduler": {"provider": "none"},
  "features": {
    "declarations": {
      "tasks": {
        "profile": "cache",
        "scope": "application",
        "factorySource": {
          "source": "lib/features/tasks/composition/tasks_factory.dart",
          "declaration": "TasksFactory"
        },
        "localAuthority": "generated_pull",
        "storageContext": "primary",
        "dataset": {
          "dataset": "tasks",
          "partition": "account_partition",
          "codec": "tasks_v1",
          "retention": "P30D",
          "transactionBoundary": "tasks_transaction"
        },
        "transport": "api",
        "targets": ["android", "web"],
        "pagination": "cursor",
        "diagnostics": "basic",
        "headlessTargets": [],
        "capabilities": [],
        "operations": [
          {"contract": "tasks_api", "operationId": "getTasks"}
        ]
      }
    }
  },
  "extensionSources": []
}
```

Config v2 remains documented only as the input contract for the transactional
[migration chain](config-v2.md).
