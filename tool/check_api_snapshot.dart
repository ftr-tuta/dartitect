import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';

import 'api_snapshot.dart';

const _audiences = <String>{
  'application-facing',
  'extension-author',
  'generated-code',
  'adapter-author',
  'tooling-test',
};

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final release = _object(
    jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ),
    'package release contract',
  );
  final cohort = release['cohortVersion'];
  if (cohort is! String) throw const FormatException('Invalid release cohort.');
  final policy = _loadPolicy(root);
  final entrypoints = await _entrypoints(root);
  final paths = entrypoints.map((file) => _relative(root, file)).toSet();
  final missingPolicy = paths.difference(policy.keys.toSet()).toList()..sort();
  final stalePolicy = policy.keys.toSet().difference(paths).toList()..sort();
  if (missingPolicy.isNotEmpty || stalePolicy.isNotEmpty) {
    throw StateError(
      'Public API audience policy mismatch. Missing: $missingPolicy; '
      'stale: $stalePolicy.',
    );
  }

  final surface = <String, Object?>{};
  final collection = AnalysisContextCollection(
    includedPaths: entrypoints.map((entrypoint) => entrypoint.path).toList(),
  );
  try {
    for (final entrypoint in entrypoints) {
      final path = _relative(root, entrypoint);
      final audiencePolicy = policy[path]!;
      final result = await collection
          .contextFor(entrypoint.path)
          .currentSession
          .getResolvedLibrary(entrypoint.path);
      if (result is! ResolvedLibraryResult) {
        throw StateError('Could not resolve ${entrypoint.path}: $result');
      }
      final symbols =
          result.element.exportNamespace.definedNames2.entries
              .where((entry) => !entry.key.startsWith('_'))
              .map(
                (entry) => _semanticElement(
                  entry.value,
                  audience: audiencePolicy.audienceFor(entry.key),
                ),
              )
              .toList()
            ..sort(_compareSemanticElements);
      final unknownOverrides = audiencePolicy.overrides.keys.toSet().difference(
        symbols.map((symbol) => symbol['name']! as String).toSet(),
      );
      if (unknownOverrides.isNotEmpty) {
        throw StateError(
          '$path has stale audience overrides: $unknownOverrides',
        );
      }
      surface[path] = <String, Object?>{
        'defaultAudience': audiencePolicy.defaultAudience,
        'symbols': symbols,
      };
    }
  } finally {
    await collection.dispose();
  }
  final current = <String, Object?>{
    'schemaVersion': 2,
    'sdkVersion': cohort,
    'entrypoints': surface,
  };
  final encoded = '${const JsonEncoder.withIndent('  ').convert(current)}\n';
  final snapshot = File.fromUri(
    root.uri.resolve('tool/api_surface.snapshot.json'),
  );
  if (arguments.contains('--update')) {
    await snapshot.writeAsString(encoded, flush: true);
    stdout.writeln(
      'Updated semantic API snapshot for ${entrypoints.length} entrypoints.',
    );
    return;
  }
  if (!await snapshot.exists()) {
    stderr.writeln('Public API snapshot is missing; review and use --update.');
    exitCode = 1;
    return;
  }
  final previous = _object(
    jsonDecode(await snapshot.readAsString()),
    'API snapshot',
  );
  if (_canonical(previous) != _canonical(current)) {
    final differences = classifyApiDiff(previous, current);
    final change = maximumApiChange(differences);
    final previousVersion = previous['sdkVersion'];
    final versionValid =
        previousVersion is String &&
        validatesApiVersion(previousVersion, cohort, change);
    stderr.writeln(
      'Public API snapshot is stale (${change.name}); '
      'version ${versionValid ? 'permits' : 'does not permit'} this change.',
    );
    for (final difference in differences.take(30)) {
      stderr.writeln(
        '${difference.kind.name}: ${difference.path}: ${difference.message}',
      );
    }
    if (differences.length > 30) {
      stderr.writeln('... ${differences.length - 30} more difference(s).');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Semantic API snapshot matches ${entrypoints.length} entrypoints.',
  );
}

