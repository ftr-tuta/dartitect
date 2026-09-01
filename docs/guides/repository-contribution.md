# Repository contribution workflow

## Scope and invariants

Every normal tracked change reaches `main` through a pull request. Do not push
normal work directly to `main`, bypass its ruleset, weaken required checks, or
use an emergency procedure for convenience. Keep unrelated local changes intact.

Repository commits have the single canonical identity `ftr <ftr@tuta.com>` and
use Conventional Commits. The repository-local setting
`user.useConfigOnly=true` prevents an ambient global identity from leaking in.

## Start a short-lived branch

Begin from the current remote mainline:

```console
git fetch --prune origin
git switch -c <type>/<short-purpose> origin/main
git config --local user.name ftr
git config --local user.email ftr@tuta.com
git config --local user.useConfigOnly true
```

Use only `feat/`, `fix/`, `ci/`, `docs/`, `chore/`, or `release/`. Keep the name,
scope, and lifetime short. Check the working tree and applicable `AGENTS.md`
before editing.

## Implement and verify

Keep commits independently reviewable and write Conventional Commit subjects.
Choose checks in proportion to the affected boundary:

- documentation-only changes run formatting plus documentation, policy, link,
  and skill checks that can be affected;
- Dart or Flutter code runs formatting, analysis, and focused tests through the
  public or real provider boundary;
- dependency, release, native, or cross-cutting work runs supply-chain checks and
  the full relevant `tool/verify.dart` and `tool/release_audit.dart` gates;
- every explicitly requested command remains mandatory even when the diff looks
  low-risk.

Adding or changing a Flutter plugin requires regenerating and committing all
affected native integration. Run the relevant Flutter resolution/build on its
supported host and inspect generated registrants, build projects, and workspaces.
In particular, commit the CocoaPods integration emitted for iOS and macOS.
Platform builds must finish with `git diff --exit-code -- .` clean.

Review the full diff and `git diff --check` before each commit. Do not mix
unrelated cleanup, generated Dartdoc HTML, publication, or tags into a change.

Release tooling distinguishes the lockstep workspace cohort from the latest
distributed stable cohort. An untagged candidate version in 25 pubspecs does
not imply that its derivable tag exists. Verification may use only a local
disposable tag for a canary; creating or moving a remote tag, running the
`Release` workflow, creating a GitHub Release, publishing, or promoting a
candidate requires separate explicit authorization. Release workflows reject
prerelease workspace cohorts before external writes.

## Open and complete the pull request

Push only the topic branch. Use a Conventional Commit PR title suitable for the
final squash commit and complete every applicable template section: outcome,
ownership, compatibility, platform impact, verification evidence, native
integration, and remaining GitHub-hosted gates.

GitHub Actions checks out and builds the merge candidate. On `pull_request`, the
release audit receives `github.event.pull_request.head.sha` only for authorship,
so GitHub's synthetic merge author cannot mask or reject branch authors. On
`push`, the complete `main` history is audited. On `merge_group`, non-merge
commits are audited while the synthetic queue merge is excluded.

If a check fails, correct it on the same branch and keep the ruleset unchanged.
Resolve review conversations and update the branch when required. With one
maintainer, the ruleset intentionally requires zero approving reviews but still
requires `CI / Required` and resolved threads.

## Squash and clean up

Before enabling auto-merge, confirm the GitHub account selects `ftr@tuta.com` for
web operations and that email privacy does not force a `noreply` author on the
squash. Merge by squash only: the PR title becomes the commit title and commit
messages become the body. GitHub automatically deletes the topic branch.

After merge, wait for `CI / Required` on `main`. Confirm the remote has only
`main`, the ruleset has no bypass actors, the new commit and all reachable
history have canonical authorship, and GitHub lists only `ftr-tuta` as a
contributor. Verify a fresh clone is clean. Create and verify a new final bundle
without removing earlier backups.

## Break-glass recovery

Directly updating `main` is an exceptional recovery with a narrower authority
than normal contribution work. It requires explicit authorization that names
the recovery, target ref, expected remote SHA, and intended replacement. Before
any mutation:

1. fetch and record the exact remote refs, repository settings, and full ruleset;
2. create a timestamped `git bundle create <backup>.bundle --all`, run
   `git bundle verify <backup>.bundle`, and retain prior backups;
3. prepare and test a rollback that restores the captured `main` SHA;
4. if protection must be changed, prepare an automatic restoration path before
   changing it and make the narrowest temporary change possible.

Never use `git push --mirror`. Update only `refs/heads/main`, and when history
must be replaced use an exact lease such as:

```console
git push --force-with-lease=refs/heads/main:<captured-remote-sha> origin <recovery-sha>:refs/heads/main
```

Restore every protection immediately, including on failure; do not leave a
bypass actor or disabled rule while diagnosing. Re-fetch and verify remote refs,
canonical authorship, ruleset settings, CI, Security, a clean fresh clone, and a
new verified final bundle. If validation fails, roll back to the captured SHA
with a newly observed exact lease, restore protections first, and report the
failed recovery.

## Maintainer repository settings

Allow squash merge only. Enable auto-merge, branch updates, and automatic topic
branch deletion. Configure the squash title from the PR title and its body from
the commits.

Protect `main` with no bypass actors, deletion and non-fast-forward protection,
required thread resolution, an up-to-date branch, zero approvals while there is
only one maintainer, and exactly one required check: `CI / Required`. Its graph
owns all platform, native, security, audit, benchmark, and canary dependencies;
do not configure component jobs as separate required checks.
