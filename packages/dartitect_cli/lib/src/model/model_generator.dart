import 'dart:convert';
import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:dartitect_modeling_analyzer/dartitect_modeling_analyzer.dart';

import '../generation/generation_engine.dart';

/// Stable model-generation diagnostic.
final class ModelDiagnostic {
  /// Creates a source, ownership, or freshness diagnostic.
  const ModelDiagnostic({
    required this.code,
    required this.message,
    required this.path,
    this.severity = ModelingDiagnosticSeverity.error,
    this.line,
    this.fixId,
  });

  /// Creates the CLI representation of a shared compiler diagnostic.
  factory ModelDiagnostic.fromModeling(ModelingDiagnostic diagnostic) =>
      ModelDiagnostic(
        code: diagnostic.rule,
        message: diagnostic.message,
        path: diagnostic.path,
        severity: diagnostic.severity,
        line: diagnostic.line,
        fixId: diagnostic.fixId,
      );

  /// Stable `DTnnnn` rule.
  final String code;

  /// Payload-free actionable message.
  final String message;

  /// Project-relative source or output path.
  final String path;

  /// Stable severity shared with lints and verification.
  final ModelingDiagnosticSeverity severity;

  /// Optional one-based source line.
  final int? line;

  /// Optional stable semantic-fix identifier.
  final String? fixId;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'rule': code,
    'severity': severity.name,
    'message': message,
    'path': path,
    if (line != null) 'line': line,
    if (fixId != null) 'fixId': fixId,
  };
}

/// Complete read-only model generation inspection.
final class ModelGenerationReport {
  /// Creates a report from source diagnostics and an optional engine plan.
  const ModelGenerationReport({
    required this.operations,
    required this.diagnostics,
    required this.plan,
  });

  /// Complete desired fully-generated output set.
  final List<FileGenerationOperation> operations;

  /// Invalid source-contract diagnostics.
  final List<ModelDiagnostic> diagnostics;

  /// Ownership/freshness plan when source analysis succeeded.
  final GenerationPlan? plan;

  /// Whether outputs, manifest, and recovery state are current.
  bool get isFresh =>
      diagnostics.isEmpty &&
      plan != null &&
      !plan!.pendingRecovery &&
      !plan!.hasConflicts &&
      !plan!.hasChanges;

  /// Stable diagnostics including freshness and ownership states.
  List<ModelDiagnostic> get findings {
    final output = <ModelDiagnostic>[...diagnostics];
    final currentPlan = plan;
    if (currentPlan == null) return List<ModelDiagnostic>.unmodifiable(output);
    if (currentPlan.pendingRecovery) {
      output.add(
        const ModelDiagnostic(
          code: 'DT1023',
          message:
              'A generation journal requires `model sync --apply` recovery.',
          path: '.dartitect/generation-journal.json',
        ),
      );
    }
    for (final operation in currentPlan.operations) {
      final path = operation.operation.relativePath;
      switch (operation.disposition) {
        case GenerationDisposition.create:
        case GenerationDisposition.update:
        case GenerationDisposition.delete:
          output.add(
            ModelDiagnostic(
              code: 'DT1020',
              message: switch (operation.disposition) {
                GenerationDisposition.create =>
                  'Generated model output is missing.',
                GenerationDisposition.update =>
                  'Generated model output is stale.',
                GenerationDisposition.delete =>
                  'Generated model output is orphaned.',
                _ => throw StateError('unreachable'),
              },
              path: path,
            ),
          );
        case GenerationDisposition.conflict:
          output.add(
            ModelDiagnostic(
              code: 'DT1022',
              message: 'Generated model ownership cannot be proven.',
              path: path,
            ),
          );
        case GenerationDisposition.noOp:
          break;
      }
    }
    output.sort((left, right) {
      final path = left.path.compareTo(right.path);
      if (path != 0) return path;
      return left.code.compareTo(right.code);
    });
    return List<ModelDiagnostic>.unmodifiable(output);
  }

  /// Stable JSON representation used by sync/check.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'model',
    'fresh': isFresh,
    'pendingRecovery': plan?.pendingRecovery ?? false,
    'operations': <Object?>[
      for (final operation
          in plan?.operations ?? const <PlannedFileOperation>[])
        <String, Object?>{
          'path': operation.operation.relativePath,
          'disposition': operation.disposition.name,
        },
    ],
    'diagnostics': <Object?>[
      for (final diagnostic in findings) diagnostic.toJson(),
    ],
  };
}

/// Invalid model sources prevented generation.
final class ModelGenerationException implements Exception {
  /// Creates the failure with deterministic [diagnostics].
  const ModelGenerationException(this.diagnostics);

  /// Source diagnostics that must be resolved.
  final List<ModelDiagnostic> diagnostics;

  @override
  String toString() => 'Model source validation failed.';
}

/// Native Analyzer-backed Dartitect model generator.
final class DartitectModelGenerator {
  /// Creates a generator for one project or pub workspace root.
  DartitectModelGenerator(
    Directory root, {
    GenerationFaultInjector? faultInjector,
  }) : root = root.absolute,
       _faultInjector = faultInjector;

  /// Project root; emitted paths remain relative.
  final Directory root;

  final GenerationFaultInjector? _faultInjector;

  /// Inspects source, ownership, freshness, and orphans without writing.
  Future<ModelGenerationReport> inspect() async {
    final discovery = await _discover();
    if (discovery.diagnostics.isNotEmpty) {
      return ModelGenerationReport(
        operations: discovery.operations,
        diagnostics: discovery.diagnostics,
        plan: null,
      );
    }
    final plan = await GenerationEngine(
      root,
      faultInjector: _faultInjector,
    ).plan(discovery.operations, manageFullyGenerated: true);
    return ModelGenerationReport(
      operations: discovery.operations,
      diagnostics: const <ModelDiagnostic>[],
      plan: plan,
    );
  }