Map<String, Object?> _semanticElement(
  Element element, {
  required String audience,
}) {
  final output = <String, Object?>{
    'name': element.name ?? element.displayName,
    'kind': element.kind.name.toLowerCase(),
    'audience': audience,
    'declaration': element.displayString(),
    'deprecated': element.metadata.hasDeprecated,
    'annotations': _annotations(element),
    'modifiers': _modifiers(element),
  };
  if (element is TypeParameterizedElement) {
    output['typeParameters'] = <Object?>[
      for (final parameter in element.typeParameters)
        <String, Object?>{
          'name': parameter.name,
          'declaration': parameter.displayString(),
          'bound': parameter.bound?.getDisplayString(),
          'annotations': _annotations(parameter),
        },
    ];
  }
  if (element is ExecutableElement) {
    output['returnType'] = element.returnType.getDisplayString();
    output['parameters'] = <Object?>[
      for (final parameter in element.formalParameters)
        <String, Object?>{
          'name': parameter.name,
          'declaration': parameter.displayString(),
          'type': parameter.type.getDisplayString(),
          'kind': parameter.isRequiredNamed
              ? 'requiredNamed'
              : parameter.isOptionalNamed
              ? 'optionalNamed'
              : parameter.isOptionalPositional
              ? 'optionalPositional'
              : 'requiredPositional',
          'default': parameter.defaultValueCode,
          'annotations': _annotations(parameter),
        },
    ];
  }
  if (element is VariableElement) {
    output['type'] = element.type.getDisplayString();
  }
  if (element is TypeAliasElement) {
    output['aliasedType'] = element.aliasedType.getDisplayString();
  }
  if (element is InterfaceElement) {
    output['supertype'] = element.supertype?.getDisplayString();
    output['mixins'] = element.mixins
        .map((type) => type.getDisplayString())
        .toList();
    output['interfaces'] = element.interfaces
        .map((type) => type.getDisplayString())
        .toList();
  }
  if (element is InstanceElement) {
    final members = <Element>[
      if (element is InterfaceElement)
        ...element.constructors.where((member) => member.isPublic),
      ...element.fields.where(
        (member) => member.isPublic && !member.isOriginGetterSetter,
      ),
      ...element.getters.where(
        (member) => member.isPublic && member.isOriginDeclaration,
      ),
      ...element.setters.where(
        (member) => member.isPublic && member.isOriginDeclaration,
      ),
      ...element.methods.where((member) => member.isPublic),
    ];
    final semanticMembers =
        members
            .map((member) => _semanticElement(member, audience: audience))
            .toList()
          ..sort(_compareSemanticElements);
    output['members'] = semanticMembers;
  }
  return output;
}

List<String> _annotations(Element element) =>
    element.metadata.annotations
        .map((annotation) => annotation.toSource())
        .toList()
      ..sort();

List<String> _modifiers(Element element) {
  final values = <String>{};
  if (element.metadata.hasDeprecated) values.add('deprecated');
  if (element is ClassElement) {
    if (element.isAbstract) values.add('abstract');
    if (element.isBase) values.add('base');
    if (element.isFinal) values.add('final');
    if (element.isInterface) values.add('interface');
    if (element.isMixinClass) values.add('mixin');
    if (element.isSealed) values.add('sealed');
  }
  if (element is ConstructorElement) {
    if (element.isConst) values.add('const');
    if (element.isFactory) values.add('factory');
    if (element.isPrimary) values.add('primary');
  }
  if (element is ExecutableElement) {
    if (element.isAbstract) values.add('abstract');
    if (element.isExternal) values.add('external');
    if (element.isStatic) values.add('static');
  }
  if (element is VariableElement) {
    if (element.isConst) values.add('const');
    if (element.isFinal) values.add('final');
    if (element.isLate) values.add('late');
    if (element.isStatic) values.add('static');
  }
  if (element is FieldElement) {
    if (element.isCovariant) values.add('covariant');
    if (element.isEnumConstant) values.add('enumConstant');
  }
  return values.toList()..sort();
}

int _compareSemanticElements(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final kind = '${left['kind']}'.compareTo('${right['kind']}');
  if (kind != 0) return kind;
  final name = '${left['name']}'.compareTo('${right['name']}');
  if (name != 0) return name;
  return '${left['declaration']}'.compareTo('${right['declaration']}');
}

Future<List<File>> _entrypoints(Directory root) async {
  final output = <File>[];
  await for (final package in Directory.fromUri(
    root.uri.resolve('packages/'),
  ).list(followLinks: false)) {
    if (package is! Directory) continue;
    final lib = Directory.fromUri(package.uri.resolve('lib/'));
    if (!await lib.exists()) continue;
    await for (final entity in lib.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        output.add(entity.absolute);
      }
    }
  }
  output.sort((left, right) => left.path.compareTo(right.path));
  return output;
}

Map<String, _AudiencePolicy> _loadPolicy(Directory root) {
  final decoded = _object(
    jsonDecode(
      File('${root.path}/tool/public_api_audiences.json').readAsStringSync(),
    ),
    'public API audience policy',
  );
  if (decoded['schemaVersion'] != 1) {
    throw const FormatException('Unsupported public API audience schema.');
  }
  final entrypoints = _object(decoded['entrypoints'], 'audience entrypoints');
  return <String, _AudiencePolicy>{
    for (final entry in entrypoints.entries)
      entry.key: _AudiencePolicy.parse(
        _object(entry.value, 'audience policy ${entry.key}'),
      ),
  };
}

final class _AudiencePolicy {
  const _AudiencePolicy(this.defaultAudience, this.overrides);

  factory _AudiencePolicy.parse(Map<String, Object?> json) {
    final defaultAudience = json['defaultAudience'];
    if (defaultAudience is! String || !_audiences.contains(defaultAudience)) {
      throw FormatException('Invalid default audience: $defaultAudience');
    }
    final rawOverrides = json['overrides'] ?? const <String, Object?>{};
    final overrides = _object(rawOverrides, 'audience overrides').map((
      name,
      value,
    ) {
      if (value is! String || !_audiences.contains(value)) {
        throw FormatException('Invalid audience for $name: $value');
      }
      return MapEntry<String, String>(name, value);
    });
    return _AudiencePolicy(defaultAudience, overrides);
  }

  final String defaultAudience;
  final Map<String, String> overrides;

  String audienceFor(String symbol) => overrides[symbol] ?? defaultAudience;
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected object for $label.');
  }
  return value;
}

String _relative(Directory root, File file) => file.path
    .substring(root.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

String _canonical(Object? value) => jsonEncode(value);
