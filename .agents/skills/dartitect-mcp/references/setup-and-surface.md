# Setup and surface

Run `dart run dartitect_mcp:dartitect_mcp --root .` and register that local STDIO
command in the MCP client. Multiple roots must already exist and are addressed
by configured names. Do not put credentials in command arguments or environment.

The closed read surface provides inspect, bounded scan, doctor, finding
explanation, conformance auditing, and change previews. Generated resources expose
package metadata, diagnostics, canonical English guides, and credential-free
config v1. There is no free-form file resource. Results include structured
content plus compatible JSON text. Read tools/previews are annotated read-only;
only apply is mutable/destructive.
