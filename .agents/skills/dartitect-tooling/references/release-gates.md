# Release gates

Run formatting, analysis, public API snapshots, package/example tests,
generated-consumer matrices, public documentation/link checks, skills coverage,
MCP catalog freshness, CI/security policy, license/SBOM/advisory checks, native
fixtures, clean package archives, and exact-tag Git-consumption canaries in
proportion to the change and as required by the repository workflow.

Pin external Actions by full commit SHA. OSV exceptions are exact advisory IDs
with justification, analysis link, and short expiry; package-wide ignores and
PackageOverrides are forbidden. Distribution is GitHub-only; validation uses
clean archives and exact-tag Git canaries, and no registry workflow exists. A
source-validation preview never authorizes a tag or GitHub Release. Platform-specific evidence
must run on its supported host, and builds must leave tracked files unchanged.

For documentation and skill changes, require the documentation classification,
link/include, changelog-cohort, skill-reference, managed snapshot/hash, and MCP
catalog gates. Normal config accepts v3 only; v1/v2 are transactional fleet
migration inputs. Keep `sdkVersion` at the released cohort until a separately
authorized release changes it.
