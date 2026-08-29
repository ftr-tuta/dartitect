# Contributing to Dartitect

## Before opening a change

Search existing issues, keep scope narrow, and state the ownership/composition
boundary affected. For security issues, stop and use the private process in
`SECURITY.md`.

## Development setup

Install Dart `^3.13.0` and Flutter `>=3.47.1`, then run:

```console
flutter pub get
dart run tool/verify.dart --skip-get
```

Use `dart run tool/setup_objectbox_vm.dart` before the native ObjectBox fixture.
Generated API HTML under `docs/api/` is local-only.

Repository commits must use the canonical identity and local-only protection:

```console
git config --local user.name ftr
git config --local user.email ftr@tuta.com
git config --local user.useConfigOnly true
```

Do not change the global Git identity for Dartitect work.

## Branches and commits

Normal work never starts or lands directly on `main`. Fetch the remote and
create a short-lived branch from `origin/main` using `feat/`, `fix/`, `ci/`,
`docs/`, `chore/`, or `release/`. Use Conventional Commits and keep every commit
authored as `ftr <ftr@tuta.com>`.

Do not bypass branch protections. Preserve unrelated local work, keep the
branch focused, and fix a failed `CI / Required` result on that same branch.

## Change requirements

Before accepting any new capability, answer this question:

> É business-neutral, difícil de implementar corretamente e gera infraestrutura repetitiva no consumidor?

All three answers must be yes. Otherwise keep the capability in `softgran_*`,
`agrox_*`, or the application and do not add it to Dartitect.

- Preserve native-first constructor injection and explicit owned/borrowed state.
- Add tests through public entrypoints and real provider boundaries where needed.
- Document every supported public member and update the API snapshot.
- Keep public English documentation and generated catalogs current.
- Update dependency/source ledgers, licenses, SBOM, skills, and release gates when
  the change affects them.
- When adding or changing a Flutter plugin, regenerate and commit every affected
  native project/workspace integration, including CocoaPods changes for iOS and
  macOS, then prove platform builds leave the tracked tree unchanged.
- Do not publish packages, create tags, or commit generated Dartdoc HTML.

## New adapter checklist

- [ ] Optional, isolated package with consumer-owned provider configuration.
- [ ] Real SDK boundary test and deterministic no-network tests where relevant.
- [ ] Explicit owned/borrowed lifetime and reverse disposal order.
- [ ] Minimal/redacted telemetry with no credentials, bodies, headers, or identity.
- [ ] English README, example, Dartdoc, changelog, license, and topics.
- [ ] Dependency/version rationale, license review, and advisory check.
- [ ] Public API snapshot, package catalog, and skills coverage updated.

## Pull requests

Explain the outcome, tests, platform impact, compatibility risk, and any
remaining GitHub-hosted validation. Complete every applicable item in the PR
template and run checks proportional to the change before pushing. The required
`CI / Required` check must pass against the merge candidate; authorship auditing
uses the PR head because GitHub creates a synthetic merge commit.

Use squash merge only, with the PR title as the final Conventional Commit title.
Resolve all conversations, update the branch when required, and delete the
short-lived branch after merge. A passing dry-run does not authorize publication.
See the complete [repository contribution workflow](docs/guides/repository-contribution.md).

## Emergency recovery

Direct updates to `main` are break-glass operations, not a contribution path.
They require explicit authorization, a verified bundle and remote-state backup,
an exact force-with-lease when rewriting is unavoidable, a tested rollback, and
immediate restoration of every protection. Never use `git push --mirror`. Follow
the procedure in the repository contribution guide without weakening checks for
ordinary work.
