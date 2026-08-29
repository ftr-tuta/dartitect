# Stable config v2

## Contract

`dartitect.json` accepts exactly `configVersion: 2` and the sole architecture
profile `native_strict`. Unknown fields fail with an exact JSON Pointer. The
schema has distinct blocks for application `targets`, `storageContexts`,
`transports`, `observability`, `scheduler`, `features`, and confined
`extensionSources`; credentials and opaque plugin data are never configuration.

Every application target is explicit. A feature inherits those targets when it
omits `targets`, or restricts them to a subset. Storage, transport, scheduler,
and observability bindings declare the exact targets they support.

## Feature profiles

| Profile | Transport | Persistence and sync |
| --- | --- | --- |
| `local` | prohibited | optional explicit storage; no sync/outbox |
| `online` | required | persistence prohibited |
| `cache` | required | named storage context; local-authority refresh |
| `replica` | required | named durable context and dataset sync |
| `offline-full` | required | named durable context, dataset sync, optional outbox/headless |

No productive provider is implicit. `memory` must be named with `mode: memory`,
is for development/tests only, and fails release doctor. Built-in providers are
ordinary typed config blocks, never extensions.

`dartitect wiring sync` compiles each declaration into a capability-closed
`<Feature>FeatureAssembly`. Its generic bindings are non-null and present only
when selected: storage, transport, local authority, pagination, outbox, sync,
headless job, diagnostics, and opt-in workflows. The generated application
graph uses the consumer's exact session/failure types and concrete built-in
scheduler/observability types. Project-local providers become explicit typed
factory inputs. No generated graph contains `Object`, provider-name fields, or
nullable capability slots.

Composition supplies every generated slot with a
`DartitectAssemblyBinding.borrowed` or `DartitectAssemblyBinding.owned` value.
Owned values are registered while a `ResourceTransaction` is still open,
rollback atomically when construction fails, and are released in reverse order
by the generated `OwnedGraph`. Consumer code does not provide a catch-all
disposal callback.

Scaffolds inject consumer repositories into composition. Deterministic memory
and fake implementations are generated only below `test/support`; an
explicitly requested `--example` may include example-only data in its app.

```json
{
  "configVersion": 2,
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
      "targets": ["android", "web"]
    }
  },
  "transports": {
    "api": {"provider": "dio", "targets": ["android", "web"]}
  },
  "observability": {"provider": "developer"},
  "scheduler": {"provider": "none"},
  "features": {
    "declarations": {
      "tasks": {
        "profile": "cache",
        "scope": "application",
        "storageContext": "primary",
        "transport": "api",
        "pagination": "cursor",
        "diagnostics": "basic",
        "headlessTargets": [],
        "capabilities": []
      }
    }
  },
  "extensionSources": ["lib/infrastructure/project_extensions.dart"]
}
```

`dartitect create app <name> --targets=android,web` creates an empty shell and
only the requested Flutter platforms. `--example=tasks` is explicit opt-in.
Config v1 is accepted only by the versioned Dartitect-project upgrade; it is
not accepted by normal config loading and is not an application conversion.
Extension declarations and their confinement rules are covered in
[typed project-local extensions](project-local-extensions.md).
