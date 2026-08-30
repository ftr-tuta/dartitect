import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_style/dart_style.dart';
import 'package:yaml/yaml.dart';

import '../generation/generation_engine.dart';

/// Classification emitted by bounded OpenAPI validation and comparison.
enum OpenApiContractFindingKind {
  /// The contract cannot be validated or generated safely.
  error,

  /// The compared surface only grows compatibly.
  additive,

  /// Existing generated consumers may no longer compile or behave the same.
  breaking,
}

/// One path-scoped OpenAPI validation or compatibility finding.
final class OpenApiContractFinding {
  /// Creates a stable finding.
  const OpenApiContractFinding({
    required this.code,
    required this.path,
    required this.message,
    required this.kind,
  });

  /// Stable diagnostic identifier.
  final String code;

  /// JSON pointer or project-relative file path.
  final String path;

  /// Sanitized actionable message.
  final String message;

  /// Validation or compatibility classification.
  final OpenApiContractFindingKind kind;

  /// JSON-safe representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'path': path,
    'message': message,
    'kind': kind.name,
  };
}

/// Deterministic result of `dartitect contracts check|sync`.
final class OpenApiContractReport {
  /// Creates a report around a validated generation plan.
  const OpenApiContractReport({
    required this.command,
    required this.specPath,
    required this.outputPath,
    required this.findings,
    required this.plan,
    required this.applied,
    required this.writes,
  });

  /// Stable command name.
  final String command;

  /// Project-relative source contract.
  final String specPath;

  /// Project-relative fully-generated Dart output.
  final String outputPath;

  /// Validation and compatibility findings.
  final List<OpenApiContractFinding> findings;

  /// Generation plan when validation produced renderable input.
  final GenerationPlan? plan;

  /// Whether synchronization committed outputs.
  final bool applied;

  /// Number of created, updated, or deleted files.
  final int writes;

  /// Whether no validation errors exist.
  bool get isValid => findings.every(
    (finding) => finding.kind != OpenApiContractFindingKind.error,
  );

  /// Whether compatibility contains no breaking change.
  bool get isCompatible => findings.every(
    (finding) => finding.kind != OpenApiContractFindingKind.breaking,
  );

  /// Whether generated outputs and ownership metadata are current.
  bool get isFresh =>
      isValid &&
      isCompatible &&
      plan != null &&
      !plan!.pendingRecovery &&
      !plan!.hasConflicts &&
      !plan!.hasChanges;

  /// JSON-safe command envelope.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': command,
    'spec': specPath,
    'output': outputPath,
    'valid': isValid,
    'compatible': isCompatible,
    'fresh': isFresh,
    'applied': applied,
    'writes': writes,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    'operations': <Object?>[
      for (final operation
          in plan?.operations ?? const <PlannedFileOperation>[])
        <String, Object?>{
          'path': operation.operation.relativePath,
          'disposition': operation.disposition.name,
        },
    ],
  };
}

/// Offline OpenAPI 3.1 validator, compatibility classifier, and generator.
final class OpenApiContractService {
  /// Creates a service confined to [root].
  OpenApiContractService(Directory root) : root = root.absolute;

  /// Project boundary for source, refs, and generated output.
  final Directory root;

  /// Validates, classifies, renders, and previews without writing.
  Future<OpenApiContractReport> inspect({
    required String specPath,
    String? baselinePath,
    String? outputPath,
  }) => _run(
    command: 'contracts check',
    specPath: specPath,
    baselinePath: baselinePath,
    outputPath: outputPath,
    apply: false,
  );

  /// Previews synchronization while retaining the sync command envelope.
  Future<OpenApiContractReport> preview({
    required String specPath,
    String? baselinePath,
    String? outputPath,
  }) => _run(
    command: 'contracts sync',
    specPath: specPath,
    baselinePath: baselinePath,
    outputPath: outputPath,
    apply: false,
  );

  /// Revalidates and transactionally converges the generated output.
  Future<OpenApiContractReport> apply({
    required String specPath,
    String? baselinePath,
    String? outputPath,
  }) => _run(
    command: 'contracts sync',
    specPath: specPath,
    baselinePath: baselinePath,
    outputPath: outputPath,
    apply: true,
  );

  Future<OpenApiContractReport> _run({
    required String command,
    required String specPath,
    required String? baselinePath,
    required String? outputPath,
    required bool apply,
  }) async {
    final loader = _OpenApiLoader(root);
    final findings = <OpenApiContractFinding>[];
    final current = await loader.load(specPath, findings: findings);
    if (current != null) {
      _validateContract(current, findings);
    }
    if (current != null && baselinePath != null) {
      final baselineFindings = <OpenApiContractFinding>[];
      final baseline = await loader.load(
        baselinePath,
        findings: baselineFindings,
      );
      if (baseline != null) _validateContract(baseline, baselineFindings);
      if (baselineFindings.any(
        (finding) => finding.kind == OpenApiContractFindingKind.error,
      )) {
        findings.addAll(
          baselineFindings.map(
            (finding) => OpenApiContractFinding(
              code: finding.code,
              path: 'baseline:${finding.path}',
              message: finding.message,
              kind: finding.kind,
            ),
          ),
        );
      } else if (baseline != null) {
        findings.addAll(_compareContracts(baseline, current));
      }
    }
    findings.sort((left, right) {
      final path = left.path.compareTo(right.path);
      return path == 0 ? left.code.compareTo(right.code) : path;
    });

    final resolvedOutput = _normalizeOutputPath(
      outputPath ?? _defaultOutput(specPath),
    );
    GenerationPlan? plan;
    var writes = 0;
    var applied = false;
    if (current != null &&
        findings.every(
          (finding) => finding.kind != OpenApiContractFindingKind.error,
        )) {
      final content = _OpenApiRenderer(current).render(resolvedOutput);
      final signature = sha256
          .convert(utf8.encode(_canonicalJson(current.root)))
          .toString();
      final operation = FileGenerationOperation(
        relativePath: resolvedOutput,
        content: content,
        ownership: GeneratedOwnership.fullyGenerated,
        sourcePath: current.relativePath,
        rendererVersion: 3,
        semanticSchemaVersion: 1,
        inputSignature: signature,
      );
      final engine = GenerationEngine(
        root,
        namespace: GenerationNamespace.contracts,
      );
      if (apply) {
        final result = await engine.apply(<FileGenerationOperation>[
          operation,
        ], manageFullyGenerated: true);
        plan = result.plan;
        writes =
            result.createdPaths.length +
            result.updatedPaths.length +
            result.deletedPaths.length;
        applied = true;
      } else {
        plan = await engine.plan(<FileGenerationOperation>[
          operation,
        ], manageFullyGenerated: true);
      }
    }
    return OpenApiContractReport(
      command: command,
      specPath: current?.relativePath ?? _portable(specPath),
      outputPath: resolvedOutput,
      findings: List<OpenApiContractFinding>.unmodifiable(findings),
      plan: plan,
      applied: applied,
      writes: writes,
    );
  }

