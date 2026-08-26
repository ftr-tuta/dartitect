---
name: dartitect-mcp
description: Configure, use, or extend the local Dartitect MCP server, bounded tools/resources, reviewed previews, and opt-in writes. Use for MCP-specific workflows; exclude shell automation, remote services, application access, and CI scripting.
---

# Use the local Dartitect MCP

## When to use

Use this skill when a local MCP client needs typed Dartitect inspection,
diagnostics, adoption context, public guide resources, reviewed previews, or the
server's guarded write flow.

## When not to use

Use `$dartitect-tooling` and the CLI directly for shell scripts, CI, generators,
release gates, or native setup. The MCP is not a remote service, HTTP/OAuth
endpoint, ChatGPT web plugin, shell bridge, arbitrary file reader, or debugger
for a running application.

## Invariants

The server is local STDIO and read-only by default. Stdout is JSON-RPC only.
Roots are preconfigured and canonical; tool paths are relative and confined.
Never expose secrets, environment, arbitrary files, raw internal errors, or
unbounded results. Tool/resource schemas stay closed and generated resources
come from maintained repository sources.

## Workflow

Configure a trusted root, use inspect/scan/doctor/explain/adoption/resource
reads first, then request a preview. Enable server writes only for an intended,
reviewed local change and retain client approval.

Read [references/setup-and-surface.md](references/setup-and-surface.md) for
configuration/tools/resources and [references/reviewed-writes.md](references/reviewed-writes.md)
for mutation security.

## Validate

Test real-process startup/shutdown, stdout purity, structured plus text output,
bounded pagination, root/path/symlink rejection, resource catalog freshness,
write-disabled behavior, preview/apply annotations, expiry, replay, stale state,
confirmation, locking, revalidation, and sanitized failures.
