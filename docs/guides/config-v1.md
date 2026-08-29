# Stable config v1

## Contract

`dartitect.json` accepts exactly `configVersion: 1` and the sole architecture
profile `native_strict`. Unknown fields fail with a JSON Pointer. Extension
data is accepted and round-tripped only under `extensions.<namespace>`; never
put credentials there.

Provider identifiers are closed:

- persistence: `none`, `memory`, `drift`, `objectbox`, or `custom:<slug>`;
- transport: `dio` or `custom:<slug>`;
- scheduler: `none`, `workmanager`, or `custom:<slug>`.

Platforms are Android, iOS, macOS, Windows, Linux, and web. ObjectBox on web,
missing required persistence, unsupported headless combinations, and other
unimplemented provider/profile matrices fail validation.

## Feature declaration

Each feature declares one shared `FeatureProfile`, an application/session
scope, native/web persistence, transport, pagination, diagnostics, a complete
headless platform map, and explicit capabilities:

```json
{
  "configVersion": 1,
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
  "features": {
    "declarations": {
      "orders": {
        "profile": "offline-full",
        "scope": "session",
        "persistence": {"native": "drift", "web": "drift"},
        "transport": "dio",
        "pagination": "cursor",
        "diagnostics": "full",
        "headless": {
          "android": true, "ios": true, "macos": true,
          "windows": false, "linux": true, "web": true
        },
        "capabilities": ["credentials", "attachments", "forms", "queries"]
      }
    }
  },
  "platforms": ["android", "ios", "macos", "windows", "linux", "web"],
  "scheduler": "workmanager",
  "extensions": {"example.team": {"reviewed": true}}
}
```

`online`, `cache`, `replica`, and `offline-full` are behavior profiles only.
There are no blueprint aliases or architecture coexistence controls.

## Commands and migration

```console
dartitect init --dry-run
dartitect scan --no-baseline
dartitect doctor
dartitect verify --root .
dartitect wiring sync --dry-run --json
```

The public config API does not accept RC5 aliases. Only
`dartitect fleet upgrade ... --to=1.0.0-rc.6 --apply` performs the exact,
journaled RC5-to-RC6 conversion.

## Inclusion gate

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

A capability enters Dartitect only when all three answers are yes; otherwise
it remains in `softgran_*`, `agrox_*`, or the application.
