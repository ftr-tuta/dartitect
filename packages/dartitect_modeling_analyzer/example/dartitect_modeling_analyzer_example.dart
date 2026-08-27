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
