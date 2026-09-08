---
name: repository-contribution
description: Safely deliver versioned Dartitect changes through short-lived branches, canonical commits, proportional validation, pull requests, required checks, and squash merges. Use for any task that edits tracked content or operates Git branches, commits, PRs, checks, repository settings, or merges in this repository.
---

# Repository Contribution

Read the applicable `AGENTS.md`, `CONTRIBUTING.md`, and
[`docs/guides/repository-contribution.md`](../../../docs/guides/repository-contribution.md)
before changing tracked content or remote GitHub state. For documentation or
skills, also read the task index in [`docs/README.md`](../../../docs/README.md)
and preserve the classification in `tool/documentation_contract.json`.
Preserve unrelated work and keep authorization boundaries explicit.

## Start safely

Inspect the working tree, current branch, remote, and local Git identity. Keep
`ftr <ftr@tuta.com>` and `user.useConfigOnly=true` in repository-local config.
Fetch `origin`, then create a short-lived `feat/`, `fix/`, `ci/`, `docs/`,
`chore/`, or `release/` branch from `origin/main`. Never perform normal work on
`main`.

## Implement and validate

Keep the diff focused and use Conventional Commits. Run checks proportional to
risk plus every explicitly requested gate. When a Flutter plugin changes,
regenerate and commit affected native project/workspace integration on the
relevant hosts; iOS/macOS builds must leave the tracked tree unchanged.

Before committing, review the complete diff, authorship, generated artifacts,
and working tree. Do not publish packages or create tags unless separately
authorized.

Treat the lockstep workspace cohort, release channel, latest distributed stable
cohort, derivable candidate tag, and materialized-tag state as distinct facts.
An untagged prerelease workspace does not authorize a remote tag, `Release`
workflow run, GitHub Release, publication, or stable promotion. Candidate
canaries may use only a local disposable tag, and release workflows must reject
prerelease cohorts before external writes.

For documentation and skill work, update
`packages/dartitect_cli/lib/src/codex/skill_catalog.dart`, regenerate rather than
hand-edit the catalog-managed skills, and update the local skill directly. Keep
all 25 changelogs on the same non-empty `Unreleased` entry and keep `1.1.0` as
the first numbered version. The current source cohort may be newer than the
public version, including a prepared stable version with an unmaterialized
tag. Preserve the recorded distribution during preparation; release assets
resolve the prepared cohort and the immutable GitHub Release records actual
publication and provenance. Run documentation classification/link checks,
skill coverage/reference/snapshot checks, the package release contract, managed
skill validation, and generated-catalog freshness before committing.

## Deliver through a pull request

Push only the topic branch and complete the PR template with outcome, ownership,
compatibility, platform impact, evidence, and remaining validation. Keep builds
on GitHub's merge candidate; for authorship, audit the PR head rather than the
synthetic merge commit. Fix failures on the same branch. Never bypass or weaken
the `main` ruleset.

Before enabling auto-merge, confirm GitHub web operations use `ftr@tuta.com` and
email privacy will not substitute a `noreply` address. Require all configured CI
and Security checks, resolved conversations, and an up-to-date branch. Squash
using the PR title, then verify `main`, automatic branch deletion, canonical
authorship, and the clean-clone/bundle evidence required by the guide.

## Break glass

Direct `main` updates are allowed only for an explicitly authorized recovery.
Immediately before remote mutation, re-confirm the exact target and expected
remote SHA. Preserve a verified bundle and repository/ruleset snapshots, use an
exact lease and only the single `main` ref, prepare rollback to the captured SHA,
and restore protections immediately even on failure. Never use `git push
--mirror`. This exception never authorizes bypass for ordinary contribution
work.
