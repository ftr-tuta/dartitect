---
name: dartitect-tooling
description: Operate or extend the Dartitect CLI, config, verify, scan, doctor, fleet, lints, semantic compiler, generators, native setup, and release gates. Use for shell/CI architecture tooling; MCP configuration and protocol work belongs to the MCP skill.
---

# Operate Dartitect tooling

## When to use

Use this skill for CLI commands/services, stable config v1, verify/scanner/doctor policy,
baselines, analyzer diagnostics, generators, Codex sync, native fixture setup,
or repository release gates.

## When not to use

Use `$dartitect-mcp` for local MCP tools, resources, protocol, previews, or
opt-in MCP writes. Use runtime skills for application behavior.

## Invariants

Inspection and `dartitect verify` are strictly read-only. Mutations preview by default or provide explicit
dry-run/apply separation. Reject experimental versions and preserve unknown v1
extension fields without interpreting them.
Baselines cover reviewed existing debt only. Generators stage, validate, refuse
conflicts, and recover transactionally. Codex sync replaces only valid
manifest-owned skills and preserves consumer-owned files/directories.
Every reviewed project change binds only its semantic inputs in a sorted
SHA-256 manifest. Partition generated ownership, reports, and journals by
`GenerationNamespace`. Acquire the cross-process project lock before
revalidation and hold it through commit, rollback, or recovery. Migrate RC3
ownership only when manifest metadata, recorded digest, and current bytes match.

## Workflow

Identify the command contract and exit codes, resolve roots by real path
segments, construct a deterministic preview, validate the complete staged
result, then commit atomically. Update tests, docs, diagnostics, catalogs, and
release gates that expose the behavior.

Read [references/cli-scan-and-lints.md](references/cli-scan-and-lints.md),
[references/generation-and-native.md](references/generation-and-native.md), or
[references/release-gates.md](references/release-gates.md) as applicable.

## Validate

Test idempotency, conflicts, stale state, interrupted recovery, path/symlink
confinement, permissions, CRLF, Unicode/spaces, unknown-key preservation, stable
JSON/exit codes, irrelevant-asset stability, real cross-process exclusion,
generated-consumer behavior, and unchanged tracked files after verification.

## Dartitect inclusion gate

Before adding a capability, answer:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be “yes”. Otherwise the capability belongs in
`softgran_*`, `agrox_*`, or the application, not in a Dartitect package.
