import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:dart_style/dart_style.dart';

import '../generation/generation_engine.dart';

/// Stable model-generation diagnostic.
final class ModelDiagnostic {
  /// Creates a source contract diagnostic.
  const ModelDiagnostic({
    required this.code,
    required this.message,
    required this.path,
    this.line,
  });

  /// Stable DT102x code.
  final String code;

  /// Payload-free actionable message.
  final String message;

  /// Project-relative source or output path.
  final String path;

  /// Optional one-based source line.
  final int? line;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'path': path,
    if (line != null) 'line': line,
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

/// Native Analyzer-backed Dartitect value generator.
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
    final files = await _sourceFiles();
    final diagnostics = <ModelDiagnostic>[];
    final operations = <FileGenerationOperation>[];
    final annotatedFiles = <_AnnotatedFile>[];
    final collection = AnalysisContextCollection(
      includedPaths: <String>[root.path],
      excludedPaths: <String>[
        _join(root.path, '.dart_tool'),
        _join(root.path, 'build'),
      ],
    );
    try {
      for (final file in files) {
        final source = await file.readAsString();
        final parsed = parseString(
          content: source,
          path: file.path,
          throwIfDiagnostics: false,
        );
        final lexical = parsed.unit.declarations
            .whereType<ClassDeclaration>()
            .where(_hasLexicalDartitectValue)
            .toList(growable: false);
        if (lexical.isEmpty) continue;
        final path = _relative(file.path);
        final context = collection.contextFor(file.path);
        final result = await context.currentSession.getResolvedUnit(file.path);
        if (result is! ResolvedUnitResult) {
          diagnostics.add(
            ModelDiagnostic(
              code: 'DT1021',
              message: 'Analyzer could not resolve the model library.',
              path: path,
            ),
          );
          continue;
        }
        final candidates = result.unit.declarations
            .whereType<ClassDeclaration>()
            .where(_hasLexicalDartitectValue)
            .toList(growable: false);
        final annotated = candidates
            .where(_hasDartitectValue)
            .toList(growable: false);
        if (annotated.length != candidates.length) {
          diagnostics.add(
            ModelDiagnostic(
              code: 'DT1021',
              message:
                  'DartitectValue must resolve to the annotation declared by '
                  'package:dartitect.',
              path: path,
            ),
          );
        }
        if (annotated.isEmpty) continue;
        if (annotated.length != 1) {
          diagnostics.add(
            ModelDiagnostic(
              code: 'DT1021',
              message:
                  'A source library must contain exactly one DartitectValue '
                  'class.',
              path: path,
            ),
          );
          continue;
        }
        final declaration = annotated.single;
        final model = _validateModel(
          result.unit,
          declaration,
          path: path,
          lineAt: (offset) => result.lineInfo.getLocation(offset).lineNumber,
          diagnostics: diagnostics,
        );
        if (model == null) continue;
        final outputPath =
            path.substring(0, path.length - '.dart'.length) +
            '.dartitect.g.dart';
        annotatedFiles.add(
          _AnnotatedFile(
            file: file,
            outputPath: outputPath,
            mixinName: '_\$${model.name}Dartitect',
          ),
        );
        operations.add(
          FileGenerationOperation(
            relativePath: outputPath,
            content: _render(model, sourcePath: path),
            ownership: GeneratedOwnership.fullyGenerated,
            sourcePath: path,
            inputSignature: _semanticSignature(model, sourcePath: path),
          ),
        );
      }
    } finally {
      await collection.dispose();
    }

