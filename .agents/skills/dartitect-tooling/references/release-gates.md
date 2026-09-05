# Release gates

Run formatting, analysis, public API snapshots, package/example tests,
generated-consumer matrices, public documentation/link checks, skills coverage,
MCP catalog freshness, CI/security policy, license/SBOM/advisory checks, native
fixtures, clean package archives, and exact-tag Git-consumption canaries in
proportion to the change and as required by the repository workflow.

Pin external Actions by full commit SHA. OSV exceptions are exact advisory IDs
with justification, analysis link, and short expiry; package-wide ignores and
PackageOverrides are forbidden. Distribution is GitHub-only. Distinguish the
workspace cohort/channel from the latest distributed stable cohort and whether
a derivable candidate tag is materialized. Candidate validation uses clean
archives and a local disposable-tag canary; it never authorizes a remote tag,
workflow run, GitHub Release, publication, or promotion. Release rejects
prerelease cohorts before external writes. Platform-specific evidence must run
on its supported host, and builds must leave tracked files unchanged.

For documentation and skill changes, require the documentation classification,
link/include, changelog-cohort, skill-reference, managed snapshot/hash, and MCP
catalog gates. Normal config accepts v3 only; v1/v2 are transactional fleet
migration inputs. `sdkVersion` follows the workspace cohort; public consumption
continues to use the recorded materialized distributed stable cohort. A newer
prepared stable cohort keeps `tagMaterialized` false. Release assets use the
prepared workspace version and record the prior distribution; the immutable
GitHub Release and attestation establish actual publication.
