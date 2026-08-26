# Security policy

[Português (Brasil)](SECURITY.pt-BR.md)

## Supported versions

Security fixes target the current lockstep development/stable cohort. Older
prereleases may require upgrading first.

## Report a vulnerability

Do not open a public issue. Use the repository's GitHub **Security → Advisories
→ Report a vulnerability** flow. Include affected package/version, impact,
minimal reproduction, platform, and suggested mitigation. Do not include live
credentials, production data, DSNs, tokens, or customer identity.

Maintainers will acknowledge the report, coordinate validation/remediation, and
agree on disclosure. No response-time or bounty guarantee is made.

## Security boundaries

Dartitect does not own consumer credentials or provider configuration. MCP is
local STDIO, root-restricted, read-only by default, and exposes no arbitrary
shell/file access. Treat opt-in writes and provider adapters as privileged local
operations and review every dependency update.
