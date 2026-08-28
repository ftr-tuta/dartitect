import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/source/line_info.dart';

import 'diagnostic.dart';
import 'ir.dart';
import 'source_edit.dart';

/// Validated renderer-neutral IR and all payload-free source diagnostics.
final class ModelingCompilation {
  /// Creates one deterministic compiler result.
  const ModelingCompilation({
    required this.workspace,
    required this.diagnostics,
  });

  /// Validated workspace. Invalid libraries are omitted.
  final ModelingWorkspaceIr workspace;

  /// Diagnostics sorted by path, line, and rule.
  final List<ModelingDiagnostic> diagnostics;

  /// Whether every discovered modeling library is safe to render.
  bool get isValid => diagnostics.every(
    (diagnostic) => diagnostic.severity != ModelingDiagnosticSeverity.error,
  );
}

/// Result of validating one annotated class through the shared compiler.
final class ModelingClassCompilation {
  /// Creates one class validation result.
  const ModelingClassCompilation({
    required this.model,
    required this.diagnostics,
  });

  /// Validated model, or `null` when an error prevents rendering.
  final ModelingModelIr? model;

  /// Stable class diagnostics.
  final List<ModelingDiagnostic> diagnostics;
}

/// Read-only Analyzer-backed semantic compiler shared by CLI and lints.
final class ModelingCompiler {
  /// Creates a compiler for one Dart project or pub workspace.
  ModelingCompiler(Directory root) : root = root.absolute;

  /// Canonical compiler root.
  final Directory root;

  /// Resolves each candidate library within one Analyzer lifecycle.
  Future<ModelingCompilation> compile() async {
    final diagnostics = <ModelingDiagnostic>[];
    final libraries = <ModelingLibraryIr>[];
    final collection = AnalysisContextCollection(
      includedPaths: <String>[root.path],
      excludedPaths: <String>[
        _join(root.path, '.dart_tool'),
        _join(root.path, 'build'),
      ],
    );
    try {
      final definingPaths = <String>{};
      for (final file in await _sourceFiles()) {
        final parsed = parseString(
          content: await file.readAsString(),
          path: file.path,
          throwIfDiagnostics: false,
        );
        if (!parsed.unit.declarations.whereType<ClassDeclaration>().any(
          hasLexicalModelingAnnotation,
        )) {
          continue;
        }
        final result = await collection
            .contextFor(file.path)
            .currentSession
            .getResolvedUnit(file.path);
        if (result is! ResolvedUnitResult) {
          diagnostics.add(
            _diagnostic(
              rule: 'DT1039',
              message: 'Analyzer could not resolve the modeling library.',
              path: _relative(file.path),
            ),
          );
          continue;
        }
        definingPaths.add(result.libraryElement.firstFragment.source.fullName);
      }

      final orderedPaths = definingPaths.toList()..sort();
      for (final definingPath in orderedPaths) {
        final result = await collection
            .contextFor(definingPath)
            .currentSession
            .getResolvedLibrary(definingPath);
        if (result is! ResolvedLibraryResult) {
          diagnostics.add(
            _diagnostic(
              rule: 'DT1039',
              message:
                  'Analyzer could not resolve the complete modeling library.',
              path: _relative(definingPath),
            ),
          );
          continue;
        }
        final compiled = compileResolvedLibrary(result, rootPath: root.path);
        diagnostics.addAll(compiled.diagnostics);
        libraries.addAll(compiled.workspace.libraries);
      }
    } finally {
      await collection.dispose();
    }
    _sortDiagnostics(diagnostics);
    libraries.sort((left, right) => left.path.compareTo(right.path));
    return ModelingCompilation(
      workspace: ModelingWorkspaceIr(
        root: root.path.replaceAll('\\', '/'),
        libraries: List<ModelingLibraryIr>.unmodifiable(libraries),
      ),
      diagnostics: List<ModelingDiagnostic>.unmodifiable(diagnostics),
    );
  }