  String _defaultOutput(String specPath) {
    final portable = _portable(specPath);
    final file = portable.split('/').last;
    final dot = file.lastIndexOf('.');
    final stem = dot <= 0 ? file : file.substring(0, dot);
    final safe = _snake(stem);
    return 'lib/contracts/$safe.contracts.dartitect.g.dart';
  }

  String _normalizeOutputPath(String value) {
    final portable = _portable(value);
    if (portable.startsWith('/') ||
        portable.split('/').contains('..') ||
        !portable.endsWith('.dartitect.g.dart')) {
      throw const FormatException(
        'Contract output must be a confined .dartitect.g.dart path.',
      );
    }
    final target = File(_join(root.path, portable)).absolute;
    if (!_within(target.path, root.path)) {
      throw const FormatException('Contract output escapes the project root.');
    }
    return portable;
  }
}

final class _OpenApiDocument {
  const _OpenApiDocument({
    required this.root,
    required this.file,
    required this.relativePath,
    required this.loader,
  });

  final Map<String, Object?> root;
  final File file;
  final String relativePath;
  final _OpenApiLoader loader;

  Object? resolveRef(String ref) => loader.resolveRef(this, ref);
}

final class _OpenApiLoader {
  _OpenApiLoader(this.root);

  final Directory root;
  final Map<String, _OpenApiDocument> _documents = <String, _OpenApiDocument>{};

  Future<_OpenApiDocument?> load(
    String input, {
    required List<OpenApiContractFinding> findings,
  }) async {
    try {
      final file = _confined(input, relativeTo: root);
      final document = await _read(file);
      _validateRefs(document, findings, <String>{});
      return document;
    } on FormatException catch (error) {
      findings.add(
        OpenApiContractFinding(
          code: 'DT3101',
          path: _portable(input),
          message: error.message,
          kind: OpenApiContractFindingKind.error,
        ),
      );
      return null;
    } on FileSystemException catch (error) {
      findings.add(
        OpenApiContractFinding(
          code: 'DT3101',
          path: _portable(input),
          message: error.message,
          kind: OpenApiContractFindingKind.error,
        ),
      );
      return null;
    }
  }

  Future<_OpenApiDocument> _read(File file) async {
    final real = file.resolveSymbolicLinksSync();
    final cached = _documents[real];
    if (cached != null) return cached;
    final source = await file.readAsString();
    final extension = file.path.toLowerCase();
    final Object? parsed;
    if (extension.endsWith('.json')) {
      parsed = jsonDecode(source);
    } else if (extension.endsWith('.yaml') || extension.endsWith('.yml')) {
      parsed = _plainYaml(loadYaml(source));
    } else {
      throw const FormatException('OpenAPI source must be JSON, YAML, or YML.');
    }
    if (parsed is! Map<String, Object?>) {
      throw const FormatException('OpenAPI source root must be an object.');
    }
    final document = _OpenApiDocument(
      root: parsed,
      file: File(real),
      relativePath: _relative(root.resolveSymbolicLinksSync(), real),
      loader: this,
    );
    _documents[real] = document;
    return document;
  }

  File _confined(String input, {required Directory relativeTo}) {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.hasScheme ||
        input.startsWith('/') ||
        input.contains('\\')) {
      throw const FormatException('OpenAPI paths must be local and relative.');
    }
    final file = File(_join(relativeTo.path, input));
    if (!file.existsSync()) {
      throw FormatException(
        'OpenAPI file does not exist: ${_portable(input)}.',
      );
    }
    final real = file.resolveSymbolicLinksSync();
    if (!_within(real, root.resolveSymbolicLinksSync())) {
      throw const FormatException(
        'OpenAPI path or symlink escapes the project.',
      );
    }
    return File(real);
  }

  Object? resolveRef(_OpenApiDocument owner, String ref) {
    if (ref.trim().isEmpty || Uri.tryParse(ref)?.hasScheme == true) {
      throw const FormatException(r'OpenAPI $ref must be local.');
    }
    final hash = ref.indexOf('#');
    final filePart = hash < 0 ? ref : ref.substring(0, hash);
    final fragment = hash < 0 ? '' : ref.substring(hash + 1);
    final document = filePart.isEmpty
        ? owner
        : _documents[_confined(
                filePart,
                relativeTo: owner.file.parent,
              ).resolveSymbolicLinksSync()] ??
              (throw FormatException(
                r'OpenAPI $ref document was not loaded: ' + filePart,
              ));
    Object? value = document.root;
    if (fragment.isEmpty) return value;
    if (!fragment.startsWith('/')) {
      throw const FormatException(
        r'OpenAPI $ref fragment must be a JSON pointer.',
      );
    }
    for (final raw in fragment.substring(1).split('/')) {
      final token = Uri.decodeComponent(
        raw.replaceAll('~1', '/').replaceAll('~0', '~'),
      );
      if (value is Map<String, Object?> && value.containsKey(token)) {
        value = value[token];
      } else if (value is List<Object?>) {
        final index = int.tryParse(token);
        if (index == null) {
          throw FormatException(r'OpenAPI $ref index is invalid: ' + ref);
        }
        if (index < 0 || index >= value.length) {
          throw FormatException(r'OpenAPI $ref index does not exist: ' + ref);
        }
        value = value[index];
      } else {
        throw FormatException(r'OpenAPI $ref target does not exist: ' + ref);
      }
    }
    return value;
  }

  void _validateRefs(
    _OpenApiDocument document,
    List<OpenApiContractFinding> findings,
    Set<String> visited,
  ) {
    void visit(Object? value, _OpenApiDocument owner, String pointer) {
      if (value is Map<String, Object?>) {
        final ref = value[r'$ref'];
        if (ref != null) {
          if (ref is! String) {
            findings.add(
              OpenApiContractFinding(
                code: 'DT3102',
                path: pointer,
                message: r'OpenAPI $ref must be a string.',
                kind: OpenApiContractFindingKind.error,
              ),
            );
            return;
          }
          try {
            final hash = ref.indexOf('#');
            final filePart = hash < 0 ? ref : ref.substring(0, hash);
            var refOwner = owner;
            if (filePart.isNotEmpty) {
              final file = _confined(filePart, relativeTo: owner.file.parent);
              refOwner =
                  _documents[file.resolveSymbolicLinksSync()] ??
                  _readSync(file);
            }
            final key = '${refOwner.file.path}#$ref';
            final target = resolveRef(owner, ref);
            if (visited.add(key)) visit(target, refOwner, '$pointer/\$ref');
          } on FormatException catch (error) {
            findings.add(
              OpenApiContractFinding(
                code: 'DT3102',
                path: pointer,
                message: error.message,
                kind: OpenApiContractFindingKind.error,
              ),
            );
          }
          return;
        }
        for (final entry in value.entries) {
          visit(entry.value, owner, '$pointer/${_pointer(entry.key)}');
        }
      } else if (value is List<Object?>) {
        for (var index = 0; index < value.length; index += 1) {
          visit(value[index], owner, '$pointer/$index');
        }
      }
    }

    visit(document.root, document, '');
  }

  _OpenApiDocument _readSync(File file) {
    final real = file.resolveSymbolicLinksSync();
    final cached = _documents[real];
    if (cached != null) return cached;
    final source = file.readAsStringSync();
    final parsed = file.path.toLowerCase().endsWith('.json')
        ? jsonDecode(source)
        : _plainYaml(loadYaml(source));
    if (parsed is! Map<String, Object?>) {
      throw const FormatException('Referenced OpenAPI root must be an object.');
    }
    final document = _OpenApiDocument(
      root: parsed,
      file: File(real),
      relativePath: _relative(root.resolveSymbolicLinksSync(), real),
      loader: this,
    );
    _documents[real] = document;
    return document;
  }
}

