# Stable config v1

## Contract

`dartitect.json` accepts exactly `configVersion: 1` with the
`native_strict` profile. It declares named layer globs, composition roots,
generated infrastructure, reviewed suppressions, the five generated-once
blueprints, and optional `modeling` and `ecosystem` blocks. It can also replace
the reviewed generated suffix list. The CLI scanner and analyzer plugin share
the stable policy definitions.

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

## Additive RC4 blocks

Omitting `modeling` preserves the behavior of existing config-v1 consumers.
When present, it selects one adoption preset and explicit untrusted JSON
limits. `ecosystem` records incremental adoption and treats an installed but
non-leaking overlapping runtime as a warning:

```json
{
  "modeling": {
    "preset": "interop_existing_project",
    "jsonLimits": {
      "maxDepth": 64,
      "maxCollectionItems": 10000,
      "maxNodes": 100000
    }
  },
  "ecosystem": {
    "adoption": "incremental",
    "installedOverlap": "warning"
  }
}
```

This is a fragment to merge into a complete config-v1 document. Unknown v1
extension keys remain round-trippable, but known block fields and enum values
are validated fail-closed.

## Presets do not enable annotations

`minimal` suggests value semantics only. `recommended_complete` suggests
value, JSON, projection, and mapper capabilities for a new model.
`interop_existing_project` permits consumer-owned generators to coexist when
they own different outputs. These are adoption defaults only: JSON,
projections, and mappers still require their independent annotations. No preset
authorizes provider leakage, duplicate ownership, dual-write, or an inferred
conversion.

Run `dartitect verify --json` after changing either block. Use
`dartitect verify --sarif` for code-scanning ingestion; both forms are strictly
read-only.

## Suppress deliberately

Each suppression needs a diagnostic code, path glob, reason, owner, and either
an expiry date or a permanent justification. Prefer fixing a boundary; use a
suppression only for reviewed debt or an intentional exception. Expired or
incomplete entries do not suppress findings.
