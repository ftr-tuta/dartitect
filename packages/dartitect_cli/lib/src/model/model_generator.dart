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
          path: '.dartitect/generation/modeling/journal.json',
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
    'schemaVersion': DartitectGenerationVersions.report,
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
      namespace: GenerationNamespace.modeling,
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
    final engine = GenerationEngine(
      root,
      namespace: GenerationNamespace.modeling,
      faultInjector: _faultInjector,
    );
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
          rendererVersion: DartitectGenerationVersions.modelRenderer,
          semanticSchemaVersion:
              DartitectGenerationVersions.modelingSemanticSchema,
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
    'schemaVersion': 4,
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
                if (field.jsonName != null) 'jsonName': field.jsonName,
                if (field.decodeHook != null) 'decodeHook': field.decodeHook,
                if (field.encodeHook != null) 'encodeHook': field.encodeHook,
                if (field.targetName != null) 'targetName': field.targetName,
                if (field.mapToHook != null) 'mapToHook': field.mapToHook,
                if (field.mapFromHook != null) 'mapFromHook': field.mapFromHook,
              },
          ],
          if (model.json case final json?)
            'json': <String, Object?>{
              'rejectUnknownKeys': json.rejectUnknownKeys,
              'trusted': json.trusted,
            },
          'projections': <Object?>[
            for (final projection in model.projections)
              <String, Object?>{
                'name': projection.name,
                'fields': projection.fields,
              },
          ],
          'mappers': <Object?>[
            for (final mapper in model.mappers)
              <String, Object?>{
                'target': mapper.targetType.displayName,
                'targetLibrary': mapper.targetType.libraryUri,
                'targetReference': mapper.targetReference,
                'bidirectional': mapper.bidirectional,
                'decisions': <Object?>[
                  for (final decision in mapper.decisions)
                    <String, Object?>{
                      'sourceField': decision.sourceField,
                      'targetField': decision.targetField,
                      'sourceType': decision.sourceType.displayName,
                      'targetType': decision.targetType.displayName,
                      'compatibility': decision.compatibility.name,
                      'reason': decision.reason,
                      if (decision.mapToHook != null)
                        'mapToHook': decision.mapToHook,
                      if (decision.mapFromHook != null)
                        'mapFromHook': decision.mapFromHook,
                    },
                ],
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
    ..writeln(
      '// Dartitect model renderer '
      '${DartitectGenerationVersions.modelRenderer}, semantic schema '
      '${DartitectGenerationVersions.modelingSemanticSchema}.',
    )
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
  for (final model in library.models.where(
    (model) => model.capabilities.contains(ModelingCapability.json),
  )) {
    _renderJsonCodec(buffer, model);
  }
  for (final model in library.models.where(
    (model) => model.capabilities.contains(ModelingCapability.projection),
  )) {
    _renderProjections(buffer, model);
  }
  for (final model in library.models.where(
    (model) => model.capabilities.contains(ModelingCapability.mapper),
  )) {
    for (final mapper in model.mappers) {
      _renderMapper(buffer, model, mapper);
    }
  }
  return DartFormatter(
    languageVersion: DartFormatter.latestLanguageVersion,
    lineEnding: '\n',
  ).format(buffer.toString(), uri: partName);
}

void _renderProjections(StringBuffer buffer, ModelingModelIr model) {
  final declaration = _typeParameterDeclaration(model);
  final use = _typeParameterUse(model);
  final fieldsName = '${model.name}DartitectFields';
  buffer
    ..writeln()
    ..writeln('/// Generated typed descriptors and lenses for [${model.name}].')
    ..writeln('final class $fieldsName$declaration {')
    ..writeln('  /// Creates the generated field registry.')
    ..writeln('  const $fieldsName();');
  for (final field in model.fields) {
    buffer
      ..writeln()
      ..writeln('  /// Descriptor and immutable lens for `${field.name}`.')
      ..writeln(
        '  DartitectLens<${model.name}$use, ${field.type.displayName}> '
        'get ${field.name} => DartitectLens<${model.name}$use, ${field.type.displayName}>(',
      )
      ..writeln(
        '    descriptor: DartitectFieldDescriptor<${model.name}$use, ${field.type.displayName}>(',
      )
      ..writeln("      name: '${field.name}',")
      ..writeln('      select: (model) => model.${field.name},')
      ..writeln('    ),')
      ..writeln('    write: (model, value) => ${model.name}$use(');
    for (final constructorField in model.fields) {
      final value = constructorField.name == field.name
          ? 'value'
          : 'model.${constructorField.name}';
      buffer.writeln('      ${constructorField.name}: $value,');
    }
    buffer
      ..writeln('    ),')
      ..writeln('  );');
  }
  buffer.writeln('}');
  if (model.typeParameters.isEmpty) {
    buffer
      ..writeln()
      ..writeln('/// Shared generated field registry for [${model.name}].')
      ..writeln(
        'const ${_lowerFirst(model.name)}DartitectFields = $fieldsName();',
      );
  }
  final byName = <String, ModelingFieldIr>{
    for (final field in model.fields) field.name: field,
  };
  for (final projection in model.projections) {
    final projectionSuffix = _upperCamel(projection.name);
    final projectionName =
        '${model.name}${projectionSuffix}DartitectProjection';
    final selectorName = 'select${model.name}$projectionSuffix';
    final record = projection.fields
        .map((name) => '${byName[name]!.type.displayName} $name')
        .join(', ');
    final values = projection.fields
        .map((name) => '$name: model.$name')
        .join(', ');
    buffer
      ..writeln()
      ..writeln(
        '/// Generated `${projection.name}` record projection for [${model.name}].',
      )
      ..writeln('typedef $projectionName$declaration = ({$record});')
      ..writeln()
      ..writeln('/// Selects the generated `${projection.name}` projection.')
      ..writeln(
        '$projectionName$use $selectorName$declaration('
        '${model.name}$use model) => ($values);',
      );
  }
}

void _renderMapper(
  StringBuffer buffer,
  ModelingModelIr model,
  ModelingMapperIr mapper,
) {
  final declaration = _typeParameterDeclaration(model);
  final use = _typeParameterUse(model);
  final target = mapper.targetReference;
  final mapperName =
      '${model.name}To${mapper.targetType.declarationName}DartitectMapper';
  final contract = mapper.bidirectional
      ? 'DartitectBidirectionalBoundaryMapper'
      : 'DartitectBoundaryMapper';
  buffer
    ..writeln()
    ..writeln(
      '/// Generated pure boundary mapper from [${model.name}] to [$target].',
    )
    ..writeln(
      'final class $mapperName$declaration '
      'implements $contract<${model.name}$use, $target> {',
    )
    ..writeln('  /// Creates the generated mapper.')
    ..writeln('  const $mapperName();')
    ..writeln()
    ..writeln('  @override')
    ..writeln(
      '  Result<$target, DartitectMappingFailure> '
      'toTarget(${model.name}$use source) =>',
    )
    ..writeln('      ${_mappingChain(model, mapper, forward: true)};');
  if (mapper.bidirectional) {
    buffer
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        '  Result<${model.name}$use, DartitectMappingFailure> '
        'fromTarget($target target) =>',
      )
      ..writeln('      ${_mappingChain(model, mapper, forward: false)};');
  }
  buffer.writeln('}');
  if (model.typeParameters.isEmpty) {
    buffer
      ..writeln()
      ..writeln(
        '/// Shared generated mapper from [${model.name}] to [$target].',
      )
      ..writeln('const ${_lowerFirst(mapperName)} = $mapperName();');
  }
}

