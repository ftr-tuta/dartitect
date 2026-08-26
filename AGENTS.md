# Dartitect workspace

Use the focused skills under `.agents/skills` and preserve explicit ownership
boundaries. Invoke `repository-contribution` for every tracked change and for
branch, commit, pull request, check, or merge work. It is repository-specific
and is not managed by `dartitect codex sync`.

Create repository commits only as `ftr <ftr@tuta.com>`. Keep this identity and
`user.useConfigOnly=true` in the repository-local Git config; do not change the
global Git identity for Dartitect work.

Normal work must use a short-lived branch and pull request. Never bypass the
`main` ruleset. Direct changes to `main` are limited to an explicitly authorized
break-glass recovery that follows the backup, lease, rollback, and immediate
protection-restoration procedure in the contribution guide.
