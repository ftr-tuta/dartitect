# Dartitect workspace

Use the focused skills under `.agents/skills` and preserve explicit ownership
boundaries. Invoke `repository-contribution` for every tracked change and for
branch, commit, pull request, check, or merge work. It is repository-specific
and is not managed by `dartitect codex sync`.

The canonical source for the twelve distributed skills is
`packages/dartitect_cli/lib/src/codex/skill_catalog.dart`. Never edit their
managed snapshots directly; regenerate them with
`dartitect codex sync --overwrite-managed` and require a twelve-`NO-OP` dry run
before delivery. Update the local `repository-contribution` skill directly.

Use `docs/README.md` as the public documentation entrypoint and
`tool/documentation_contract.json` as the current/migration/historical/generated
classification. Keep public guidance in English, do not modernize historical
ADRs or handoffs, and remove duplicate guide formats. Every package changelog
starts with `# Changelog`, a uniform `## Unreleased` section, and then `1.0.0`
as its first numbered version.

Documentation or skill changes must pass `check_public_docs`,
`check_skill_coverage`, `check_package_release_contract`, MCP catalog freshness,
managed-skill validation, and every additional gate named by the task.

Create repository commits only as `ftr <ftr@tuta.com>`. Keep this identity and
`user.useConfigOnly=true` in the repository-local Git config; do not change the
global Git identity for Dartitect work.

Normal work must use a short-lived branch and pull request. Never bypass the
`main` ruleset. Direct changes to `main` are limited to an explicitly authorized
break-glass recovery that follows the backup, lease, rollback, and immediate
protection-restoration procedure in the contribution guide.