String _mappingChain(
  ModelingModelIr model,
  ModelingMapperIr mapper, {
  required bool forward,
  int index = 0,
}) {
  if (index == mapper.decisions.length) {
    if (forward) {
      final arguments = mapper.decisions
          .map(
            (decision) =>
                '${decision.targetField}: _${decision.sourceField}Mapped',
          )
          .join(', ');
      return 'Ok<${mapper.targetReference}>('
          '${mapper.targetReference}($arguments))';
    }
    final use = _typeParameterUse(model);
    final arguments = mapper.decisions
        .map(
          (decision) =>
              '${decision.sourceField}: _${decision.sourceField}Mapped',
        )
        .join(', ');
    return 'Ok<${model.name}$use>(${model.name}$use($arguments))';
  }
  final decision = mapper.decisions[index];
  final input = forward
      ? 'source.${decision.sourceField}'
      : 'target.${decision.targetField}';
  final outputType = forward
      ? decision.targetType.displayName
      : decision.sourceType.displayName;
  final hook = forward ? decision.mapToHook : decision.mapFromHook;
  final conversion = hook == null
      ? 'DartitectMappingResults.success<$outputType>($input)'
      : '$hook($input, const DartitectMappingPath('
            "sourceField: '${decision.sourceField}', "
            "targetField: '${decision.targetField}'))";
  return '$conversion.flatMap((_${decision.sourceField}Mapped) => '
      '${_mappingChain(model, mapper, forward: forward, index: index + 1)})';
}

