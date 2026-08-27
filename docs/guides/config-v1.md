# Stable config v1

[Português (Brasil)](config-v1.pt-BR.md)

## Contract

`dartitect.json` accepts exactly `configVersion: 1` with the
`native_strict` profile. It declares named layer globs, composition roots,
generated infrastructure, reviewed suppressions, and the five generated-once
blueprints. It can also replace the reviewed generated suffix list. The CLI
scanner and analyzer plugin share the `DT1001` through
`DT1015` policy definitions.

Experimental configuration versions are intentionally incompatible. There is
no upgrade command or migration path: recreate the file with `dartitect init`,
then review it before replacing an older local experiment.

## Create and validate

```console
dartitect init --dry-run
dartitect init
dartitect scan --no-baseline
dartitect doctor
```

The parser rejects missing or incorrectly typed fields and preserves unknown
v1 extension keys without interpreting them. It does not store credentials.
Layer globs and composition roots are repository-relative. A generated source
is classified either by an explicit infrastructure glob or by both a standard
generated-code header and a configured suffix. Invalid analyzer configuration
is reported explicitly; defaults never hide the invalid state.

## Suppress deliberately

Each suppression needs a diagnostic code, path glob, reason, owner, and either
an expiry date or a permanent justification. Prefer fixing a boundary; use a
suppression only for reviewed debt or an intentional exception. Expired or
incomplete entries do not suppress findings.
