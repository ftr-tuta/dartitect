# Git candidate consumption

[Português (Brasil)](git-candidate-consumption.pt-BR.md)

## Channel

`v1.0.0-rc.1` is an annotated, unsigned Git-consumption tag over the complete
sixteen-package cohort. It is protected against updates and deletion. It is not
a GitHub Release, a pub.dev publication, or the future signed formal release
channel.

## Add packages

Keep normal version declarations so the intended cohort remains visible, then
override every selected package and transitive Dartitect dependency to the same
repository and tag:

```yaml
dependencies:
  dartitect_flutter: 1.0.0-rc.1

dependency_overrides:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.1
      path: packages/dartitect
  dartitect_flutter:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      ref: v1.0.0-rc.1
      path: packages/dartitect_flutter
```

Do not mix local `path:` dependencies, another Dartitect ref, or hosted
Dartitect packages into the same resolution.

## Generate the transitive closure

From a clone of this repository, emit a ready-to-paste override block for one
or more packages:

```console
dart run tool/git_dependency_overrides.dart dartitect_flutter
dart run tool/git_dependency_overrides.dart dartitect_media,dartitect_privacy
```

The generator reads the checked sixteen-package publication order and package
pubspecs, follows all internal dependencies, rejects unknown packages, and
emits one common URL/ref with a package-relative Git path.

## Verify resolution

Run `flutter pub get`, then inspect `pubspec.lock`: every resolved package whose
name starts with `dartitect` must have `source: git`, the same URL, the
`v1.0.0-rc.1` ref, and a `packages/<name>` path. The package configuration must
point into Pub's Git cache, never into a local Dartitect checkout.

Maintainers validate the minimal, offline-first, and native-capability consumers
with:

```console
dart run tool/run_git_canaries.dart \
  --repository=https://github.com/ftr-tuta/dartitect.git \
  --ref=v1.0.0-rc.1
```

The gate rejects a missing/lightweight tag, a mixed commit, any hosted
Dartitect package, and any local path resolution. Physical Android/iOS evidence
remains a separate external gate.