  /// Recovers, rediscovers, replans, and commits the complete desired set.
  Future<GenerationResult> apply() async {
    final engine = GenerationEngine(root, faultInjector: _faultInjector);
    await engine.recover();
    final report = await inspect();
    if (report.diagnostics.isNotEmpty) {
      throw ModelGenerationException(report.diagnostics);
    }
    return engine.apply(report.operations, manageFullyGenerated: true);
  }

  Future<_Discovery> _discover() async {
    final compilation = await ModelingCompiler(root).compile();
    final diagnostics = <ModelDiagnostic>[
      for (final diagnostic in compilation.diagnostics)
        ModelDiagnostic.fromModeling(diagnostic),
    ];
    final operations = <FileGenerationOperation>[];
    for (final library in compilation.workspace.libraries) {
      operations.add(
        FileGenerationOperation(
          relativePath: library.outputPath,
          content: _render(library),
          ownership: GeneratedOwnership.fullyGenerated,
          sourcePath: library.path,
          inputSchemaVersion: 2,
          inputSignature: _semanticSignature(library),
        ),
      );
    }
    operations.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return _Discovery(
      List<FileGenerationOperation>.unmodifiable(operations),
      List<ModelDiagnostic>.unmodifiable(diagnostics),
    );
  }
}

String _semanticSignature(ModelingLibraryIr library) => jsonEncode(
  <String, Object?>{
    'schemaVersion': 2,
    'library': library.uri,
    'source': library.path,
    'part': library.outputPath,
    'models': <Object?>[
      for (final model in library.models)
        <String, Object?>{
          'class': model.name,
          'source': model.sourcePath,
          'const': model.isConst,
          'capabilities': model.capabilities.map((value) => value.name).toList()
            ..sort(),
          'typeParameters': <Object?>[
            for (final parameter in model.typeParameters)
              <String, Object?>{
                'name': parameter.name,
                if (parameter.bound != null)
                  'bound': parameter.bound!.displayName,
              },
          ],
          'constructor': <Object?>[
            for (final field in model.fields)
              <String, Object?>{
                'name': field.name,
                'type': field.type.displayName,
                'library': field.type.libraryUri,
                'nullable': field.type.nullable,
                'required': field.isRequiredNamed,
                if (field.defaultCode != null) 'default': field.defaultCode,
              },
          ],
        },
    ],
    'configuration': <String, Object?>{
      'equality': 'ValueEquality',
      'copyWith': 'typed-clear-flags-v1',
    },
  },
);

String _render(ModelingLibraryIr library) {
  final sourceName = _basename(library.path);
  final partName = _basename(library.outputPath);
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT EDIT BY HAND.')
    ..writeln('// Dartitect model generator 1.0.0-rc.3, input schema 2.')
    ..writeln()
    ..writeln("part of '$sourceName';");
  for (final model in library.models.where(
    (model) => model.capabilities.contains(ModelingCapability.value),
  )) {
    final declaration = _typeParameterDeclaration(model);
    final use = _typeParameterUse(model);
    buffer
      ..writeln()
      ..writeln(
        'mixin _\$${model.name}Dartitect$declaration on ValueEquality {',
      );
    for (final field in model.fields) {
      buffer.writeln('  ${field.type.displayName} get ${field.name};');
    }
    buffer
      ..writeln()
      ..writeln('  @override')
      ..writeln('  Iterable<Object?> get equalityFields => <Object?>[');
    for (final field in model.fields) {
      buffer.writeln('    ${field.name},');
    }
    buffer
      ..writeln('  ];')
      ..writeln()
      ..writeln('  ${model.name}$use copyWith({');
    for (final field in model.fields) {
      final parameterType = field.type.nullable
          ? field.type.displayName
          : '${field.type.displayName}?';
      buffer.writeln('    $parameterType ${field.name},');
      if (field.type.nullable) {
        buffer.writeln('    bool ${_clearName(field.name)} = false,');
      }
    }
    buffer.writeln('  }) {');
    for (final field in model.fields.where((field) => field.type.nullable)) {
      final clear = _clearName(field.name);
      buffer
        ..writeln('    if ($clear && ${field.name} != null) {')
        ..writeln(
          "      throw ArgumentError('${field.name} and $clear cannot be used together.');",
        )
        ..writeln('    }');
    }
    buffer.writeln('    return ${model.name}$use(');
    for (final field in model.fields) {
      if (field.type.nullable) {
        buffer.writeln(
          '      ${field.name}: ${_clearName(field.name)} '
          '? null : ${field.name} ?? this.${field.name},',
        );
      } else {
        buffer.writeln(
          '      ${field.name}: ${field.name} ?? this.${field.name},',
        );
      }
    }
    buffer
      ..writeln('    );')
      ..writeln('  }')
      ..writeln('}');
  }
  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    lineEnding: '\n',
  ).format(buffer.toString(), uri: partName);
}

String _typeParameterDeclaration(ModelingModelIr model) {
  if (model.typeParameters.isEmpty) return '';
  return '<${model.typeParameters.map((parameter) {
    final bound = parameter.bound;
    return bound == null ? parameter.name : '${parameter.name} extends ${bound.displayName}';
  }).join(', ')}>';
}

String _typeParameterUse(ModelingModelIr model) => model.typeParameters.isEmpty
    ? ''
    : '<${model.typeParameters.map((parameter) => parameter.name).join(', ')}>';

String _clearName(String field) =>
    'clear${field[0].toUpperCase()}${field.substring(1)}';

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

final class _Discovery {
  const _Discovery(this.operations, this.diagnostics);

  final List<FileGenerationOperation> operations;
  final List<ModelDiagnostic> diagnostics;
}
