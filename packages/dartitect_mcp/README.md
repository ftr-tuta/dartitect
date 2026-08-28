# dartitect_mcp

[Português (Brasil)](README.pt-BR.md)

## Purpose

Local MCP access to Dartitect inspection, diagnostics, conformance, reviewed
previews, and generated public documentation on the lockstep `1.0.0-rc.4`
candidate line.

## When to use it

Use it with Codex or another local MCP client when an agent needs bounded,
typed project context. Use the CLI directly in scripts. This package is not a
remote service, ChatGPT web plugin, application debugger, or shell bridge.

## When not to use it

Do not use it for shell/CI automation, arbitrary file access, HTTP/OAuth,
remote application access, or unattended writes. Do not enable writes unless a
reviewed local mutation is intended.

## Recommended combinations

Combine with `dartitect_cli` as the shared project service, while keeping scripts
on the CLI. Use the managed `$dartitect-mcp` skill for MCP work and
`$dartitect-tooling` for shell/CI tooling. See the
[ecosystem selection guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/ecosystem-selection.md)
and [implementation recipes](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/implementation-recipes.md).

## Install

This candidate is not published on pub.dev. Declare
`dartitect_mcp: 1.0.0-rc.4` under `dev_dependencies`, apply the overrides from
the [Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md),
then run `dart run dartitect_mcp:dartitect_mcp --root .`.

## Minimal example

```dart
final server = DartitectMcpServer(
  stdioChannel(input: stdin, output: stdout),
  policy: DartitectMcpPolicy(allowedRoots: [Directory.current]),
);
await server.done;
```

## Public API tour

- `DartitectMcpServer` implements tools/resources over an injected MCP channel.
- `DartitectMcpPolicy` canonicalizes allowed roots, keeps writes off by default,
  limits results/time, and injects clock/IDs for deterministic tests.
- `DartitectMcpException` represents sanitized policy/request failures.

Tools: `dartitect_inspect_project`, `dartitect_scan_architecture`,
`dartitect_doctor_project`, `dartitect_explain_finding`,
`dartitect_audit_conformance`, three `dartitect_preview_*` tools, and
`dartitect_apply_change`. There is no `create`, arbitrary file read, process
argument, or shell tool.

Resources: `dartitect://packages`, package/diagnostic/guide templates, and
`dartitect://config/v1`. The catalog is generated from package metadata, public
docs—including ecosystem selection and implementation recipes—config,
diagnostics, and the API snapshot; CI rejects staleness.

## Ownership

The host owns stdin/stdout and server lifetime. The policy owns only canonical
root authorization. Project providers, credentials, and running applications
remain outside MCP.

## Limitations

`dart_mcp` is pinned to `0.5.2`. This release supports local STDIO only; no
Streamable HTTP, OAuth/authorization, UI, remote plugin, or application access.
Stdout is JSON-RPC only; diagnostics go to stderr.

## Extending

Add a typed operation to `DartitectProjectService`, then a bounded MCP mapping.
Never subprocess the CLI or parse its text. Preserve relative/sanitized output,
closed schemas, explicit annotations, and server-wide instructions.

## Testing

Run `dart test`. The suite uses a real `dart_mcp` client in-process and as a
STDIO child process; it requires no model, network, token, or provider account.

## Codex setup

```console
codex mcp add dartitect -- dart run dartitect_mcp:dartitect_mcp --root .
```

```toml
[mcp_servers.dartitect]
command = "dart"
args = ["run", "dartitect_mcp:dartitect_mcp", "--root", "."]
default_tools_approval_mode = "writes"
startup_timeout_sec = 20
tool_timeout_sec = 120
```

For writes, add `--allow-writes`. Application still requires a reviewed preview,
unexpired single-use plan, `confirmed: true`, client approval, state revalidation,
serialization, and a filesystem lock. Read-only setup is recommended.

## Generic MCP clients

Configure an MCP 2025-06-18-or-newer compatible STDIO client with command
`dart` and arguments `run dartitect_mcp:dartitect_mcp --root .`. Do not add
secrets or environment credentials. Mark `dartitect_apply_change` for approval.

## Links

See the [MCP guide](https://github.com/ftr-tuta/dartitect/blob/main/docs/guides/mcp.md),
[security policy](https://github.com/ftr-tuta/dartitect/blob/main/SECURITY.md), and [issue tracker](https://github.com/ftr-tuta/dartitect/issues).
