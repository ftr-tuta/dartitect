# Typed project-local extensions

Dartitect is closed to concrete product, organization, and business behavior.
When reusable infrastructure is intentionally specific to one greenfield
project, declare it in ordinary typed Dart inside that project and list the
source in config v3. The SDK has no plugin loader, registry, string lookup,
marketplace, or globally installed extension.

```dart
import 'package:dartitect/dartitect.dart';

final class ProjectTelemetry {
  ProjectTelemetry(this.close);

  final Future<void> Function() close;
}

@DartitectProjectExtension()
final class ProjectTelemetryExtension
    implements DartitectLocalExtension<ProjectTelemetry> {
  @override
  ProjectTelemetry build() => ProjectTelemetry(() async {
    // Construct only infrastructure belonging to this project.
  });

  @override
  Future<void> dispose(ProjectTelemetry binding) => binding.close();
}
```

Declare the importable source, never a class name or runtime identifier:

```json
{
  "extensionSources": ["lib/infrastructure/project_extensions.dart"]
}
```

`dartitect wiring sync` resolves the annotation and generic binding through the
Dart analyzer without loading or executing the library. Generated composition
constructs the declaration directly, adds a field with the concrete binding
type, owns that binding in the application graph, and calls its typed disposal
callback exactly once.

Declarations must be public, concrete final classes with an unnamed
zero-argument constructor and a concrete non-nullable `B`. Sources must resolve
inside the project's real filesystem boundary and be importable from a package
`lib` directory. A package in the same workspace is accepted only when its real
path stays inside the project. Missing files, analyzer errors, false/homonymous
annotations, field collisions, external symlink targets, `Object`, `dynamic`,
and generic declarations fail before generation writes anything.

Multiple local extensions are allowed. Keep their binding contracts neutral to
the application's layers: domain schema, business rules, semantic mappings,
conflict policy, credentials, and UI remain ordinary consumer-owned code.
