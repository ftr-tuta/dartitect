# dartitect_mcp

## Purpose

A local MCP server exposing bounded Dartitect project inspection, diagnostics,
conformance, reviewed change previews/application, and a generated English
documentation catalog over STDIO.

## When to use

Use it with Codex or another local MCP client when an agent needs typed,
root-confined Dartitect project context. Keep scripts and CI on the CLI.

## When not to use

Do not use it as a remote service, ChatGPT web plugin, application debugger,
shell bridge, arbitrary file reader, HTTP/OAuth server, or unattended writer.
Do not enable writes unless a reviewed local mutation is intended.

## Platforms and entrypoints

- Run `dart run dartitect_mcp:dartitect_mcp --root .` on the Dart VM.
- Import `package:dartitect_mcp/dartitect_mcp.dart` to embed the server in a
  local STDIO host.

The current server is local STDIO only.

## Mental model and data flow

The host owns stdin/stdout and chooses allowed canonical roots.
`DartitectMcpPolicy` bounds roots, result size, time, and write permission.
`DartitectMcpServer` maps MCP tools to the typed `DartitectProjectService`; it
never shells out or parses CLI text. Resources come from generated package
metadata, diagnostics (including `DT1050` through `DT1054`), English guides,
config v3, and the reviewed API snapshot.

Writes are off by default. When enabled, a preview produces an opaque,
short-lived, single-use plan ID. Apply requires explicit confirmation and client
approval, then revalidates state under serialization and the project lock.

## Minimal workflow

```dart
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:dartitect_mcp/dartitect_mcp.dart';

Future<void> main() async {
  final server = DartitectMcpServer(
    stdioChannel(input: stdin, output: stdout),
    policy: DartitectMcpPolicy(
      allowedRoots: <Directory>[Directory.current],
    ),
  );
  await server.done;
}
```

## Public API tour

- `DartitectMcpServer` implements the local tools/resources over an injected MCP
  channel.
- `DartitectMcpPolicy` canonicalizes roots, defaults to read-only, bounds
  results/time, and accepts injectable clocks/IDs for deterministic tests.
- `DartitectMcpException` represents sanitized policy/request failures.

Tools cover inspect, scan, doctor, finding explanation, conformance audit,
change previews, and guarded apply. Resources cover packages, package details,
diagnostics, English guides, and config v3. There is no create, shell, process
argument, arbitrary file-read, or network tool.

When a scan request carries an MCP progress token, the server consumes
`ProjectScanner.scanEvents` and publishes only analyzed and total counts.
Progress never includes source, finding text, or paths, and timeout/disposal
fences late notifications. The terminal response keeps the existing bounded,
paginated finding contract.

## Ownership and lifecycle

The host owns the channel, process, server lifetime, project files, credentials,
and running applications. Policy owns authorization decisions only. Dispose the
server/channel before process shutdown. Project provider resources never enter
MCP.

## Failure, cancellation, and concurrency

Policy and request failures are sanitized and bounded. Tool deadlines cancel at
the project-service boundary where supported; filesystem work already committed
is governed by the transaction receipt. Apply is serialized, consumes one
unexpired plan exactly once, and revalidates the complete semantic state.

Stdout is JSON-RPC only; diagnostics go to stderr. Failed, expired, changed, or
replayed plans fail closed. A read-only setup cannot invoke writes even if a
client asks.

## Prohibited uses and limitations

- No remote transport, HTTP, OAuth, UI, application access, or credentials.
- No arbitrary shell/process arguments or arbitrary filesystem reads.
- No unattended write or apply without preview, `confirmed: true`, and client
  approval.
- No bypass of root confinement, state revalidation, serialization, or lock.
- No hand-edited generated catalog.

The Dartitect MCP contract is stable and pins the reviewed `dart_mcp` `0.5.2`
transport surface.

## Testing

Run `dart test`. The suite uses a real in-process and child-process MCP client
with no model, network, token, or provider account. Cover root confinement,
schemas, annotations, catalog freshness, result/time bounds, read-only denial,
preview/apply/expiry/replay, concurrent apply, sanitized errors, and clean STDIO.

## Related packages and guides

`dartitect_cli` supplies the typed project service and canonical managed skills.
Use the `dartitect-mcp` managed skill for agent workflows. Read
[MCP](../../docs/guides/mcp.md),
[getting started](../../docs/guides/getting-started.md), and
[model generation](../../docs/guides/model-generation.md). Progressive scan
semantics are documented in the
[incremental operations guide](../../docs/guides/incremental-operations.md).

Destination privacy questions route to the managed observability skill. MCP
does not read running telemetry payloads or expose the separate DevTools
privacy RPC.

## Availability

Dartitect `1.1.0` is distributed only by the annotated `v1.1.0` tag and
its immutable GitHub Release. Declare this package directly with the canonical
Git descriptor; its transitive Dartitect dependencies resolve from the same tag
without overrides. See the
[Git release consumption guide](../../docs/guides/git-release-consumption.md).