const _httpMethods = <String>{
  'get',
  'put',
  'post',
  'delete',
  'options',
  'head',
  'patch',
  'trace',
};

void _validateContract(
  _OpenApiDocument document,
  List<OpenApiContractFinding> findings,
) {
  final root = document.root;
  final version = root['openapi'];
  if (version is! String || !version.startsWith('3.1.')) {
    _error(
      findings,
      'DT3103',
      '/openapi',
      'Only OpenAPI 3.1.x contracts are supported.',
    );
  }
  if (root['info'] is! Map<String, Object?>) {
    _error(findings, 'DT3103', '/info', 'OpenAPI info must be an object.');
  }
  if (root.containsKey('webhooks')) {
    _error(
      findings,
      'DT3104',
      '/webhooks',
      'Webhooks are outside the bounded contract generator.',
    );
  }
  final paths = root['paths'];
  if (paths is! Map<String, Object?>) {
    _error(findings, 'DT3103', '/paths', 'OpenAPI paths must be an object.');
  } else {
    for (final pathEntry in paths.entries) {
      final path = pathEntry.key;
      if (!path.startsWith('/')) {
        _error(
          findings,
          'DT3103',
          '/paths/${_pointer(path)}',
          'Route templates must start with /.',
        );
      }
      final pathItem = _mapOrNull(_dereference(document, pathEntry.value));
      if (pathItem == null) {
        _error(
          findings,
          'DT3103',
          '/paths/${_pointer(path)}',
          'Path items must be objects.',
        );
        continue;
      }
      for (final operationEntry in pathItem.entries) {
        if (!_httpMethods.contains(operationEntry.key)) continue;
        final pointer = '/paths/${_pointer(path)}/${operationEntry.key}';
        final operation = _mapOrNull(
          _dereference(document, operationEntry.value),
        );
        if (operation == null) {
          _error(findings, 'DT3103', pointer, 'Operations must be objects.');
          continue;
        }
        if (operation.containsKey('callbacks')) {
          _error(
            findings,
            'DT3104',
            '$pointer/callbacks',
            'Callbacks are outside the bounded contract generator.',
          );
        }
        _validateParameters(
          document,
          <Object?>[
            ...?_listOrNull(pathItem['parameters']),
            ...?_listOrNull(operation['parameters']),
          ],
          '$pointer/parameters',
          findings,
        );
        _validateContent(
          document,
          _mapOrNull(_dereference(document, operation['requestBody'])),
          '$pointer/requestBody',
          findings,
        );
        final responses = _mapOrNull(operation['responses']);
        if (responses == null || responses.isEmpty) {
          _error(
            findings,
            'DT3103',
            '$pointer/responses',
            'Operations require at least one response.',
          );
        } else {
          for (final response in responses.entries) {
            _validateContent(
              document,
              _mapOrNull(_dereference(document, response.value)),
              '$pointer/responses/${_pointer(response.key)}',
              findings,
            );
          }
        }
      }
    }
  }
  final schemas = _mapOrNull(_mapOrNull(root['components'])?['schemas']);
  if (schemas != null) {
    for (final entry in schemas.entries) {
      _validateSchema(
        document,
        entry.value,
        '/components/schemas/${_pointer(entry.key)}',
        findings,
        <Object>{},
      );
    }
  }
}

void _validateParameters(
  _OpenApiDocument document,
  List<Object?> values,
  String pointer,
  List<OpenApiContractFinding> findings,
) {
  final names = <String>{};
  for (var index = 0; index < values.length; index += 1) {
    final parameter = _mapOrNull(_dereference(document, values[index]));
    final path = '$pointer/$index';
    if (parameter == null) {
      _error(findings, 'DT3103', path, 'Parameters must be objects.');
      continue;
    }
    final name = parameter['name'];
    final location = parameter['in'];
    if (name is! String ||
        name.isEmpty ||
        !const <String>{'path', 'query', 'header'}.contains(location)) {
      _error(
        findings,
        'DT3103',
        path,
        'Only named path, query, and header parameters are supported.',
      );
      continue;
    }
    if (!names.add('$location:$name')) {
      _error(findings, 'DT3103', path, 'Duplicate operation parameter.');
    }
    if (location == 'path' && parameter['required'] != true) {
      _error(findings, 'DT3103', path, 'Path parameters must be required.');
    }
    _validateSchema(
      document,
      parameter['schema'],
      '$path/schema',
      findings,
      <Object>{},
    );
  }
}

void _validateContent(
  _OpenApiDocument document,
  Map<String, Object?>? boundary,
  String pointer,
  List<OpenApiContractFinding> findings,
) {
  if (boundary == null) return;
  final content = _mapOrNull(boundary['content']);
  if (content == null || content.isEmpty) return;
  for (final entry in content.entries) {
    if (entry.key == 'multipart/form-data' ||
        entry.key == 'application/octet-stream' ||
        !_isJsonMediaType(entry.key)) {
      _error(
        findings,
        'DT3104',
        '$pointer/content/${_pointer(entry.key)}',
        'Only bounded JSON bodies and responses are supported; use the '
            'attachment pipeline for multipart or binary content.',
      );
      continue;
    }
    final media = _mapOrNull(entry.value);
    _validateSchema(
      document,
      media?['schema'],
      '$pointer/content/${_pointer(entry.key)}/schema',
      findings,
      <Object>{},
    );
  }
}

