import 'package:analyzer/dart/ast/ast.dart';

/// One deterministic source replacement produced by a semantic modeling fix.
final class ModelingSourceEdit {
  /// Creates one replacement at [offset] covering [length] characters.
  const ModelingSourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
  });

  /// Zero-based source offset.
  final int offset;

  /// Number of source characters replaced.
  final int length;

  /// Replacement source.
  final String replacement;
}

/// Builds the shared `model.migrate.primary` fix when semantics are provable.
///
/// The result is `null` for constructor bodies, initializers, ambiguous field
/// ownership, or any other case that needs consumer judgment.
List<ModelingSourceEdit>? primaryConstructorSourceEdits(
  ClassDeclaration declaration,
) {
  if (declaration.finalKeyword == null || declaration.abstractKeyword != null) {
    return null;
  }
  final constructors = declaration.body.members
      .whereType<ConstructorDeclaration>()
      .toList(growable: false);
  if (constructors.length != 1) return null;
  final constructor = constructors.single;
  if (constructor.name != null ||
      constructor.factoryKeyword != null ||
      constructor.externalKeyword != null ||
      constructor.initializers.isNotEmpty ||
      constructor.documentationComment != null) {
    return null;
  }
  final fields = <String, FieldDeclaration>{};
  for (final member in declaration.body.members.whereType<FieldDeclaration>()) {
    if (member.isStatic) continue;
    if (!member.fields.isFinal ||
        member.fields.isLate ||
        member.fields.type == null ||
        member.fields.variables.length != 1 ||
        member.fields.variables.single.initializer != null) {
      return null;
    }
    final name = member.fields.variables.single.name.lexeme;
    if (name.startsWith('_') || fields.containsKey(name)) return null;
    fields[name] = member;
  }
  if (fields.isEmpty) return null;
  final parameters = <String>[];
  final seen = <String>{};
  for (final parameter in constructor.parameters.parameters) {
    if (parameter is! FieldFormalParameter ||
        !parameter.isNamed ||
        parameter.name.lexeme.startsWith('_')) {
      return null;
    }
    final name = parameter.name.lexeme;
    final field = fields[name];
    if (field == null || !seen.add(name)) return null;
    final documentation = field.documentationComment?.toSource();
    final metadata = <String>{
      for (final annotation in field.metadata) annotation.toSource(),
      for (final annotation in parameter.metadata) annotation.toSource(),
    };
    final parameterSource =
        '${parameter.requiredKeyword == null ? '' : 'required '}'
        'final ${field.fields.type!.toSource()} $name'
        '${parameter.defaultClause?.toSource() ?? ''},';
    parameters.add(
      <String>[
        if (documentation != null) ...documentation.split('\n'),
        ...metadata,
        parameterSource,
      ].map((line) => '  $line').join('\n'),
    );
  }
  if (seen.length != fields.length) return null;
  final primary = StringBuffer()
    ..write(constructor.constKeyword == null ? '' : 'const ')
    ..write(declaration.namePart.toSource())
    ..writeln('({')
    ..writeln(parameters.join('\n'))
    ..write('})');
  return <ModelingSourceEdit>[
    ModelingSourceEdit(
      offset: declaration.namePart.offset,
      length: declaration.namePart.length,
      replacement: primary.toString(),
    ),
    ModelingSourceEdit(
      offset: constructor.offset,
      length: constructor.length,
      replacement: '',
    ),
    for (final field in fields.values)
      ModelingSourceEdit(
        offset: field.documentationComment?.offset ?? field.offset,
        length:
            field.end - (field.documentationComment?.offset ?? field.offset),
        replacement: '',
      ),
  ];
}
