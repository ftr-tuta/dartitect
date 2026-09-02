# Local MCP server

## Scope

The distributed `dartitect_mcp 1.0.0` is local and STDIO-only. The source
workspace is the untagged `1.1.0-rc.2` candidate and retains the same transport
boundary. It uses
`dart_mcp 0.5.2`. Streamable HTTP, OAuth/authorization, remote ChatGPT plugins,
MCP UI, arbitrary shell/files, scaffolding `create`, and access to running
applications are out of scope. The bounded `dartitect_preview_create_feature`
tool is the only create workflow exposed.

## Read-only setup

Declare the MCP package directly under `dev_dependencies`; its transitive
Dartitect packages resolve from the same tag without overrides:

```yaml
dev_dependencies:
  dartitect_mcp:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      path: packages/dartitect_mcp
      tag_pattern: 'v{{version}}'
    version: 1.0.0
```

Then run `dart run dartitect_mcp:dartitect_mcp --root .`. See the
[Git release consumption guide](git-release-consumption.md).

Stdout is reserved for newline-delimited JSON-RPC. Internal diagnostics use
stderr. The process accepts repeated `--root` arguments; all must already exist.

## Codex

For Flutter SDK and DevTools integration, install Flutter's official plugin as
an explicit user action and begin a new session:

```console
codex plugin add dart-flutter@dart-flutter
dartitect codex doctor --flutter
dartitect codex setup --flutter --dry-run
```

The plugin supplies its own `dart mcp-server` and six official Flutter skills.
Dartitect discovers those capabilities at runtime and never invents a missing
tool. Setup is offline and synchronizes only catalog-managed Dartitect skills;
it never installs the plugin, calls `npx`, modifies global Codex configuration,
or creates `.vscode/mcp.json`.

```console
codex mcp add dartitect -- dart run dartitect_mcp:dartitect_mcp --root .
codex mcp list
```

Or save project-scoped `.codex/config.toml` in a trusted project:

```toml
[mcp_servers.dartitect]
command = "dart"
args = ["run", "dartitect_mcp:dartitect_mcp", "--root", "."]
default_tools_approval_mode = "writes"
startup_timeout_sec = 20
tool_timeout_sec = 120
```

`writes` prompts for a tool not marked read-only. Inspection and preview tools
are annotated read-only; `dartitect_apply_change` is mutable/destructive. Server
instructions summarize the workflow and restrictions for the client.

## Generic clients

Configure a local MCP client supporting STDIO and protocol 2025-06-18 or later:

- command: `dart`;
- arguments: `run`, `dartitect_mcp:dartitect_mcp`, `--root`, `.`;
- environment: no token, DSN, password, or credential;
- approval: require user approval for `dartitect_apply_change`.

The server returns `structuredContent` and a compatible textual JSON content
block for every tool result.

## Read tools and resources

Inspect, scan, verify, doctor, finding explanation, conformance auditing, and
all previews are read-only. Scan and verify accept bounded `offset`/`limit`;
verify combines architecture, modeling freshness, native-strict ecosystem, and
provider status. Deep doctor is opt-in and time-bounded.

`dartitect_audit_conformance` audits a project created with Dartitect after
development or a supported SDK upgrade. It uses the strict scan as evidence
and never returns an application-conversion plan.

Stable `1.0.0` provides the confined, closed-schema tools and config-v3/fleet
metadata:

- `dartitect_preview_create_feature`;
- `dartitect_preview_wiring_sync`;
- `dartitect_explain_feature_graph`;
- `dartitect_list_consumer_owned_seams`;
- `dartitect_verify_primary_constructor_policy`.

They paginate bounded results and never return arbitrary consumer file bodies.

Resources are generated from maintained project sources:

- `dartitect://packages` and `dartitect://packages/{name}`;
- `dartitect://diagnostics/{code}`;
- `dartitect://guides/{slug}`;
- `dartitect://config/v3`.

There is no free-form file resource.
The candidate catalog includes the privacy-bypass diagnostics `DT1050` through
`DT1054` and routes destination-policy questions to the observability skill.
MCP still cannot read runtime payloads or invoke the DevTools privacy RPC.
The guide catalog includes the ecosystem selection matrix and implementation
recipes. Use the managed `$dartitect-mcp` skill for MCP configuration and
protocol work; use `$dartitect-tooling` and the CLI directly for scripts or CI.

## Opt-in writes

Add `--allow-writes` to the server arguments only when reviewed local writes
are required. This flag alone is insufficient.

Model sync and primary-constructor quick fixes use the same preview/apply gate
as init, feature creation, wiring sync, and managed skill synchronization.
Preview payloads contain
operations and semantic manifests, never consumer source bodies.

Apply requires all of:

1. server write opt-in;
2. a prior read-only preview;
3. an opaque plan ID that is unexpired and unused;
4. `confirmed: true` after the user reviews operations and preview;
5. client MCP approval;
6. complete state/operation revalidation;
7. in-process serialization and an exclusive filesystem lock.

Plans expire after ten minutes by default and are single-use even after a failed
attempt. Expiry, replay, concurrency, stale state, lock, permission, and I/O
failures return structured errors without disclosing absolute paths.

Before exposing another MCP operation, ask:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be yes; non-neutral reusable infrastructure belongs in a
typed project-local extension and business actions remain in the application.

## Root and data security

Tool paths are relative. Absolute paths, traversal, empty segments, unauthorized
root names, missing projects, and symlinks escaping a configured canonical root
are rejected. The filesystem root itself cannot be authorized. The server
never returns absolute paths, credentials, bodies,
headers, DSNs, environment values, or unsanitized internal errors.

## Troubleshooting

- `writes_disabled`: restart with `--allow-writes` only if mutation is intended.
- `plan_expired`, `plan_replayed`, or `stale_plan`: create and review a new preview.
- `change_locked`: wait for the other local change, then create a new preview.
- `root_*` or path errors: use a configured root name and relative project path.
- startup timeout: run the command directly and inspect stderr; do not add
  secrets to debug configuration.

## References

Transport and protocol capabilities follow
[`dart_mcp 0.5.2`](https://pub.dev/packages/dart_mcp/versions/0.5.2). Codex
registration, TOML fields, instructions, and approval behavior follow the
[official OpenAI MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