void _validateSchema(
  _OpenApiDocument document,
  Object? raw,
  String pointer,
  List<OpenApiContractFinding> findings,
  Set<Object> active,
) {
  if (raw == null) return;
  if (raw is! Map<String, Object?>) {
    _error(findings, 'DT3103', pointer, 'Schemas must be objects.');
    return;
  }
  if (!active.add(raw)) return;
  try {
    if (raw[r'$ref'] case final String ref) {
      try {
        _validateSchema(
          document,
          document.resolveRef(ref),
          '$pointer/\$ref',
          findings,
          active,
        );
      } on FormatException catch (error) {
        _error(findings, 'DT3102', pointer, error.message);
      }
      return;
    }
    if (raw['format'] == 'binary' || raw['format'] == 'byte') {
      _error(
        findings,
        'DT3104',
        '$pointer/format',
        'Binary and attachment formats require the attachment pipeline.',
      );
    }
    final type = raw['type'];
    final types = type is List<Object?>
        ? type
        : <Object?>[if (type != null) type];
    if (types.any(
      (value) =>
          value is! String ||
          !const <String>{
            'null',
            'boolean',
            'integer',
            'number',
            'string',
            'array',
            'object',
          }.contains(value),
    )) {
      _error(findings, 'DT3103', '$pointer/type', 'Unsupported schema type.');
    }
    if (raw['enum'] case final Object values) {
      if (values is! List<Object?> || values.isEmpty) {
        _error(findings, 'DT3103', '$pointer/enum', 'Enums must be non-empty.');
      }
    }
    if (raw['oneOf'] case final Object oneOf) {
      if (oneOf is! List<Object?> || oneOf.isEmpty) {
        _error(
          findings,
          'DT3103',
          '$pointer/oneOf',
          'oneOf must be non-empty.',
        );
      } else {
        final discriminator = _mapOrNull(raw['discriminator']);
        if (discriminator?['propertyName'] is! String) {
          _error(
            findings,
            'DT3103',
            '$pointer/discriminator',
            'oneOf requires an explicit discriminator propertyName.',
          );
        }
        for (var index = 0; index < oneOf.length; index += 1) {
          _validateSchema(
            document,
            oneOf[index],
            '$pointer/oneOf/$index',
            findings,
            active,
          );
        }
      }
    }
    if (raw['allOf'] case final Object allOf) {
      if (allOf is! List<Object?> || allOf.isEmpty) {
        _error(
          findings,
          'DT3103',
          '$pointer/allOf',
          'allOf must be non-empty.',
        );
      } else {
        for (var index = 0; index < allOf.length; index += 1) {
          _validateSchema(
            document,
            allOf[index],
            '$pointer/allOf/$index',
            findings,
            active,
          );
        }
      }
    }
    if (types.contains('array') || raw.containsKey('items')) {
      if (raw['items'] == null) {
        _error(findings, 'DT3103', '$pointer/items', 'Arrays require items.');
      } else {
        _validateSchema(
          document,
          raw['items'],
          '$pointer/items',
          findings,
          active,
        );
      }
    }
    final properties = _mapOrNull(raw['properties']);
    if (properties != null) {
      final required = _listOrNull(raw['required']) ?? const <Object?>[];
      if (required.any(
        (name) => name is! String || !properties.containsKey(name),
      )) {
        _error(
          findings,
          'DT3103',
          '$pointer/required',
          'Required names must identify declared properties.',
        );
      }
      for (final property in properties.entries) {
        _validateSchema(
          document,
          property.value,
          '$pointer/properties/${_pointer(property.key)}',
          findings,
          active,
        );
      }
    }
  } finally {
    active.remove(raw);
  }
}

List<OpenApiContractFinding> _compareContracts(
  _OpenApiDocument baseline,
  _OpenApiDocument current,
) {
  final findings = <OpenApiContractFinding>[];
  final beforeSchemas =
      _mapOrNull(_mapOrNull(baseline.root['components'])?['schemas']) ??
      const <String, Object?>{};
  final afterSchemas =
      _mapOrNull(_mapOrNull(current.root['components'])?['schemas']) ??
      const <String, Object?>{};
  for (final name in beforeSchemas.keys.toList()..sort()) {
    final path = '/components/schemas/${_pointer(name)}';
    if (!afterSchemas.containsKey(name)) {
      _change(findings, 'DT3110', path, 'Schema was removed.', breaking: true);
      continue;
    }
    _compareSchema(
      baseline,
      beforeSchemas[name],
      current,
      afterSchemas[name],
      path,
      findings,
    );
  }
  for (final name in afterSchemas.keys.toList()..sort()) {
    if (!beforeSchemas.containsKey(name)) {
      _change(
        findings,
        'DT3111',
        '/components/schemas/${_pointer(name)}',
        'Schema was added.',
        breaking: false,
      );
    }
  }
  final beforeOperations = _operationSurface(baseline);
  final afterOperations = _operationSurface(current);
  for (final key in beforeOperations.keys.toList()..sort()) {
    if (!afterOperations.containsKey(key)) {
      _change(
        findings,
        'DT3110',
        key,
        'Operation was removed.',
        breaking: true,
      );
    } else if (_canonicalJson(beforeOperations[key]) !=
        _canonicalJson(afterOperations[key])) {
      _change(
        findings,
        'DT3110',
        key,
        'Operation parameters, body, or responses changed.',
        breaking: true,
      );
    }
  }
  for (final key in afterOperations.keys.toList()..sort()) {
    if (!beforeOperations.containsKey(key)) {
      _change(findings, 'DT3111', key, 'Operation was added.', breaking: false);
    }
  }
  return findings;
}

void _compareSchema(
  _OpenApiDocument beforeDocument,
  Object? beforeRaw,
  _OpenApiDocument afterDocument,
  Object? afterRaw,
  String path,
  List<OpenApiContractFinding> findings,
) {
  final before = _mapOrNull(_dereference(beforeDocument, beforeRaw));
  final after = _mapOrNull(_dereference(afterDocument, afterRaw));
  if (before == null || after == null) return;
  final beforeEnum = _listOrNull(before['enum']);
  final afterEnum = _listOrNull(after['enum']);
  if (beforeEnum != null && afterEnum != null) {
    for (final value in beforeEnum) {
      if (!afterEnum.contains(value)) {
        _change(
          findings,
          'DT3110',
          '$path/enum',
          'Enum value ${jsonEncode(value)} was removed.',
          breaking: true,
        );
      }
    }
    for (final value in afterEnum) {
      if (!beforeEnum.contains(value)) {
        _change(
          findings,
          'DT3111',
          '$path/enum',
          'Enum value ${jsonEncode(value)} was added.',
          breaking: false,
        );
      }
    }
  }
  final beforeProperties =
      _mapOrNull(before['properties']) ?? const <String, Object?>{};
  final afterProperties =
      _mapOrNull(after['properties']) ?? const <String, Object?>{};
  final beforeRequired = (_listOrNull(before['required']) ?? const <Object?>[])
      .whereType<String>()
      .toSet();
  final afterRequired = (_listOrNull(after['required']) ?? const <Object?>[])
      .whereType<String>()
      .toSet();
  for (final name in beforeProperties.keys) {
    final propertyPath = '$path/properties/${_pointer(name)}';
    if (!afterProperties.containsKey(name)) {
      _change(
        findings,
        'DT3110',
        propertyPath,
        'Property was removed.',
        breaking: true,
      );
    } else if (_schemaSignature(beforeDocument, beforeProperties[name]) !=
        _schemaSignature(afterDocument, afterProperties[name])) {
      _change(
        findings,
        'DT3110',
        propertyPath,
        'Property type changed.',
        breaking: true,
      );
    }
  }
  for (final name in afterProperties.keys) {
    if (!beforeProperties.containsKey(name)) {
      _change(
        findings,
        afterRequired.contains(name) ? 'DT3110' : 'DT3111',
        '$path/properties/${_pointer(name)}',
        afterRequired.contains(name)
            ? 'Required property was added.'
            : 'Optional property was added.',
        breaking: afterRequired.contains(name),
      );
    }
  }
  for (final name in afterRequired.difference(beforeRequired)) {
    if (beforeProperties.containsKey(name)) {
      _change(
        findings,
        'DT3110',
        '$path/required',
        'Existing property $name became required.',
        breaking: true,
      );
    }
  }
}

