# dartitect_modeling_analyzer

[Português (Brasil)](README.pt-BR.md)

## Purpose

Read-only Analyzer-backed semantic compiler shared by the Dartitect CLI and
official lints. It resolves libraries once, validates primary constructors with
element and `DartType` identity, and exposes renderer-neutral workspace IR plus
stable diagnostics and semantic source edits. Runtime applications must never
depend on this package.