    if (annotatedFiles.isNotEmpty) {
      await _validateAnalyzerBootstrap(annotatedFiles, diagnostics);
    }
    diagnostics.sort((left, right) {
      final path = left.path.compareTo(right.path);
      if (path != 0) return path;
      return (left.line ?? 0).compareTo(right.line ?? 0);
    });
    operations.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return _Discovery(
      List<FileGenerationOperation>.unmodifiable(operations),
      List<ModelDiagnostic>.unmodifiable(diagnostics),
    );
  }

  _Model? _validateModel(
    CompilationUnit unit,
    ClassDeclaration declaration, {
    required String path,
    required int Function(int) lineAt,
    required List<ModelDiagnostic> diagnostics,
  }) {
    final before = diagnostics.length;
    void reject(String message, [AstNode? node]) {
      diagnostics.add(
        ModelDiagnostic(
          code: 'DT1021',
          message: message,
          path: path,
          line: node == null ? null : lineAt(node.offset),
        ),
      );
    }

    final name = declaration.namePart.typeName.lexeme;
    final expectedPart =
        '${_basename(path, removeExtension: true)}.dartitect.g.dart';
    final partUris = unit.directives
        .whereType<PartDirective>()
        .map((directive) => directive.uri.stringValue)
        .whereType<String>()
        .toList(growable: false);
    if (partUris.where((uri) => uri == expectedPart).length != 1) {
      reject('The library must declare exactly `part \'$expectedPart\';`.');
    }
    if (declaration.finalKeyword == null) {
      reject('DartitectValue classes must be final.', declaration);
    }
    if (declaration.abstractKeyword != null) {
      reject('DartitectValue classes must be concrete.', declaration);
    }
    if (declaration.namePart.typeParameters != null) {
      reject(
        'Generic DartitectValue classes are not supported in 1.0.',
        declaration,
      );
    }
    final superclass = declaration.extendsClause?.superclass.toSource();
    if (superclass == null || superclass.split('.').last != 'ValueEquality') {
      reject('DartitectValue classes must extend ValueEquality.', declaration);
    }
    final expectedMixin = '_\$${name}Dartitect';
    final mixins =
        declaration.withClause?.mixinTypes
            .map((type) => type.toSource())
            .toList(growable: false) ??
        const <String>[];
    if (!mixins.contains(expectedMixin)) {
      reject('The class must mix in $expectedMixin.', declaration);
    }

    final fields = <_Field>[];
    for (final member
        in declaration.body.members.whereType<FieldDeclaration>()) {
      if (member.isStatic ||
          !member.fields.isFinal ||
          member.fields.isLate ||
          member.fields.type == null) {
        reject(
          'Model fields must be typed, instance, final, and non-late.',
          member,
        );
        continue;
      }
      final typeAnnotation = member.fields.type!;
      final type = typeAnnotation.toSource();
      if (_isMutableCollection(typeAnnotation)) {
        reject(
          'Mutable collection interfaces are not supported in model fields.',
          member,
        );
      }
      for (final variable in member.fields.variables) {
        final fieldName = variable.name.lexeme;
        if (fieldName.startsWith('_') || variable.initializer != null) {
          reject(
            'Model fields must be public and initialized by the constructor.',
            variable,
          );
          continue;
        }
        fields.add(
          _Field(
            name: fieldName,
            type: type,
            nullable: type.trim().endsWith('?'),
          ),
        );
      }
    }
    if (fields.isEmpty)
      reject('A DartitectValue class must declare at least one field.');

    final constructors = declaration.body.members
        .whereType<ConstructorDeclaration>()
        .toList(growable: false);
    if (constructors.length != 1 ||
        constructors.single.name != null ||
        constructors.single.factoryKeyword != null ||
        constructors.single.externalKeyword != null) {
      reject(
        'The class must have one unnamed generative constructor.',
        declaration,
      );
    } else {
      final parameters = constructors.single.parameters.parameters;
      final names = <String>[];
      for (final parameter in parameters) {
        final parameterName = parameter.name?.lexeme;
        if (!parameter.isNamed || parameterName == null) {
          reject('Every model constructor parameter must be named.', parameter);
          continue;
        }
        names.add(parameterName);
        final field = fields
            .where((field) => field.name == parameterName)
            .firstOrNull;
        if (field == null) continue;
        final declaredType = parameter.type?.toSource();
        if (declaredType != null && declaredType != field.type) {
          reject(
            'Constructor parameter types must match their fields.',
            parameter,
          );
        }
      }
      final fieldNames = fields.map((field) => field.name).toList();
      if (names.length != fieldNames.length ||
          !names.toSet().containsAll(fieldNames)) {
        reject(
          'Constructor named parameters must correspond exactly to fields.',
          constructors.single,
        );
      }
    }

    final generatedParameters = <String>{
      for (final field in fields) field.name,
    };
    for (final field in fields.where((field) => field.nullable)) {
      final clearName = _clearName(field.name);
      if (!generatedParameters.add(clearName)) {
        reject(
          'Nullable clear flag `$clearName` collides with a field.',
          declaration,
        );
      }
    }
    if (diagnostics.length != before) return null;
    return _Model(name: name, partUri: expectedPart, fields: fields);
  }

  Future<void> _validateAnalyzerBootstrap(
    List<_AnnotatedFile> files,
    List<ModelDiagnostic> diagnostics,
  ) async {
    final collection = AnalysisContextCollection(
      includedPaths: <String>[root.path],
      excludedPaths: <String>[
        _join(root.path, '.dart_tool'),
        _join(root.path, 'build'),
      ],
    );
    try {
      for (final annotated in files) {
        final context = collection.contextFor(annotated.file.path);
        final result = await context.currentSession.getResolvedUnit(
          annotated.file.path,
        );
        if (result is! ResolvedUnitResult) {
          diagnostics.add(
            ModelDiagnostic(
              code: 'DT1021',
              message: 'Analyzer could not resolve the model library.',
              path: _relative(annotated.file.path),
            ),
          );
          continue;
        }
        for (final diagnostic in result.diagnostics) {
          if (diagnostic.severity != Severity.error) continue;
          final expectedBootstrap =
              diagnostic.message.contains(_basename(annotated.outputPath)) ||
              diagnostic.message.contains(annotated.mixinName) ||
              diagnostic.diagnosticCode.lowerCaseName ==
                      'non_abstract_class_inherits_abstract_member' &&
                  diagnostic.message.contains('ValueEquality.equalityFields');
          if (expectedBootstrap) continue;
          diagnostics.add(
            ModelDiagnostic(
              code: 'DT1021',
              message: 'Analyzer: ${diagnostic.message}',
              path: _relative(annotated.file.path),
              line: result.lineInfo.getLocation(diagnostic.offset).lineNumber,
            ),
          );
        }
      }
    } finally {
      await collection.dispose();
    }
  }

  Future<List<File>> _sourceFiles() async {
    final roots = <Directory>[];
    final lib = Directory(_join(root.path, 'lib'));
    if (await lib.exists()) roots.add(lib);
    final packages = Directory(_join(root.path, 'packages'));
    if (await packages.exists()) {
      await for (final package in packages.list(followLinks: false)) {
        if (package is! Directory) continue;
        final packageLib = Directory(_join(package.path, 'lib'));
        if (await packageLib.exists()) roots.add(packageLib);
      }
    }
    final files = <File>[];
    for (final sourceRoot in roots) {
      await for (final entity in sourceRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.dartitect.g.dart')) {
          files.add(entity.absolute);
        }
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  String _relative(String path) => path
      .substring(root.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

bool _hasLexicalDartitectValue(ClassDeclaration declaration) =>
    declaration.metadata.any(
      (annotation) =>
          annotation.name.toSource().split('.').last == 'DartitectValue',
    );

bool _hasDartitectValue(ClassDeclaration declaration) =>
    declaration.metadata.any((annotation) {
      final element = annotation.element;
      return element?.enclosingElement?.displayName == 'DartitectValue' &&
          element?.library?.uri.toString() ==
              'package:dartitect/src/dartitect_value.dart';
    });

bool _isMutableCollection(TypeAnnotation type) {
  final normalized = type.toSource().replaceAll(RegExp(r'\s+'), '');
  final base = RegExp(r'^(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)')
      .firstMatch(normalized)
      ?.group(1);
  final resolvedBase = type.type?.extensionTypeErasure.element?.displayName;
  const mutableInterfaces = <String>{
    'List',
    'Set',
    'Map',
    'Iterable',
    'Queue',
    'HashMap',
    'LinkedHashMap',
    'SplayTreeMap',
    'HashSet',
    'LinkedHashSet',
    'SplayTreeSet',
    'Uint8List',
    'Int8List',
    'Uint16List',
    'Int16List',
    'Uint32List',
    'Int32List',
    'Uint64List',
    'Int64List',
    'Float32List',
    'Float64List',
  };
  return mutableInterfaces.contains(base) ||
      mutableInterfaces.contains(resolvedBase);
}

String _semanticSignature(_Model model, {required String sourcePath}) =>
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'source': sourcePath,
      'class': model.name,
      'part': model.partUri,
      'constructor': <Object?>[
        for (final field in model.fields)
          <String, Object?>{
            'name': field.name,
            'type': field.type,
            'nullable': field.nullable,
          },
      ],
      'configuration': <String, Object?>{
        'equality': 'ValueEquality',
        'copyWith': 'typed-clear-flags-v1',
      },
    });

String _render(_Model model, {required String sourcePath}) {
  final sourceName = _basename(sourcePath);
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT EDIT BY HAND.')
    ..writeln('// Dartitect model generator 1.0.0-rc.2, input schema 1.')
    ..writeln()
    ..writeln("part of '$sourceName';")
    ..writeln()
    ..writeln('mixin _\$${model.name}Dartitect on ValueEquality {');
  for (final field in model.fields) {
    buffer.writeln('  ${field.type} get ${field.name};');
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
    ..writeln('  ${model.name} copyWith({');
  for (final field in model.fields) {
    final parameterType = field.nullable ? field.type : '${field.type}?';
    buffer.writeln('    $parameterType ${field.name},');
    if (field.nullable) {
      buffer.writeln('    bool ${_clearName(field.name)} = false,');
    }
  }
  buffer.writeln('  }) {');
  for (final field in model.fields.where((field) => field.nullable)) {
    final clear = _clearName(field.name);
    buffer
      ..writeln('    if ($clear && ${field.name} != null) {')
      ..writeln(
        "      throw ArgumentError('${field.name} and $clear cannot be used together.');",
      )
      ..writeln('    }');
  }
  buffer.writeln('    return ${model.name}(');
  for (final field in model.fields) {
    if (field.nullable) {
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
  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    lineEnding: '\n',
  ).format(buffer.toString(), uri: model.partUri);
}

String _clearName(String field) =>
    'clear${field[0].toUpperCase()}${field.substring(1)}';

String _basename(String path, {bool removeExtension = false}) {
  final name = path.replaceAll('\\', '/').split('/').last;
  if (!removeExtension) return name;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

final class _Discovery {
  const _Discovery(this.operations, this.diagnostics);

  final List<FileGenerationOperation> operations;
  final List<ModelDiagnostic> diagnostics;
}

final class _AnnotatedFile {
  const _AnnotatedFile({
    required this.file,
    required this.outputPath,
    required this.mixinName,
  });

  final File file;
  final String outputPath;
  final String mixinName;
}

final class _Model {
  const _Model({
    required this.name,
    required this.partUri,
    required this.fields,
  });

  final String name;
  final String partUri;
  final List<_Field> fields;
}

final class _Field {
  const _Field({
    required this.name,
    required this.type,
    required this.nullable,
  });

  final String name;
  final String type;
  final bool nullable;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