Map<String, Object?> _operationSurface(_OpenApiDocument document) {
  final result = <String, Object?>{};
  final paths = _mapOrNull(document.root['paths']) ?? const <String, Object?>{};
  for (final path in paths.entries) {
    final item = _mapOrNull(_dereference(document, path.value));
    if (item == null) continue;
    for (final method in _httpMethods) {
      final operation = _mapOrNull(_dereference(document, item[method]));
      if (operation == null) continue;
      result['/paths/${_pointer(path.key)}/$method'] = <String, Object?>{
        'parameters': <Object?>[
          ...?_listOrNull(item['parameters']),
          ...?_listOrNull(operation['parameters']),
        ].map((value) => _dereference(document, value)).toList(),
        'requestBody': _dereference(document, operation['requestBody']),
        'responses': operation['responses'],
      };
    }
  }
  return result;
}

String _schemaSignature(_OpenApiDocument document, Object? raw) {
  final schema = _mapOrNull(_dereference(document, raw));
  if (schema == null) return 'unknown';
  return _canonicalJson(<String, Object?>{
    'type': schema['type'],
    'format': schema['format'],
    'nullable': schema['nullable'],
    'items': schema['items'] == null
        ? null
        : _schemaSignature(document, schema['items']),
    'ref': schema[r'$ref'],
    'oneOf': schema['oneOf'],
    'allOf': schema['allOf'],
  });
}

void _error(
  List<OpenApiContractFinding> findings,
  String code,
  String path,
  String message,
) {
  findings.add(
    OpenApiContractFinding(
      code: code,
      path: path.isEmpty ? '/' : path,
      message: message,
      kind: OpenApiContractFindingKind.error,
    ),
  );
}

void _change(
  List<OpenApiContractFinding> findings,
  String code,
  String path,
  String message, {
  required bool breaking,
}) {
  findings.add(
    OpenApiContractFinding(
      code: code,
      path: path,
      message: message,
      kind: breaking
          ? OpenApiContractFindingKind.breaking
          : OpenApiContractFindingKind.additive,
    ),
  );
}

final class _OpenApiRenderer {
  _OpenApiRenderer(this.document);

  final _OpenApiDocument document;