void _renderJsonCodec(StringBuffer buffer, ModelingModelIr model) {
  final declaration = _typeParameterDeclaration(model);
  final use = _typeParameterUse(model);
  final codecName = '${model.name}DartitectJsonCodec';
  final trustedInitializer = model.json?.trusted ?? false
      ? ' : super(defaultLimits: const DartitectJsonLimits.trusted())'
      : '';
  buffer
    ..writeln()
    ..writeln('/// Generated JSON codec for [${model.name}].')
    ..writeln(
      'final class $codecName$declaration '
      'extends DartitectJsonCodec<${model.name}$use> {',
    );
  if (model.typeParameters.isEmpty) {
    buffer
      ..writeln('  /// Creates the generated codec.')
      ..writeln('  const $codecName()$trustedInitializer;');
  } else {
    buffer
      ..writeln(
        '  /// Creates the generated codec with explicit generic codecs.',
      )
      ..writeln('  const $codecName({')
      ..writeAll(
        model.typeParameters.map(
          (parameter) =>
              '    required this.${_typeParameterCodecName(parameter)},\n',
        ),
      )
      ..writeln('  })$trustedInitializer;')
      ..writeln();
    for (final parameter in model.typeParameters) {
      buffer
        ..writeln('  /// Codec for `${parameter.name}` fields.')
        ..writeln(
          '  final DartitectJsonCodec<${parameter.name}> '
          '${_typeParameterCodecName(parameter)};',
        );
    }
  }
  final allowedKeys = model.fields
      .map((field) => _dartStringLiteral(field.jsonName ?? field.name))
      .join(', ');
  final requiredKeys = model.fields
      .where((field) => field.isRequiredNamed)
      .map((field) => _dartStringLiteral(field.jsonName ?? field.name))
      .join(', ');
  buffer
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Result<${model.name}$use, DartitectJsonFailure> decodeValue(')
    ..writeln('    Object? input,')
    ..writeln('    DartitectJsonPath path,')
    ..writeln('  ) => DartitectJsonObjectSupport.decodeObject(')
    ..writeln('    input,')
    ..writeln('    path,')
    ..writeln('    allowedKeys: const <String>{$allowedKeys},')
    ..writeln('    requiredKeys: const <String>{$requiredKeys},')
    ..writeln(
      '    rejectUnknownKeys: ${model.json?.rejectUnknownKeys ?? true},',
    )
    ..writeln('  ).flatMap(')
    ..writeln('    (object) => ${_jsonDecodeChain(model, 0)},')
    ..writeln('  );')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Result<Object?, DartitectJsonFailure> encodeValue(')
    ..writeln('    ${model.name}$use value,')
    ..writeln('    DartitectJsonPath path,')
    ..writeln('  ) => ${_jsonEncodeChain(model, 0)};')
    ..writeln('}');
  if (model.typeParameters.isEmpty) {
    buffer
      ..writeln()
      ..writeln('/// Shared generated JSON codec for [${model.name}].')
      ..writeln(
        'const ${_lowerFirst(model.name)}DartitectJsonCodec = '
        '$codecName();',
      );
  }
}

String _jsonDecodeChain(ModelingModelIr model, int index) {
  final use = _typeParameterUse(model);
  if (index == model.fields.length) {
    final arguments = model.fields
        .map((field) => '${field.name}: _${field.name}Json')
        .join(', ');
    return 'Ok<${model.name}$use>(${model.name}$use($arguments))';
  }
  final field = model.fields[index];
  final key = _dartStringLiteral(field.jsonName ?? field.name);
  final codec = _jsonCodecExpression(model, field);
  final decoded = '$codec.decodeValue(object[$key], path.key($key))';
  final expression = field.isRequiredNamed
      ? decoded
      : "object.containsKey($key) ? $decoded : Ok<${field.type.displayName}>(${field.defaultCode ?? 'null'})";
  return '($expression).flatMap((_${field.name}Json) => '
      '${_jsonDecodeChain(model, index + 1)})';
}

String _jsonEncodeChain(ModelingModelIr model, int index) {
  if (index == model.fields.length) {
    final entries = model.fields
        .map(
          (field) =>
              '${_dartStringLiteral(field.jsonName ?? field.name)}: '
              '_${field.name}Json',
        )
        .join(', ');
    return 'Ok<Object?>(<String, Object?>{$entries})';
  }
  final field = model.fields[index];
  final key = _dartStringLiteral(field.jsonName ?? field.name);
  final codec = _jsonCodecExpression(model, field);
  return '$codec.encodeValue(value.${field.name}, path.key($key)).flatMap('
      '(_${field.name}Json) => ${_jsonEncodeChain(model, index + 1)})';
}

String _jsonCodecExpression(ModelingModelIr model, ModelingFieldIr field) {
  final decodeHook = field.decodeHook;
  final encodeHook = field.encodeHook;
  if (decodeHook != null && encodeHook != null) {
    return 'DartitectHookJsonCodec<${field.type.displayName}>('
        'decode: $decodeHook, encode: $encodeHook)';
  }
  return _automaticJsonCodec(model, field.type);
}

String _automaticJsonCodec(ModelingModelIr model, ModelingTypeIr type) {
  final parameter = model.typeParameters.where(
    (parameter) => parameter.name == type.declarationName,
  );
  String codec;
  if (parameter.isNotEmpty) {
    codec = _typeParameterCodecName(parameter.single);
  } else if (type.declarationName == 'dynamic' ||
      type.displayName == 'Object?') {
    codec = 'DartitectJsonCodecs.jsonValue';
  } else if (type.libraryUri == 'dart:core') {
    codec = switch (type.declarationName) {
      'String' => 'DartitectJsonCodecs.string',
      'bool' => 'DartitectJsonCodecs.boolean',
      'int' => 'DartitectJsonCodecs.integer',
      'num' => 'DartitectJsonCodecs.number',
      'double' => 'DartitectJsonCodecs.doubleValue',
      'Null' => 'DartitectJsonCodecs.nullValue',
      _ => throw StateError('Compiler admitted an unsupported JSON scalar.'),
    };
  } else {
    codec = switch (type.declarationName) {
      'ImmutableValueList' =>
        'DartitectJsonCodecs.immutableList('
            '${_automaticJsonCodec(model, type.typeArguments.single)})',
      'ImmutableValueSet' =>
        'DartitectJsonCodecs.immutableSet('
            '${_automaticJsonCodec(model, type.typeArguments.single)})',
      'ImmutableValueMap' =>
        'DartitectJsonCodecs.immutableMap('
            '${_automaticJsonCodec(model, type.typeArguments.last)})',
      _ => throw StateError('Compiler admitted an unsupported JSON type.'),
    };
  }
  return type.nullable && type.declarationName != 'Null'
      ? 'DartitectJsonCodecs.nullable($codec)'
      : codec;
}

String _typeParameterCodecName(ModelingTypeParameterIr parameter) =>
    'codec${parameter.name}';

String _lowerFirst(String value) =>
    '${value[0].toLowerCase()}${value.substring(1)}';

String _upperCamel(String value) => value
    .split('_')
    .where((segment) => segment.isNotEmpty)
    .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}')
    .join();

String _dartStringLiteral(String value) {
  var content = jsonEncode(value);
  content = content.substring(1, content.length - 1);
  content = content
      .replaceAll(r'\"', '"')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
  return "'$content'";
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
