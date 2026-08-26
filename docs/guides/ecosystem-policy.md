# Ecosystem dependency policy

[Português (Brasil)](ecosystem-policy.pt-BR.md)

## Neutral global ledger

`tool/ecosystem_policy.json` is the versioned Native Strict authority. It
contains project-wide decisions only; application paths, exceptions, metrics,
and adoption choices are forbidden there. The dispositions are:

- `approved`: reviewed for its documented boundary;
- `advisory_alternative`: Dartitect offers a bounded alternative, but use of
  the external package is informational by default;
- `reviewed_exception`: use requires a consumer-owned scoped overlay;
- `prohibited_native_strict`: a universal architecture, container, service
  locator, private-import, or security prohibition;
- `unreviewed`: absent from the global ledger.

Unknown packages remain advisory in a consumer audit. They block Dartitect's
own release audit until the exact resolved package appears in the reviewed
workspace inventory.

## Consumer overlay

Applications version their choices in `.dartitect/ecosystem-policy.json`:

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "package": "pdf",
      "decision": "approved",
      "owner": "document platform team",
      "reason": "isolated document-rendering adapter",
      "expiresOn": "2026-11-22",
      "paths": ["lib/infrastructure/documents/**"],
      "directOwners": ["document_adapter"]
    }
  ]
}
```

An entry requires a package, owner, reason, expiry, and at least one non-global
path. `directOwners` is optional, but when present every route to a transitive
package must start at one of those owners. An overlay may add approvals,
advisories, and reviewed exceptions. It cannot disable a universal prohibition,
authorize publication, move provider types across layers, or contain secrets.

## Commands and parity

`dartitect dependencies audit` reports every direct owner and one deterministic
resolved route per owner. `dartitect dependencies explain <package>` prints the
neutral global decision. Use `--json` for automation.

DT1017 identifies a universal or contextual conflict and DT1018 an invalid,
missing, expired, or incomplete review. Alternatives such as Freezed, Retrofit,
UUID packages, gallery plugins, and native splash tooling do not produce an
error merely because Dartitect has an equivalent bounded capability.
`sentry_dio` becomes an error only when equivalent Dartitect Dio
instrumentation is also resolved.

The CLI dependency command, scanner, and Analyzer plugin use the same decisions
and overlay schema. The Analyzer embeds a checked generated snapshot; the
ecosystem policy gate rejects stale decisions, alternatives, conflicts, or
architecture prohibitions.

## Review workflow

Update the neutral ledger only for project-wide facts. Put application choices
in its overlay, then run dependency audit, scanner, Analyzer tests, source and
license review, advisories, SBOM, and the snapshot freshness gate. Never use a
global ignore or dependency override to conceal solver or policy failures.