  String render(String outputPath) {
    final schemas =
        _mapOrNull(_mapOrNull(document.root['components'])?['schemas']) ??
        const <String, Object?>{};
    final operations = _operations();
    final title = _mapOrNull(document.root['info'])?['title'];
    final contractName = _pascal(title is String ? title : 'OpenApi');
    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT EDIT BY HAND.')
      ..writeln('// Bounded OpenAPI 3.1 DTOs and Dio endpoint clients.')
      ..writeln(
        '// ignore_for_file: public_member_api_docs, prefer_single_quotes',
      );
    if (operations.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln("import 'package:dio/dio.dart';");
    }
    buffer
      ..writeln()
      ..writeln(
        'const String ${_camel(contractName)}OpenApiSource = ${_literal(document.relativePath)};',
      )
      ..writeln(
        "const String ${_camel(contractName)}OpenApiVersion = ${_literal(document.root['openapi'])};",
      );

    for (final entry
        in schemas.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key))) {
      _renderSchema(buffer, entry.key, entry.value);
    }
    _renderDescriptor(buffer);
    if (operations.isNotEmpty) {
      _renderOperations(buffer, contractName, operations);
    }
    final source = buffer.toString();
    return DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
      lineEnding: '\n',
    ).format(source, uri: outputPath);
  }

  void _renderSchema(StringBuffer buffer, String wireName, Object? raw) {
    final name = '${_pascal(wireName)}Dto';
    final schema = _mapOrNull(_dereference(document, raw));
    if (schema == null) return;
    final enumValues = _listOrNull(schema['enum']);
    if (enumValues != null) {
      _renderEnum(buffer, name, enumValues);
      _renderFixture(buffer, wireName, schema);
      return;
    }
    final oneOf = _listOrNull(schema['oneOf']);
    if (oneOf != null) {
      _renderUnion(buffer, name, schema, oneOf);
      _renderFixture(buffer, wireName, schema);
      return;
    }
    if (_schemaBaseType(schema) == 'object' || schema['allOf'] != null) {
      final effective = _effectiveObjectSchema(raw, <Object>{});
      _renderObject(buffer, name, effective);
      _renderFixture(buffer, wireName, effective);
      return;
    }
    final type = _dartType(raw, required: true);
    buffer
      ..writeln()
      ..writeln(
        '/// Generated scalar contract alias for ${_literal(wireName)}.',
      )
      ..writeln('typedef $name = $type;');
    _renderFixture(buffer, wireName, schema);
  }

  void _renderEnum(StringBuffer buffer, String name, List<Object?> values) {
    final used = <String>{};
    final members = <(String, Object?)>[];
    for (var index = 0; index < values.length; index += 1) {
      var member = _identifier('${values[index]}', fallback: 'value$index');
      while (!used.add(member)) {
        member = '${member}_$index';
      }
      members.add((member, values[index]));
    }
    buffer
      ..writeln()
      ..writeln('/// Generated bounded OpenAPI enum.')
      ..writeln('enum $name {');
    for (final member in members) {
      buffer.writeln('  ${member.$1},');
    }
    buffer
      ..writeln('  ;')
      ..writeln()
      ..writeln('  factory $name.fromJson(Object? value) => switch (value) {');
    for (final member in members) {
      buffer.writeln('    ${_literal(member.$2)} => $name.${member.$1},');
    }
    buffer
      ..writeln(
        "    _ => throw FormatException('Unknown $name value: \$value'),",
      )
      ..writeln('  };')
      ..writeln()
      ..writeln('  Object toJson() => switch (this) {');
    for (final member in members) {
      buffer.writeln('    $name.${member.$1} => ${_literal(member.$2)},');
    }
    buffer
      ..writeln('  };')
      ..writeln('}');
  }

  void _renderUnion(
    StringBuffer buffer,
    String name,
    Map<String, Object?> schema,
    List<Object?> variants,
  ) {
    final discriminator = _mapOrNull(schema['discriminator']);
    final property = discriminator?['propertyName'] as String? ?? 'type';
    final mapping = _mapOrNull(discriminator?['mapping']);
    final variantTypes = <(String, String)>[];
    for (final variant in variants) {
      final ref = _mapOrNull(variant)?[r'$ref'];
      if (ref is! String) continue;
      final type = '${_pascal(_refName(ref))}Dto';
      String? wire;
      if (mapping != null) {
        for (final entry in mapping.entries) {
          if (entry.value == ref) wire = entry.key;
        }
      }
      variantTypes.add((wire ?? _camel(_refName(ref)), type));
    }
    buffer
      ..writeln()
      ..writeln('/// Generated discriminated oneOf value.')
      ..writeln('final class const $name({required final Object value}) {')
      ..writeln('  this;')
      ..writeln()
      ..writeln('  factory $name.fromJson(Map<String, Object?> json) {')
      ..writeln('    return switch (json[${_literal(property)}]) {');
    for (final variant in variantTypes) {
      buffer.writeln(
        '      ${_literal(variant.$1)} => $name(value: ${variant.$2}.fromJson(json)),',
      );
    }
    buffer
      ..writeln(
        "      final value => throw FormatException('Unknown $name discriminator: \$value'),",
      )
      ..writeln('    };')
      ..writeln('  }')
      ..writeln()
      ..writeln('  Map<String, Object?> toJson() => switch (value) {');
    for (final variant in variantTypes) {
      buffer.writeln('    final ${variant.$2} value => value.toJson(),');
    }
    buffer
      ..writeln(
        "    _ => throw StateError('Unsupported $name runtime value.'),",
      )
      ..writeln('  };')
      ..writeln('}');
  }

  void _renderObject(
    StringBuffer buffer,
    String name,
    Map<String, Object?> schema,
  ) {
    final properties =
        _mapOrNull(schema['properties']) ?? const <String, Object?>{};
    final required = (_listOrNull(schema['required']) ?? const <Object?>[])
        .whereType<String>()
        .toSet();
    final entries = properties.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    buffer
      ..writeln()
      ..writeln(
        '/// Generated JSON DTO; semantic domain mapping stays consumer-owned.',
      )
      ..writeln('final class const $name({');
    for (final entry in entries) {
      final field = _identifier(entry.key);
      final isRequired = required.contains(entry.key);
      buffer.writeln(
        '  ${isRequired ? 'required ' : ''}final ${_dartType(entry.value, required: isRequired)} $field,',
      );
    }
    buffer
      ..writeln('}) {')
      ..writeln('  this;')
      ..writeln()
      ..writeln(
        '  factory $name.fromJson(Map<String, Object?> json) => $name(',
      );
    for (final entry in entries) {
      final field = _identifier(entry.key);
      final isRequired = required.contains(entry.key);
      buffer.writeln(
        '    $field: ${_decodeExpression(entry.value, "json[${_literal(entry.key)}]", required: isRequired)},',
      );
    }
    buffer
      ..writeln('  );')
      ..writeln()
      ..writeln('  Map<String, Object?> toJson() => <String, Object?>{');
    for (final entry in entries) {
      final field = _identifier(entry.key);
      final isRequired = required.contains(entry.key);
      if (!isRequired) buffer.write('    if ($field != null) ');
      buffer.writeln(
        '${_literal(entry.key)}: ${_encodeExpression(entry.value, field, nullable: !isRequired)},',
      );
    }
    buffer
      ..writeln('  };')
      ..writeln('}');
  }

  void _renderFixture(
    StringBuffer buffer,
    String wireName,
    Map<String, Object?> schema,
  ) {
    final fixtureName = '${_camel(wireName)}OpenApiFixture';
    buffer
      ..writeln()
      ..writeln('/// Deterministic bounded JSON fixture for contract tests.')
      ..writeln(
        'const Object? $fixtureName = ${_fixtureLiteral(schema, <Object>{})};',
      );
  }

  void _renderDescriptor(StringBuffer buffer) {
    buffer
      ..writeln()
      ..writeln(
        '/// Generated endpoint metadata without automatic security execution.',
      )
      ..writeln('final class const OpenApiEndpointDescriptor({')
      ..writeln('  required final String operationId,')
      ..writeln('  required final String method,')
      ..writeln('  required final String routeTemplate,')
      ..writeln('  required final Map<int, String> responseTypes,')
      ..writeln('}) {')
      ..writeln('  this;')
      ..writeln('}');
  }

  void _renderOperations(
    StringBuffer buffer,
    String contractName,
    List<_OperationIr> operations,
  ) {
    for (final operation in operations) {
      buffer
        ..writeln()
        ..writeln('/// Expands the local OpenAPI route template.')
        ..write('String ${operation.name}Route({');
      for (final parameter in operation.parameters.where(
        (parameter) => parameter.location == 'path',
      )) {
        buffer.write('required ${parameter.type} ${parameter.dartName},');
      }
      buffer..writeln('}) => ${_routeExpression(operation)};');
    }
    buffer
      ..writeln()
      ..writeln('/// Generated status mappings and endpoint descriptors.')
      ..writeln(
        'const List<OpenApiEndpointDescriptor> ${_camel(contractName)}Endpoints = <OpenApiEndpointDescriptor>[',
      );
    for (final operation in operations) {
      buffer
        ..writeln('  OpenApiEndpointDescriptor(')
        ..writeln('    operationId: ${_literal(operation.wireName)},')
        ..writeln('    method: ${_literal(operation.method.toUpperCase())},')
        ..writeln('    routeTemplate: ${_literal(operation.path)},')
        ..writeln('    responseTypes: <int, String>{');
      for (final response in operation.responses.entries) {
        buffer.writeln('      ${response.key}: ${_literal(response.value)},');
      }
      buffer
        ..writeln('    },')
        ..writeln('  ),');
    }
    buffer
      ..writeln('];')
      ..writeln()
      ..writeln(
        '/// Borrowed-Dio client; credentials remain in their explicit pipeline.',
      )
      ..writeln('final class ${contractName}Client {')
      ..writeln('  const ${contractName}Client(this._dio);')
      ..writeln()
      ..writeln('  final Dio _dio;');
    for (final operation in operations) {
      buffer
        ..writeln()
        ..writeln(
          '  /// Calls ${operation.method.toUpperCase()} ${operation.path}.',
        )
        ..writeln('  Future<Response<Object?>> ${operation.name}({');
      for (final parameter in operation.parameters) {
        buffer.writeln(
          '    ${parameter.required ? 'required ' : ''}${parameter.type} ${parameter.dartName},',
        );
      }
      if (operation.bodyType != null) {
        buffer.writeln(
          '    ${operation.bodyRequired ? 'required ' : ''}${operation.bodyType} body,',
        );
      }
      buffer
        ..writeln('  }) => _dio.request<Object?>(')
        ..write('    ${operation.name}Route(');
      for (final parameter in operation.parameters.where(
        (parameter) => parameter.location == 'path',
      )) {
        buffer.write('${parameter.dartName}: ${parameter.dartName},');
      }
      buffer
        ..writeln('),')
        ..writeln('    queryParameters: <String, Object?>{');
      for (final parameter in operation.parameters.where(
        (parameter) => parameter.location == 'query',
      )) {
        if (!parameter.required) {
          buffer.write('      if (${parameter.dartName} != null) ');
        }
        buffer.writeln(
          '${_literal(parameter.wireName)}: ${parameter.dartName},',
        );
      }
      buffer
        ..writeln('    },')
        ..writeln('    options: Options(')
        ..writeln('      method: ${_literal(operation.method.toUpperCase())},')
        ..writeln('      headers: <String, Object?>{');
      for (final parameter in operation.parameters.where(
        (parameter) => parameter.location == 'header',
      )) {
        if (!parameter.required) {
          buffer.write('        if (${parameter.dartName} != null) ');
        }
        buffer.writeln(
          '${_literal(parameter.wireName)}: ${parameter.dartName},',
        );
      }
      buffer
        ..writeln('      },')
        ..writeln('    ),');
      if (operation.bodyType != null) {
        buffer.writeln('    data: ${operation.bodyEncodeExpression('body')},');
      }
      buffer.writeln('  );');
    }
    buffer.writeln('}');
  }

  List<_OperationIr> _operations() {
    final result = <_OperationIr>[];
    final paths =
        _mapOrNull(document.root['paths']) ?? const <String, Object?>{};
    for (final pathEntry
        in paths.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key))) {
      final pathItem = _mapOrNull(_dereference(document, pathEntry.value));
      if (pathItem == null) continue;
      for (final method in _httpMethods.toList()..sort()) {
        final operation = _mapOrNull(_dereference(document, pathItem[method]));
        if (operation == null) continue;
        final wireName = operation['operationId'] is String
            ? operation['operationId']! as String
            : '$method ${pathEntry.key}';
        final name = _identifier(
          operation['operationId'] is String
              ? operation['operationId']! as String
              : '${method}_${pathEntry.key}',
        );
        final parameters = <_ParameterIr>[];
        final values = <Object?>[
          ...?_listOrNull(pathItem['parameters']),
          ...?_listOrNull(operation['parameters']),
        ];
        final byKey = <String, _ParameterIr>{};
        for (final raw in values) {
          final parameter = _mapOrNull(_dereference(document, raw));
          if (parameter == null) continue;
          final location = parameter['in']! as String;
          final wire = parameter['name']! as String;
          final required = parameter['required'] == true;
          byKey['$location:$wire'] = _ParameterIr(
            wireName: wire,
            dartName: _identifier(wire),
            location: location,
            required: required,
            type: _dartType(parameter['schema'], required: required),
          );
        }
        parameters.addAll(byKey.values);
        parameters.sort((left, right) {
          const rank = <String, int>{'path': 0, 'query': 1, 'header': 2};
          final location = rank[left.location]!.compareTo(
            rank[right.location]!,
          );
          return location == 0
              ? left.wireName.compareTo(right.wireName)
              : location;
        });
        final requestBody = _mapOrNull(
          _dereference(document, operation['requestBody']),
        );
        final bodySchema = _jsonSchemaFromContent(requestBody);
        final responses = <int, String>{};
        final responseMap = _mapOrNull(operation['responses']);
        if (responseMap != null) {
          for (final response in responseMap.entries) {
            final status = int.tryParse(response.key);
            if (status == null) continue;
            final boundary = _mapOrNull(_dereference(document, response.value));
            final schema = _jsonSchemaFromContent(boundary);
            responses[status] = schema == null
                ? 'void'
                : _dartType(schema, required: true);
          }
        }
        result.add(
          _OperationIr(
            wireName: wireName,
            name: name,
            method: method,
            path: pathEntry.key,
            parameters: parameters,
            bodySchema: bodySchema,
            bodyType: bodySchema == null
                ? null
                : _dartType(
                    bodySchema,
                    required: requestBody?['required'] == true,
                  ),
            bodyRequired: requestBody?['required'] == true,
            responses: Map<int, String>.fromEntries(
              responses.entries.toList()
                ..sort((left, right) => left.key.compareTo(right.key)),
            ),
            renderer: this,
          ),
        );
      }
    }
    return result;
  }

  Map<String, Object?> _effectiveObjectSchema(Object? raw, Set<Object> active) {
    final schema = _mapOrNull(_dereference(document, raw));
    if (schema == null || !active.add(schema)) {
      return const <String, Object?>{'type': 'object'};
    }
    final properties = <String, Object?>{};
    final required = <String>{};
    for (final member in _listOrNull(schema['allOf']) ?? const <Object?>[]) {
      final merged = _effectiveObjectSchema(member, active);
      properties.addAll(
        _mapOrNull(merged['properties']) ?? const <String, Object?>{},
      );
      required.addAll(
        (_listOrNull(merged['required']) ?? const <Object?>[])
            .whereType<String>(),
      );
    }
    properties.addAll(
      _mapOrNull(schema['properties']) ?? const <String, Object?>{},
    );
    required.addAll(
      (_listOrNull(schema['required']) ?? const <Object?>[])
          .whereType<String>(),
    );
    active.remove(schema);
    return <String, Object?>{
      'type': 'object',
      'properties': properties,
      'required': required.toList()..sort(),
    };
  }

  String _dartType(Object? raw, {required bool required}) {
    final direct = _mapOrNull(raw);
    if (direct?[r'$ref'] case final String ref) {
      final type = '${_pascal(_refName(ref))}Dto';
      return required && !_nullableSchema(direct!) ? type : '$type?';
    }
    final schema = _mapOrNull(_dereference(document, raw));
    if (schema == null) return required ? 'Object?' : 'Object?';
    String type;
    if (schema['oneOf'] != null) {
      type = 'Object';
    } else {
      type = switch (_schemaBaseType(schema)) {
        'boolean' => 'bool',
        'integer' => 'int',
        'number' => 'double',
        'string' => 'String',
        'array' => 'List<${_dartType(schema['items'], required: true)}>',
        'object' => 'Map<String, Object?>',
        _ => 'Object',
      };
    }
    if (!required || _nullableSchema(schema)) return '$type?';
    return type;
  }

  String _decodeExpression(
    Object? raw,
    String expression, {
    required bool required,
  }) {
    final nullable =
        !required ||
        _nullableSchema(_mapOrNull(raw) ?? const <String, Object?>{});
    final direct = _mapOrNull(raw);
    final ref = direct?[r'$ref'];
    String decode;
    if (ref is String) {
      final target = _mapOrNull(_dereference(document, raw));
      final name = '${_pascal(_refName(ref))}Dto';
      if (_listOrNull(target?['enum']) != null) {
        decode = '$name.fromJson($expression)';
      } else {
        decode =
            '$name.fromJson(($expression! as Map).cast<String, Object?>())';
      }
    } else {
      final schema =
          _mapOrNull(_dereference(document, raw)) ?? const <String, Object?>{};
      decode = switch (_schemaBaseType(schema)) {
        'boolean' => '$expression! as bool',
        'integer' => '$expression! as int',
        'number' => '($expression! as num).toDouble()',
        'string' => '$expression! as String',
        'array' =>
          '($expression! as List<Object?>).map((value) => ${_decodeExpression(schema['items'], 'value', required: true)}).toList(growable: false)',
        'object' => '($expression! as Map).cast<String, Object?>()',
        _ => expression,
      };
    }
    return nullable ? '$expression == null ? null : $decode' : decode;
  }

  String _encodeExpression(
    Object? raw,
    String expression, {
    bool nullable = false,
  }) {
    final direct = _mapOrNull(raw);
    if (direct?.containsKey(r'$ref') == true) {
      return '$expression${nullable ? '!' : ''}.toJson()';
    }
    final schema =
        _mapOrNull(_dereference(document, raw)) ?? const <String, Object?>{};
    if (_schemaBaseType(schema) == 'array') {
      final value = _encodeExpression(schema['items'], 'value');
      return '$expression${nullable ? '?' : ''}.map((value) => $value).toList(growable: false)';
    }
    return expression;
  }

  String _fixtureLiteral(Map<String, Object?> schema, Set<Object> active) {
    if (!active.add(schema)) return 'null';
    try {
      final enumValues = _listOrNull(schema['enum']);
      if (enumValues != null && enumValues.isNotEmpty) {
        return _literal(enumValues.first);
      }
      final oneOf = _listOrNull(schema['oneOf']);
      if (oneOf != null && oneOf.isNotEmpty) {
        final variant = _mapOrNull(_dereference(document, oneOf.first));
        return variant == null ? 'null' : _fixtureLiteral(variant, active);
      }
      if (_schemaBaseType(schema) == 'object' || schema['allOf'] != null) {
        final effective = _effectiveObjectSchema(schema, <Object>{});
        final properties =
            _mapOrNull(effective['properties']) ?? const <String, Object?>{};
        final required =
            (_listOrNull(effective['required']) ?? const <Object?>[])
                .whereType<String>()
                .toSet();
        final entries = properties.entries.where(
          (entry) => required.contains(entry.key),
        );
        return '<String, Object?>{${entries.map((entry) {
          final child = _mapOrNull(_dereference(document, entry.value)) ?? const <String, Object?>{};
          return '${_literal(entry.key)}: ${_fixtureLiteral(child, active)}';
        }).join(', ')}}';
      }
      return switch (_schemaBaseType(schema)) {
        'boolean' => 'false',
        'integer' => '0',
        'number' => '0.0',
        'string' => _literal('fixture'),
        'array' => 'const <Object?>[]',
        'object' => 'const <String, Object?>{}',
        _ => 'null',
      };
    } finally {
      active.remove(schema);
    }
  }

  String _routeExpression(_OperationIr operation) {
    var expression = operation.path;
    for (final parameter in operation.parameters.where(
      (parameter) => parameter.location == 'path',
    )) {
      expression = expression.replaceAll(
        '{${parameter.wireName}}',
        '\${Uri.encodeComponent(${parameter.dartName}.toString())}',
      );
    }
    return _literal(expression, interpolate: true);
  }
}