  /// Compiles a resolved library without creating another Analyzer lifecycle.
  static ModelingCompilation compileResolvedLibrary(
    ResolvedLibraryResult result, {
    required String rootPath,
  }) {
    final definingPath = result.element.firstFragment.source.fullName;
    final defining = result.unitWithPath(definingPath);
    if (defining == null) {
      final diagnostic = _diagnostic(
        rule: 'DT1039',
        message: 'Analyzer omitted the defining modeling unit.',
        path: _relativeTo(rootPath, definingPath),
      );
      return ModelingCompilation(
        workspace: ModelingWorkspaceIr(root: rootPath, libraries: const []),
        diagnostics: <ModelingDiagnostic>[diagnostic],
      );
    }
    final libraryPath = _relativeTo(rootPath, definingPath);
    final outputPath =
        libraryPath.substring(0, libraryPath.length - '.dart'.length) +
        '.dartitect.g.dart';
    final expectedPart = _basename(outputPath);
    final diagnostics = <ModelingDiagnostic>[];
    final candidates =
        <({ResolvedUnitResult unit, ClassDeclaration declaration})>[];
    for (final unit in result.units) {
      for (final declaration
          in unit.unit.declarations.whereType<ClassDeclaration>().where(
            hasLexicalModelingAnnotation,
          )) {
        candidates.add((unit: unit, declaration: declaration));
      }
    }
    candidates.sort((left, right) {
      final byPath = left.unit.path.compareTo(right.unit.path);
      if (byPath != 0) return byPath;
      return left.declaration.offset.compareTo(right.declaration.offset);
    });
    final partDiagnostic = inspectLibraryPart(
      definingUnit: defining.unit,
      definingPath: libraryPath,
      lineInfo: defining.lineInfo,
      hasModels: candidates.isNotEmpty,
    );
    if (partDiagnostic != null) {
      diagnostics.add(partDiagnostic);
    }

    final models = <ModelingModelIr>[];
    for (final candidate in candidates) {
      final classResult = inspectClass(
        declaration: candidate.declaration,
        sourcePath: _relativeTo(rootPath, candidate.unit.path),
        lineInfo: candidate.unit.lineInfo,
      );
      diagnostics.addAll(classResult.diagnostics);
      if (classResult.model case final model?) models.add(model);
    }
    _appendAnalyzerDiagnostics(
      result,
      rootPath: rootPath,
      outputName: expectedPart,
      modelNames: <String>{for (final model in models) model.name},
      diagnostics: diagnostics,
    );
    _sortDiagnostics(diagnostics);
    models.sort((left, right) {
      final byPath = left.sourcePath.compareTo(right.sourcePath);
      return byPath != 0 ? byPath : left.name.compareTo(right.name);
    });
    final hasErrors = diagnostics.any(
      (diagnostic) => diagnostic.severity == ModelingDiagnosticSeverity.error,
    );
    return ModelingCompilation(
      workspace: ModelingWorkspaceIr(
        root: rootPath.replaceAll('\\', '/'),
        libraries: hasErrors || models.isEmpty
            ? const <ModelingLibraryIr>[]
            : <ModelingLibraryIr>[
                ModelingLibraryIr(
                  uri: result.element.uri.toString(),
                  path: libraryPath,
                  outputPath: outputPath,
                  models: List<ModelingModelIr>.unmodifiable(models),
                ),
              ],
      ),
      diagnostics: List<ModelingDiagnostic>.unmodifiable(diagnostics),
    );
  }

