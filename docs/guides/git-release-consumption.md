# Git release consumption

Dartitect 1.0.0 is distributed exclusively by the annotated `v1.0.0` tag and
its immutable GitHub Release. There is no supported Dartitect registry channel.
External packages continue to resolve from their normal registries.

The repository workspace may contain the untagged `1.1.0-rc.2` candidate
cohort. `v1.1.0-rc.2` is derivable but is not materialized or distributed, so
do not use it in consumer manifests. The recommended public version remains
`1.0.0` / `v1.0.0` until a separately authorized release exists.

## Declare direct packages

Declare only packages imported directly by the consumer. Use the exact URL,
package path, tag pattern, and version:

```yaml
dependencies:
  dartitect:
    git:
      url: https://github.com/ftr-tuta/dartitect.git
      path: packages/dartitect
      tag_pattern: 'v{{version}}'
    version: 1.0.0
```

For another package, change both the dependency name and `path`; keep the URL,
tag pattern, and version unchanged. Transitive Dartitect dependencies use their
own canonical descriptors from the same tag. Never add Dartitect
`dependency_overrides`, a workspace path, `main`, a branch, or an arbitrary
commit.

Official snippets are available in the Release asset
`dependency-snippets.zip` and from the source command:

```console
dart run tool/dependency_snippets.dart --profile=flutter
```

The profiles are core, Flutter, Drift, ObjectBox, and tooling.

## Install the CLI

```console
dart install https://github.com/ftr-tuta/dartitect.git \
  --git-path packages/dartitect_cli \
  --git-ref v1.0.0
```

## Verify the lockfile

Commit `pubspec.lock`. Every Dartitect entry must report version `1.0.0`, source
`git`, URL `https://github.com/ftr-tuta/dartitect.git`, its own
`packages/<package>` path, `tag-pattern: v{{version}}`, and the same full
`resolved-ref`. `dartitect doctor` enforces this graph.

Verify `SHA256SUMS`, `release-provenance.json`, and
`dartitect-git-manifest.json` from the immutable Release before accepting the
dependency change. A later release is a new lockstep upgrade: review it, run
dependency resolution, analysis, tests, and platform builds again.
