# Runtime, DevTools, and MCP

Discover Flutter tools at runtime from the official
`dart-flutter@dart-flutter` plugin and its `dart mcp-server`. Do not infer a
tool name or fabricate output. If the plugin, MCP server, a running target, or
a necessary tool is absent, record the exact missing evidence and continue
with the applicable static and test evidence.

Inspect finite layout constraints, widget/runtime errors, overflow, rebuild
scope, focus, scroll, interaction paths, first useful state, and cleanup.
Runtime evidence stays payload-free: record counts, statuses, tool identity,
and digests, not screen text, semantics, screenshots, or transcripts.

`dartitect codex doctor --flutter` is read-only and offline. Plugin installation
is a manual user action with `codex plugin add dart-flutter@dart-flutter`.
Dartitect setup manages only catalog assets and never creates or edits
`.vscode/mcp.json`.