  /// Applies the same semantic class validation used by workspace compilation.
  static ModelingClassCompilation inspectClass({
    required ClassDeclaration declaration,
    required String sourcePath,
    required LineInfo lineInfo,
  }) {
    final diagnostics = <ModelingDiagnostic>[];
    void reject(String rule, String message, [AstNode? node, String? fixId]) {
      diagnostics.add(
        _diagnostic(
          rule: rule,
          message: message,
          path: sourcePath,
          node: node ?? declaration,
          lineInfo: lineInfo,
          fixId: fixId,
        ),
      );
    }

    final recognized =
        <({ModelingCapability capability, Annotation annotation})>[];
    for (final annotation in declaration.metadata) {
      final lexicalName = annotation.name.toSource().split('.').last;
      final capability = _capabilityForAnnotation(annotation);
      if (capability != null) {
        recognized.add((capability: capability, annotation: annotation));
      } else if (_annotationNames.contains(lexicalName)) {
        reject(
          'DT1032',
          '$lexicalName must resolve to package:dartitect_modeling.',
          annotation,
        );
      }
    }
    if (recognized.isEmpty) {
      return ModelingClassCompilation(
        model: null,
        diagnostics: List<ModelingDiagnostic>.unmodifiable(diagnostics),
      );
    }
    final capabilities = <ModelingCapability>{
      for (final entry in recognized) entry.capability,
    };
    final classElement = declaration.declaredFragment?.element;
    if (classElement == null) {
      reject('DT1039', 'Analyzer did not resolve the model class element.');
      return ModelingClassCompilation(
        model: null,
        diagnostics: List<ModelingDiagnostic>.unmodifiable(diagnostics),
      );
    }
    if (!classElement.isFinal || classElement.isAbstract) {
      reject('DT1033', 'Modeling classes must be concrete final classes.');
    }
    final primaryElement = classElement.primaryConstructor;
    final primaryNode = switch (declaration.namePart) {
      final PrimaryConstructorDeclaration value => value,
      _ => null,
    };
    if (primaryElement == null ||
        !primaryElement.isPrimary ||
        primaryNode == null) {
      final edits = primaryConstructorSourceEdits(declaration);
      reject(
        'DT1030',
        'Modeling classes must declare an unnamed primary constructor.',
        declaration.namePart,
        edits == null ? null : 'model.migrate.primary',
      );
    } else if (primaryNode.constructorName != null) {
      reject(
        'DT1035',
        'Model primary constructors must be unnamed.',
        primaryNode,
      );
    }

    if (capabilities.contains(ModelingCapability.value)) {
      final supertype = classElement.supertype;
      final isValueEquality =
          supertype != null &&
          supertype.element.name == 'ValueEquality' &&
          supertype.element.library.uri.toString() ==
              'package:dartitect/src/value_equality.dart';
      if (!isValueEquality) {
        reject(
          'DT1035',
          'DartitectValue classes must extend the Dartitect ValueEquality element.',
        );
      }
      final typeUse = classElement.typeParameters.isEmpty
          ? ''
          : '<${classElement.typeParameters.map((parameter) => parameter.name).join(', ')}>';
      final expectedMixin = '_\$${classElement.name}Dartitect$typeUse';
      final mixins =
          declaration.withClause?.mixinTypes
              .map((type) => type.toSource().replaceAll(RegExp(r'\s+'), ''))
              .toSet() ??
          const <String>{};
      if (!mixins.contains(expectedMixin.replaceAll(' ', ''))) {
        reject('DT1035', 'The class must mix in $expectedMixin.');
      }
    }

    final fields = <ModelingFieldIr>[];
    final fieldTypes = <String, DartType>{};
    if (primaryNode != null && primaryElement != null) {
      for (final parameter in primaryNode.formalParameters.parameters) {
        final parameterName = parameter.name?.lexeme;
        final parameterElement = parameter.declaredFragment?.element;
        if (parameter is! RegularFormalParameter ||
            parameter.finalKeyword == null ||
            !parameter.isNamed ||
            parameterName == null ||
            parameter.type == null ||
            parameterElement == null) {
          reject(
            'DT1036',
            'Model fields must be typed, named, final primary parameters.',
            parameter,
          );
          continue;
        }
        if (parameterName.startsWith('_')) {
          reject('DT1036', 'Model fields must be public.', parameter);
          continue;
        }
        final dartType = parameterElement.type;
        fieldTypes[parameterName] = dartType;
        if (_isMutableCollection(dartType)) {
          reject(
            'DT1037',
            'Mutable collection interfaces are not valid model fields.',
            parameter,
          );
        }
        final metadata = _fieldMetadata(parameter, reject);
        fields.add(
          ModelingFieldIr(
            name: parameterName,
            type: _typeIr(dartType),
            jsonName: metadata.jsonName,
            targetName: metadata.targetName,
            decodeHook: metadata.decodeHook,
            encodeHook: metadata.encodeHook,
            mapFromHook: metadata.mapFromHook,
            mapToHook: metadata.mapToHook,
            isRequiredNamed: parameter.isRequiredNamed,
            hasDefault: parameter.defaultClause != null,
            defaultCode: parameter.defaultClause?.value.toSource(),
          ),
        );
      }
    }
    if (fields.isEmpty) {
      reject('DT1036', 'A modeling class must declare at least one field.');
    }
    for (final member in declaration.body.members) {
      if (member is FieldDeclaration && member.isStatic) continue;
      if (member is FieldDeclaration || member is ConstructorDeclaration) {
        reject(
          'DT1041',
          'Instance fields and constructors must be owned by the primary constructor.',
          member,
        );
      }
    }
    final generatedNames = <String>{for (final field in fields) field.name};
    for (final field in fields.where((field) => field.type.nullable)) {
      final clearName = _clearName(field.name);
      if (!generatedNames.add(clearName)) {
        reject(
          'DT1038',
          'Generated nullable clear flag `$clearName` collides with a field.',
        );
      }
    }

    final jsonAnnotations = recognized
        .where((entry) => entry.capability == ModelingCapability.json)
        .map((entry) => entry.annotation)
        .toList(growable: false);
    if (jsonAnnotations.length > 1) {
      reject('DT1040', 'A model may declare DartitectJson only once.');
    }
    if (jsonAnnotations.isNotEmpty) {
      final jsonNames = <String>{};
      final typeParameters = <String>{
        for (final parameter in classElement.typeParameters)
          parameter.name ?? '',
      };
      for (final field in fields) {
        final jsonName = field.jsonName ?? field.name;
        if (jsonName.isEmpty || !jsonNames.add(jsonName)) {
          reject('DT1040', 'JSON field names must be non-empty and unique.');
        }
        final hasDecodeHook = field.decodeHook != null;
        final hasEncodeHook = field.encodeHook != null;
        if (hasDecodeHook != hasEncodeHook ||
            !_validHookName(field.decodeHook) ||
            !_validHookName(field.encodeHook)) {
          reject(
            'DT1043',
            'JSON hooks must be a valid explicit decoder/encoder pair.',
          );
          continue;
        }
        if (hasDecodeHook &&
            !_validJsonHookPair(
              classElement.library,
              fieldTypes[field.name]!,
              field.decodeHook!,
              field.encodeHook!,
            )) {
          reject(
            'DT1043',
            'JSON hooks must be consumer-owned static functions with exact codec signatures.',
          );
          continue;
        }
        if (!hasDecodeHook &&
            !_supportsGeneratedJson(field.type, typeParameters)) {
          reject(
            'DT1043',
            'This JSON field type requires explicit decoder and encoder hooks.',
          );
        }
      }
    }
    final projectionAnnotations = recognized
        .where((entry) => entry.capability == ModelingCapability.projection)
        .map((entry) => entry.annotation)
        .toList(growable: false);
    final mapperAnnotations = recognized
        .where((entry) => entry.capability == ModelingCapability.mapper)
        .map((entry) => entry.annotation)
        .toList(growable: false);
    final projections = <ModelingProjectionIr>[];
    final projectionNames = <String>{};
    for (final annotation in projectionAnnotations) {
      final name = _stringField(annotation, 'name') ?? 'default';
      if (name.isEmpty || !projectionNames.add(name)) {
        reject(
          'DT1040',
          'Projection names must be non-empty and unique.',
          annotation,
        );
        continue;
      }
      projections.add(
        ModelingProjectionIr(
          name: name,
          fields: <String>[for (final field in fields) field.name],
        ),
      );
    }
    final mappers = <ModelingMapperIr>[];
    for (final annotation in mapperAnnotations) {
      final target = annotation.elementAnnotation
          ?.computeConstantValue()
          ?.getField('target')
          ?.toTypeValue();
      if (target == null) {
        reject(
          'DT1040',
          'DartitectMapper requires a resolved target type.',
          annotation,
        );
        continue;
      }
      mappers.add(
        ModelingMapperIr(
          targetType: _typeIr(target),
          bidirectional: _boolField(annotation, 'bidirectional') ?? false,
          decisions: const <ModelingCompatibilityDecisionIr>[],
        ),
      );
    }
    final beforeModel = diagnostics.where(
      (diagnostic) => diagnostic.severity == ModelingDiagnosticSeverity.error,
    );
    if (beforeModel.isNotEmpty) {
      _sortDiagnostics(diagnostics);
      return ModelingClassCompilation(
        model: null,
        diagnostics: List<ModelingDiagnostic>.unmodifiable(diagnostics),
      );
    }
    final model = ModelingModelIr(
      name: classElement.name ?? declaration.namePart.typeName.lexeme,
      sourcePath: sourcePath,
      typeParameters: <ModelingTypeParameterIr>[
        for (final parameter in classElement.typeParameters)
          ModelingTypeParameterIr(
            name: parameter.name ?? '',
            bound: parameter.bound == null ? null : _typeIr(parameter.bound!),
          ),
      ],
      fields: List<ModelingFieldIr>.unmodifiable(fields),
      capabilities: Set<ModelingCapability>.unmodifiable(capabilities),
      json: jsonAnnotations.isEmpty
          ? null
          : ModelingJsonIr(
              rejectUnknownKeys:
                  (_enumField(jsonAnnotations.single, 'unknownKeys') ??
                      'reject') ==
                  'reject',
              trusted: _boolField(jsonAnnotations.single, 'trusted') ?? false,
            ),
      projections: List<ModelingProjectionIr>.unmodifiable(projections),
      mappers: List<ModelingMapperIr>.unmodifiable(mappers),
      isConst: primaryElement?.isConst ?? false,
    );
    return ModelingClassCompilation(
      model: model,
      diagnostics: List<ModelingDiagnostic>.unmodifiable(diagnostics),
    );
  }

