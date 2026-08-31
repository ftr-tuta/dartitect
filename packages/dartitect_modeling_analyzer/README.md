# dartitect_modeling_analyzer

## Purpose

Read-only Analyzer-backed semantic compilation shared by the Dartitect CLI and
official analyzer plugin. It produces renderer-neutral modeling IR, stable
diagnostics, compatibility decisions, and semantic source edits.

## When to use

Use it when implementing Dartitect-aware developer tooling that must resolve
primary constructors, annotations, elements, and `DartType` identity once and
share the same interpretation as the official CLI and lints.

## When not to use

Runtime applications must not depend on this package. Do not use it for source
generation side effects, runtime reflection, provider schemas, or text-only
heuristics when resolved semantic identity is available.

## Platforms and entrypoints

Import
`package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart`. It is a
Dart VM tooling package backed by `package:analyzer`; it is not a Flutter or web
runtime library.

## Mental model and data flow

A tooling caller gives `ModelingCompiler` an Analyzer-resolved workspace. The
compiler validates libraries and primary-constructor models, then returns
immutable workspace/library/model/field IR plus stable diagnostics. Renderers
and mutators consume that IR separately. `primaryConstructorSourceEdits`
produces reviewed semantic edits without applying them.

## Minimal workflow

```dart
import 'package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart';

void main() {
  const workspace = ModelingWorkspaceIr(
    root: '/workspace',
    libraries: <ModelingLibraryIr>[],
  );
  const diagnostic = ModelingDiagnostic(
    rule: 'DT1030',
    severity: ModelingDiagnosticSeverity.error,
    message: 'A primary constructor is required.',
    path: 'lib/profile.dart',
    line: 4,
    fixId: 'model.migrate.primary',
  );

  assert(workspace.libraries.isEmpty);
  assert(diagnostic.toJson()['rule'] == 'DT1030');
}
```

## Public API tour

- `ModelingCompiler` and `ModelingCompilation` are the semantic compilation
  boundary.
- Workspace, library, model, field, type, projection, JSON, and mapper IR types
  expose renderer-neutral facts.
- `ModelingCapability`, `ModelingCompatibility`, and
  `ModelingCompatibilityDecisionIr` describe supported generation decisions.
- `ModelingDiagnostic` and `ModelingDiagnosticSeverity` provide stable,
  serializable diagnostics.
- `ModelingSourceEdit`, `primaryConstructorSourceEdits`, and
  `hasLexicalModelingAnnotation` support reviewed source tooling.

## Ownership and lifecycle

The caller owns Analyzer contexts, sessions, files, and any write transaction.
Compiler output is immutable data. This package reads and describes source; it
does not take a project lock, write a file, or own generated outputs.

## Failure, cancellation, and concurrency

Semantic incompatibilities are returned as diagnostics or compatibility
decisions. Analyzer/session failures remain tooling failures. The compiler has
no cancellation protocol or background worker; callers must coordinate Analyzer
sessions and avoid concurrent writes while consuming positions or edits.

## Prohibited uses and limitations

Do not import it from application runtime code, apply source edits without a
preview and project lock, treat lexical annotation detection as semantic proof,
or create a second modeling interpretation outside the shared compiler.

## Testing

Run `dart test`. Cover resolved type identity, primary constructors, generic
types, annotations, diagnostics, compatibility decisions, and exact source-edit
ranges. CLI and lints tests must demonstrate parity over the shared IR.

## Related packages and guides

Used by `dartitect_cli` and `dartitect_lints`; model annotations and runtime
types live in `dartitect_modeling`. Read
[model generation](../../docs/guides/model-generation.md) and
[tooling guidance](../../docs/guides/getting-started.md).

## Availability

The workspace contains the `1.0.0-rc.10` source candidate. Use only coordinates
published in a matching tagged GitHub Release; without one, there is no
supported consumption path. See the
[Git candidate consumption guide](../../docs/guides/git-candidate-consumption.md).
