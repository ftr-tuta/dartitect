# Release gates

Run formatting, analysis, public API snapshots, package/example tests,
generated-consumer matrices, public documentation/link checks, skills coverage,
MCP catalog freshness, CI/security policy, license/SBOM/advisory checks, native
fixtures, and publish dry-runs in proportion to the change and as required by
the repository workflow.

Pin external Actions by full commit SHA. OSV exceptions are exact advisory IDs
with justification, analysis link, and short expiry; package-wide ignores and
PackageOverrides are forbidden. A dry-run never authorizes publishing or tags.
Platform-specific evidence must run on its supported host, and builds must
leave tracked files unchanged.