  /// Validates deterministic generated-part ownership for one defining unit.
  static ModelingDiagnostic? inspectLibraryPart({
    required CompilationUnit definingUnit,
    required String definingPath,
    required LineInfo lineInfo,
    required bool hasModels,
  }) {
    if (!hasModels) return null;
    final expectedPart =
        '${_basename(definingPath).substring(0, _basename(definingPath).length - '.dart'.length)}.dartitect.g.dart';
    final partCount = definingUnit.directives
        .whereType<PartDirective>()
        .map((directive) => directive.uri.stringValue)
        .where((uri) => uri == expectedPart)
        .length;
    if (partCount == 1) return null;
    return _diagnostic(
      rule: 'DT1034',
      message:
          "The defining library must declare exactly `part '$expectedPart';`.",
      path: definingPath,
      node: definingUnit,
      lineInfo: lineInfo,
    );
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

  String _relative(String path) => _relativeTo(root.path, path);
}

/// Whether [declaration] has a lexically relevant modeling annotation.
bool hasLexicalModelingAnnotation(ClassDeclaration declaration) => declaration
    .metadata
    .map((annotation) => annotation.name.toSource().split('.').last)
    .any(_annotationNames.contains);

ModelingCapability? _capabilityForAnnotation(Annotation annotation) {
  final element = annotation.element;
  if (element?.library?.uri.toString() !=
      'package:dartitect_modeling/src/annotations.dart') {
    return null;
  }
  return switch (element?.enclosingElement?.displayName) {
    'DartitectValue' => ModelingCapability.value,
    'DartitectJson' => ModelingCapability.json,
    'DartitectProjection' => ModelingCapability.projection,
    'DartitectMapper' => ModelingCapability.mapper,
    _ => null,
  };
}

_FieldMetadata _fieldMetadata(
  FormalParameter parameter,
  void Function(String, String, [AstNode?, String?]) reject,
) {
  final annotations = parameter.metadata
      .where((annotation) {
        final element = annotation.element;
        return element?.enclosingElement?.displayName == 'DartitectField' &&
            element?.library?.uri.toString() ==
                'package:dartitect_modeling/src/annotations.dart';
      })
      .toList(growable: false);
  if (annotations.length > 1) {
    reject(
      'DT1040',
      'A field may declare DartitectField only once.',
      parameter,
    );
  }
  final annotation = annotations.firstOrNull;
  return _FieldMetadata(
    jsonName: _stringField(annotation, 'jsonName'),
    targetName: _stringField(annotation, 'targetName'),
    decodeHook: _stringField(annotation, 'decodeWith'),
    encodeHook: _stringField(annotation, 'encodeWith'),
    mapFromHook: _stringField(annotation, 'mapFromWith'),
    mapToHook: _stringField(annotation, 'mapToWith'),
  );
}

String? _stringField(Annotation? annotation, String field) => annotation
    ?.elementAnnotation
    ?.computeConstantValue()
    ?.getField(field)
    ?.toStringValue();

bool? _boolField(Annotation annotation, String field) => annotation
    .elementAnnotation
    ?.computeConstantValue()
    ?.getField(field)
    ?.toBoolValue();

String? _enumField(Annotation annotation, String field) => annotation
    .elementAnnotation
    ?.computeConstantValue()
    ?.getField(field)
    ?.getField('_name')
    ?.toStringValue();

ModelingTypeIr _typeIr(DartType type) {
  final arguments = <ModelingTypeIr>[];
  if (type is ParameterizedType) {
    arguments.addAll(type.typeArguments.map(_typeIr));
  } else if (type is RecordType) {
    arguments.addAll(type.positionalFields.map((field) => _typeIr(field.type)));
    arguments.addAll(type.namedFields.map((field) => _typeIr(field.type)));
  }
  final libraryUri = switch (type) {
    final InterfaceType value => value.element.library.uri.toString(),
    final TypeParameterType value =>
      value.element.library?.uri.toString() ?? '',
    _ => '',
  };
  return ModelingTypeIr(
    displayName: type.getDisplayString(),
    declarationName: switch (type) {
      final InterfaceType value => value.element.name ?? '',
      final TypeParameterType value => value.element.name ?? '',
      final DynamicType _ => 'dynamic',
      final VoidType _ => 'void',
      _ => '',
    },
    libraryUri: libraryUri,
    nullable: type.nullabilitySuffix == NullabilitySuffix.question,
    typeArguments: List<ModelingTypeIr>.unmodifiable(arguments),
    isRecord: type is RecordType,
  );
}

bool _validHookName(String? name) {
  if (name == null) return true;
  return RegExp(r'^_?[A-Za-z][A-Za-z0-9_]*(\._?[A-Za-z][A-Za-z0-9_]*)?$')
      .hasMatch(name);
}

bool _validJsonHookPair(
  LibraryElement library,
  DartType fieldType,
  String decodeName,
  String encodeName,
) {
  final decode = _lookupHook(library, decodeName);
  final encode = _lookupHook(library, encodeName);
  if (decode == null || encode == null) return false;
  return _validHookParameters(
        decode,
        first: (type) => _isObjectQuestion(type),
      ) &&
      _isJsonResult(
        decode.returnType,
        (type) => _sameType(library, type, fieldType),
      ) &&
      _validHookParameters(
        encode,
        first: (type) => _sameType(library, type, fieldType),
      ) &&
      _isJsonResult(encode.returnType, _isObjectQuestion);
}

ExecutableElement? _lookupHook(LibraryElement library, String name) {
  final parts = name.split('.');
  if (parts.length == 1) {
    return library.topLevelFunctions
        .where((function) => function.name == parts.single)
        .firstOrNull;
  }
  if (parts.length != 2) return null;
  final owner = library.classes
      .where((element) => element.name == parts.first)
      .firstOrNull;
  return owner?.methods
      .where((method) => method.name == parts.last && method.isStatic)
      .firstOrNull;
}

bool _validHookParameters(
  ExecutableElement hook, {
  required bool Function(DartType type) first,
}) {
  final parameters = hook.formalParameters;
  return parameters.length == 2 &&
      parameters.every((parameter) => parameter.isRequiredPositional) &&
      first(parameters.first.type) &&
      _isInterface(
        parameters.last.type,
        'DartitectJsonPath',
        'package:dartitect_modeling/src/json_codec.dart',
      );
}

bool _isJsonResult(DartType type, bool Function(DartType type) valueType) {
  final erased = type.extensionTypeErasure;
  return erased is InterfaceType &&
      erased.element.name == 'Result' &&
      erased.element.library.uri.toString() ==
          'package:dartitect/src/result.dart' &&
      erased.typeArguments.length == 2 &&
      valueType(erased.typeArguments.first) &&
      _isInterface(
        erased.typeArguments.last,
        'DartitectJsonFailure',
        'package:dartitect_modeling/src/json_codec.dart',
      );
}

bool _sameType(LibraryElement library, DartType left, DartType right) =>
    library.typeSystem.isSubtypeOf(left, right) &&
    library.typeSystem.isSubtypeOf(right, left);

bool _isObjectQuestion(DartType type) =>
    _isInterface(type, 'Object', 'dart:core') &&
    type.nullabilitySuffix == NullabilitySuffix.question;

bool _isInterface(DartType type, String name, String libraryUri) {
  final erased = type.extensionTypeErasure;
  return erased is InterfaceType &&
      erased.element.name == name &&
      erased.element.library.uri.toString() == libraryUri;
}

bool _supportsGeneratedJson(ModelingTypeIr type, Set<String> typeParameters) {
  if (typeParameters.contains(type.declarationName)) return true;
  if (type.libraryUri == 'dart:core' &&
      const <String>{
        'String',
        'bool',
        'int',
        'num',
        'double',
        'Null',
      }.contains(type.declarationName)) {
    return true;
  }
  if (type.declarationName == 'dynamic' || type.displayName == 'Object?') {
    return true;
  }
  if (type.libraryUri !=
      'package:dartitect_modeling/src/value_collections.dart') {
    return false;
  }
  return switch (type.declarationName) {
    'ImmutableValueList' || 'ImmutableValueSet' =>
      type.typeArguments.length == 1 &&
          _supportsGeneratedJson(type.typeArguments.single, typeParameters),
    'ImmutableValueMap' =>
      type.typeArguments.length == 2 &&
          type.typeArguments.first.libraryUri == 'dart:core' &&
          type.typeArguments.first.declarationName == 'String' &&
          _supportsGeneratedJson(type.typeArguments.last, typeParameters),
    _ => false,
  };
}

bool _isMutableCollection(DartType type, [Set<DartType>? active]) {
  active ??= HashSet<DartType>.identity();
  if (!active.add(type)) return false;
  try {
    return _isMutableCollectionActive(type, active);
  } finally {
    active.remove(type);
  }
}

bool _isMutableCollectionActive(DartType type, Set<DartType> active) {
  final erased = type.extensionTypeErasure;
  const names = <String>{
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
  if (erased is InterfaceType && names.contains(erased.element.name)) {
    return true;
  }
  if (type is TypeParameterType && _isMutableCollection(type.bound, active)) {
    return true;
  }
  if (type is ParameterizedType &&
      type.typeArguments.any(
        (argument) => _isMutableCollection(argument, active),
      )) {
    return true;
  }
  if (type is RecordType &&
      <DartType>[
        ...type.positionalFields.map((field) => field.type),
        ...type.namedFields.map((field) => field.type),
      ].any((field) => _isMutableCollection(field, active))) {
    return true;
  }
  return false;
}

void _appendAnalyzerDiagnostics(
  ResolvedLibraryResult result, {
  required String rootPath,
  required String outputName,
  required Set<String> modelNames,
  required List<ModelingDiagnostic> diagnostics,
}) {
  for (final unit in result.units) {
    if (_basename(unit.path) == outputName) continue;
    for (final diagnostic in unit.diagnostics) {
      if (diagnostic.severity != Severity.error) continue;
      final diagnosticEnd = diagnostic.offset + diagnostic.length;
      final diagnosticSource =
          diagnostic.offset >= 0 && diagnosticEnd <= unit.content.length
          ? unit.content.substring(diagnostic.offset, diagnosticEnd)
          : '';
      final expectedBootstrap =
          diagnostic.message.contains(outputName) ||
          modelNames.any(
            (name) =>
                diagnostic.message.contains('_\$${name}Dartitect') ||
                diagnosticSource.contains('_\$${name}Dartitect'),
          ) ||
          diagnostic.diagnosticCode.lowerCaseName ==
                  'non_abstract_class_inherits_abstract_member' &&
              diagnostic.message.contains('ValueEquality.equalityFields');
      if (expectedBootstrap) continue;
      diagnostics.add(
        _diagnostic(
          rule: 'DT1042',
          message: 'Analyzer: ${diagnostic.message}',
          path: _relativeTo(rootPath, unit.path),
          lineInfo: unit.lineInfo,
          offset: diagnostic.offset,
          length: diagnostic.length,
        ),
      );
    }
  }
}

ModelingDiagnostic _diagnostic({
  required String rule,
  required String message,
  required String path,
  ModelingDiagnosticSeverity severity = ModelingDiagnosticSeverity.error,
  AstNode? node,
  LineInfo? lineInfo,
  int? offset,
  int? length,
  String? fixId,
}) {
  final sourceOffset = offset ?? node?.offset;
  return ModelingDiagnostic(
    rule: rule,
    severity: severity,
    message: message,
    path: path,
    line: sourceOffset == null || lineInfo == null
        ? null
        : lineInfo.getLocation(sourceOffset).lineNumber,
    fixId: fixId,
    sourceOffset: sourceOffset,
    sourceLength: length ?? node?.length,
  );
}

void _sortDiagnostics(List<ModelingDiagnostic> diagnostics) {
  diagnostics.sort((left, right) {
    final byPath = left.path.compareTo(right.path);
    if (byPath != 0) return byPath;
    final byLine = (left.line ?? 0).compareTo(right.line ?? 0);
    if (byLine != 0) return byLine;
    return left.rule.compareTo(right.rule);
  });
}

String _relativeTo(String rootPath, String path) {
  final root = Directory(rootPath).absolute.path;
  final absolute = File(path).absolute.path;
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  if (!absolute.startsWith(prefix)) return absolute.replaceAll('\\', '/');
  return absolute.substring(prefix.length).replaceAll('\\', '/');
}

String _clearName(String field) =>
    'clear${field[0].toUpperCase()}${field.substring(1)}';

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

const Set<String> _annotationNames = <String>{
  'DartitectValue',
  'DartitectJson',
  'DartitectProjection',
  'DartitectMapper',
};

final class _FieldMetadata {
  const _FieldMetadata({
    this.jsonName,
    this.targetName,
    this.decodeHook,
    this.encodeHook,
    this.mapFromHook,
    this.mapToHook,
  });

  final String? jsonName;
  final String? targetName;
  final String? decodeHook;
  final String? encodeHook;
  final String? mapFromHook;
  final String? mapToHook;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
