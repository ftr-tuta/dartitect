## Outcome

Describe the user-visible result and affected packages.

## Ownership and compatibility

- Owned/borrowed resources and disposal order:
- Dart/Flutter/platform impact:
- Public API/config/generated ownership impact:

## Verification

- [ ] The source branch is short-lived and uses an allowed prefix; no normal work was pushed directly to `main`.
- [ ] Commits use Conventional Commits and canonical `ftr <ftr@tuta.com>` authorship.
- [ ] Format and analyze pass.
- [ ] Relevant pure Dart/Flutter/real-boundary tests pass.
- [ ] Public Dartdoc and API snapshot are current.
- [ ] English docs/examples and generated catalogs are current.
- [ ] Dependency/source/license/SBOM/advisory records are current if affected.
- [ ] Skills/catalog/gates are current if affected.
- [ ] No secrets, generated Dartdoc HTML, publication, tags, or unrelated changes.

## Native integration (when applicable)

- [ ] Added or changed Flutter plugins are reflected in every affected native project/workspace.
- [ ] iOS/macOS CocoaPods integration is tracked and native builds leave the Git tree unchanged.

## Merge readiness

- [ ] The PR title is the intended final Conventional Commit title and the description is complete.
- [ ] Required checks pass on the merge candidate and all conversations are resolved.
- [ ] The branch is up to date when required and is ready for squash merge and deletion.

## Adapter checklist (when applicable)

- [ ] Optional isolated package and real SDK fixture.
- [ ] Consumer-owned entities/schemas/credentials/configuration.
- [ ] Minimal redacted telemetry and explicit lifecycle.
- [ ] Dependency rationale, license, example, and skill updates.