final class _OperationIr {
  const _OperationIr({
    required this.wireName,
    required this.name,
    required this.method,
    required this.path,
    required this.parameters,
    required this.bodySchema,
    required this.bodyType,
    required this.bodyRequired,
    required this.responses,
    required this.renderer,
  });

  final String wireName;
  final String name;
  final String method;
  final String path;
  final List<_ParameterIr> parameters;
  final Object? bodySchema;
  final String? bodyType;
  final bool bodyRequired;
  final Map<int, String> responses;
  final _OpenApiRenderer renderer;

  String bodyEncodeExpression(String expression) => renderer._encodeExpression(
    bodySchema,
    expression,
    nullable: !bodyRequired,
  );
}

final class _ParameterIr {
  const _ParameterIr({
    required this.wireName,
    required this.dartName,
    required this.location,
    required this.required,
    required this.type,
  });

  final String wireName;
  final String dartName;
  final String location;
  final bool required;
  final String type;
}

Object? _dereference(_OpenApiDocument document, Object? value) {
  var current = value;
  final seen = <String>{};
  while (current is Map<String, Object?>) {
    final ref = current[r'$ref'];
    if (ref is! String) break;
    if (!seen.add(ref)) return current;
    current = document.resolveRef(ref);
  }
  return current;
}

