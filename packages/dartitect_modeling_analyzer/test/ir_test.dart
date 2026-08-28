import 'package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart';
import 'package:test/test.dart';

void main() {
  test('public IR retains renderer-neutral modeling decisions', () {
    const type = ModelingTypeIr(
      displayName: 'String',
      declarationName: 'String',
      libraryUri: 'dart:core',
      nullable: false,
    );
    const field = ModelingFieldIr(name: 'name', type: type);
    const model = ModelingModelIr(
      name: 'Profile',
      sourcePath: 'lib/profile.dart',
      fields: <ModelingFieldIr>[field],
      capabilities: <ModelingCapability>{ModelingCapability.value},
    );
    const workspace = ModelingWorkspaceIr(
      root: '/workspace',
      libraries: <ModelingLibraryIr>[
        ModelingLibraryIr(
          uri: 'package:app/profile.dart',
          path: 'lib/profile.dart',
          outputPath: 'lib/profile.dartitect.g.dart',
          models: <ModelingModelIr>[model],
        ),
      ],
    );

    expect(workspace.libraries.single.models.single.name, 'Profile');
    expect(model.capabilities, <ModelingCapability>{ModelingCapability.value});
  });

  test('diagnostic schema uses rule, severity, path, line, and fixId', () {
    const diagnostic = ModelingDiagnostic(
      rule: 'DT1030',
      severity: ModelingDiagnosticSeverity.error,
      message: 'A primary constructor is required.',
      path: 'lib/profile.dart',
      line: 7,
      fixId: 'migrate_primary_constructor',
    );

    expect(diagnostic.toJson(), <String, Object?>{
      'rule': 'DT1030',
      'severity': 'error',
      'message': 'A primary constructor is required.',
      'path': 'lib/profile.dart',
      'line': 7,
      'fixId': 'migrate_primary_constructor',
    });
  });
}