Object? _jsonSchemaFromContent(Map<String, Object?>? boundary) {
  final content = _mapOrNull(boundary?['content']);
  if (content == null) return null;
  for (final entry in content.entries) {
    if (_isJsonMediaType(entry.key)) {
      return _mapOrNull(entry.value)?['schema'];
    }
  }
  return null;
}

bool _isJsonMediaType(String value) =>
    value == 'application/json' ||
    value.startsWith('application/') && value.endsWith('+json');

bool _nullableSchema(Map<String, Object?> schema) =>
    schema['nullable'] == true ||
    schema['type'] is List<Object?> &&
        (schema['type']! as List<Object?>).contains('null');

String? _schemaBaseType(Map<String, Object?> schema) {
  final type = schema['type'];
  if (type is String) return type == 'null' ? null : type;
  if (type is List<Object?>) {
    return type.whereType<String>().firstWhere(
      (value) => value != 'null',
      orElse: () => 'object',
    );
  }
  if (schema.containsKey('properties') || schema.containsKey('allOf')) {
    return 'object';
  }
  if (schema.containsKey('items')) return 'array';
  return null;
}

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<Object?>? _listOrNull(Object? value) =>
    value is List<Object?> ? value : null;

Object? _plainYaml(Object? value) => switch (value) {
  final YamlMap map => <String, Object?>{
    for (final entry in map.entries)
      if (entry.key is String) entry.key! as String: _plainYaml(entry.value),
  },
  final YamlList list => <Object?>[for (final item in list) _plainYaml(item)],
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries)
      if (entry.key is String) entry.key! as String: _plainYaml(entry.value),
  },
  final List<Object?> list => <Object?>[
    for (final item in list) _plainYaml(item),
  ],
  _ => value,
};

String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _canonicalValue(item)];
  }
  return value;
}

String _refName(String ref) {
  final fragment = ref.split('#').last;
  final parts = fragment.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? 'Value' : Uri.decodeComponent(parts.last);
}

String _snake(String value) {
  final words = _words(value);
  return words.isEmpty
      ? 'open_api'
      : words.map((word) => word.toLowerCase()).join('_');
}

String _pascal(String value) {
  final words = _words(value);
  final result = words.isEmpty
      ? 'OpenApi'
      : words
            .map(
              (word) =>
                  '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}',
            )
            .join();
  return RegExp(r'^[0-9]').hasMatch(result) ? 'Value$result' : result;
}

String _camel(String value) {
  final pascal = _pascal(value);
  final result =
      '${pascal.substring(0, 1).toLowerCase()}${pascal.substring(1)}';
  return _dartKeywords.contains(result) ? '${result}Value' : result;
}

String _identifier(String value, {String fallback = 'value'}) {
  final result = _camel(value);
  if (result.isEmpty) return fallback;
  return _dartKeywords.contains(result) ? '${result}Value' : result;
}

List<String> _words(String value) {
  final spaced = value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim();
  return spaced.isEmpty
      ? const <String>[]
      : spaced.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
}

String _literal(Object? value, {bool interpolate = false}) {
  if (value is String) {
    var encoded = jsonEncode(value);
    if (!interpolate) encoded = encoded.replaceAll(r'$', r'\$');
    return encoded;
  }
  return jsonEncode(value);
}

String _pointer(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');

String _portable(String value) => value.replaceAll('\\', '/');

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

bool _within(String candidate, String boundary) {
  final normalizedCandidate = _portable(File(candidate).absolute.path);
  final normalizedBoundary = _portable(Directory(boundary).absolute.path);
  final comparedCandidate = _pathForComparison(normalizedCandidate);
  final comparedBoundary = _pathForComparison(normalizedBoundary);
  return comparedCandidate == comparedBoundary ||
      comparedCandidate.startsWith('$comparedBoundary/');
}

String _relative(String root, String target) {
  final boundary = _portable(Directory(root).absolute.path);
  final absolute = _portable(File(target).absolute.path);
  final prefix = '$boundary/';
  return _pathForComparison(absolute).startsWith(_pathForComparison(prefix))
      ? absolute.substring(prefix.length)
      : absolute;
}

String _pathForComparison(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;

const _dartKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};
