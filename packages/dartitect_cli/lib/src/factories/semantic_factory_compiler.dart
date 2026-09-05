import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:dartitect/dartitect.dart' show FeatureProfile;
import 'package:yaml/yaml.dart';

import '../config/dartitect_config.dart';

const _annotationLibrary =
    'package:dartitect/src/factories/factory_annotations.dart';

/// Closed role of one consumer-owned factory declaration.
enum DartitectSemanticFactoryRole {
  /// Opens one storage context.
  storage,

  /// Opens one transport context.
  transport,

  /// Constructs authenticated session roots.
  session,

  /// Supplies domain/application seams for one feature.
  feature,
}

/// Statically resolved cleanup contract for one factory method result.
enum DartitectFactoryDisposalKind {
  /// The value is borrowed or has no Dartitect lifecycle contract.
  none,

  /// The value implements `Disposable`.
  synchronous,

  /// The value implements `AsyncDisposable`.
  asynchronous,
}

/// Renderer-neutral method signature resolved by Analyzer.
final class DartitectFactoryMethodIr {
  /// Creates an immutable semantic method signature.
  const DartitectFactoryMethodIr({
    required this.name,
    required this.returnType,
    required this.valueType,
    required this.parameters,
    required this.libraryUris,
    required this.disposalKind,
  });

  /// Public instance method name.
  final String name;

  /// Concrete non-nullable return type, preserving `Future<T>` when declared.
  final String returnType;

  /// Return type with one `Future`/`FutureOr` layer removed.
  final String valueType;

  /// Concrete parameters in declaration order.
  final List<DartitectFactoryParameterIr> parameters;

  /// Package imports needed by the signature.
  final List<String> libraryUris;

  /// Compile-time lifecycle contract implemented by [valueType].
  final DartitectFactoryDisposalKind disposalKind;

  /// Stable semantic representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'returnType': returnType,
    'valueType': valueType,
    'parameters': parameters.map((parameter) => parameter.toJson()).toList(),
    'libraries': libraryUris,
    'disposalKind': disposalKind.name,
  };
}

/// One semantically resolved factory-method parameter.
final class DartitectFactoryParameterIr {
  /// Creates immutable parameter IR.
  const DartitectFactoryParameterIr({
    required this.name,
    required this.type,
    required this.named,
    required this.required,
  });

  /// Source parameter name.
  final String name;

  /// Concrete non-nullable type.
  final String type;

  /// Whether invocation must use a name.
  final bool named;

  /// Whether omission is prohibited.
  final bool required;

  /// Stable semantic representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type,
    'named': named,
    'required': required,
  };
}

/// One validated, statically linked factory declaration.
final class DartitectSemanticFactoryIr {
  /// Creates immutable factory IR.
  const DartitectSemanticFactoryIr({
    required this.role,
    required this.bindingName,
    required this.sourcePath,
    required this.libraryUri,
    required this.declarationType,
    required this.methods,
  });

  /// Config role served by this declaration.
  final DartitectSemanticFactoryRole role;

  /// Context or feature registry key; `session` for the session root.
  final String bindingName;

  /// Confined project-relative source.
  final String sourcePath;

  /// Importable package URI.
  final String libraryUri;

  /// Public concrete declaration type.
  final String declarationType;

  /// Required methods keyed by name.
  final Map<String, DartitectFactoryMethodIr> methods;

  /// Stable semantic signature used by renderer ownership.
  Map<String, Object?> toJson() => <String, Object?>{
    'role': role.name,
    'bindingName': bindingName,
    'source': sourcePath,
    'library': libraryUri,
    'declarationType': declarationType,
    'methods': <String, Object?>{
      for (final entry in methods.entries) entry.key: entry.value.toJson(),
    },
  };
}

/// Analyzer-backed compiler for config-v3 factory sources.
///
/// Sources are resolved as Dart libraries only. No declaration is imported,
/// instantiated, reflected, or executed in the CLI isolate.
final class DartitectSemanticFactoryCompiler {
  /// Creates a compiler confined to [root].
  DartitectSemanticFactoryCompiler(Directory root) : root = root.absolute;

  /// Consumer project boundary.
  final Directory root;

  /// Validates every factory referenced by [config].
  Future<List<DartitectSemanticFactoryIr>> compile(
    DartitectConfig config,
  ) async {
    final requests = _requests(config);
    if (requests.isEmpty) return const <DartitectSemanticFactoryIr>[];
    final boundary = await root.resolveSymbolicLinks();
    final packageName = await _readPackageName(requests.first.pointer);
    // Only explicit factory roots are analysis entrypoints. Dependencies still
    // resolve normally, but unrelated generated libraries are not scheduled in
    // every fresh inspection session.
    final sourcePaths = <String, String>{};
    for (final request in requests) {
      final source = request.source;
      if (sourcePaths.containsKey(source.source)) continue;
      final file = File(_join(root.path, source.source));
      if (!await file.exists()) {
        throw DartitectConfigException(
          '${request.pointer}/source',
          'factory source does not exist',
        );
      }
      final resolvedPath = await file.resolveSymbolicLinks();
      if (!_isWithin(resolvedPath, boundary)) {
        throw DartitectConfigException(
          '${request.pointer}/source',
          'factory source resolves outside the project boundary',
        );
      }
      sourcePaths[source.source] = resolvedPath;
    }
    final collection = AnalysisContextCollection(
      includedPaths: sourcePaths.values.toSet().toList(),
      excludedPaths: <String>[
        _join(boundary, '.dart_tool'),
        _join(boundary, 'build'),
      ],
    );
    final results = <String, ResolvedUnitResult>{};
    final output = <DartitectSemanticFactoryIr>[];
    try {
      for (final request in requests) {
        final resolvedPath = sourcePaths[request.source.source]!;
        var result = results[resolvedPath];
        if (result == null) {
          final analysis = await collection
              .contextFor(resolvedPath)
              .currentSession
              .getResolvedUnit(resolvedPath);
          if (analysis is! ResolvedUnitResult) {
            throw DartitectConfigException(
              request.pointer,
              'Analyzer could not resolve the factory source',
            );
          }
          final diagnostic = analysis.diagnostics
              .where((item) => item.severity == Severity.error)
              .firstOrNull;
          if (diagnostic != null) {
            throw DartitectConfigException(
              request.pointer,
              'factory source has analyzer error '
              '${diagnostic.diagnosticCode.lowerCaseName}',
            );
          }
          result = analysis;
          results[resolvedPath] = result;
        }
        output.add(
          _compileRequest(
            request,
            result,
            packageName: packageName,
            boundary: boundary,
            originalBoundary: root.path,
          ),
        );
      }
    } finally {
      await collection.dispose();
    }
    output.sort((left, right) {
      final byRole = left.role.index.compareTo(right.role.index);
      return byRole != 0
          ? byRole
          : left.bindingName.compareTo(right.bindingName);
    });
    return List<DartitectSemanticFactoryIr>.unmodifiable(output);
  }

  Future<String> _readPackageName(String pointer) async {
    final pubspec = File(_join(root.path, 'pubspec.yaml'));
    if (!await pubspec.exists()) {
      throw DartitectConfigException(
        pointer,
        'factory sources require a package pubspec.yaml',
      );
    }
    Object? decoded;
    try {
      decoded = loadYaml(await pubspec.readAsString());
    } on YamlException {
      throw DartitectConfigException(
        pointer,
        'factory sources require a valid package pubspec.yaml',
      );
    }
    final name = decoded is YamlMap ? decoded['name'] : null;
    if (name is! String || !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(name)) {
      throw DartitectConfigException(
        pointer,
        'factory sources require a valid pubspec package name',
      );
    }
    return name;
  }

  static DartitectSemanticFactoryIr _compileRequest(
    _FactoryRequest request,
    ResolvedUnitResult result, {
    required String packageName,
    required String boundary,
    required String originalBoundary,
  }) {
    final sourcePath = request.source.source;
    if (!sourcePath.startsWith('lib/') || sourcePath.length == 4) {
      throw DartitectConfigException(
        request.pointer,
        'factory sources must be importable from a package lib directory',
      );
    }
    final analyzedLibraryUri = result.libraryElement.uri.toString();
    final libraryUri = 'package:$packageName/${sourcePath.substring(4)}';
    final declaration = result.unit.declarations
        .whereType<ClassDeclaration>()
        .where(
          (candidate) =>
              candidate.declaredFragment?.element.name ==
              request.source.declaration,
        )
        .singleOrNull;
    if (declaration == null) {
      throw DartitectConfigException(
        '${request.pointer}/declaration',
        'factory declaration was not found in its source',
      );
    }
    final element = declaration.declaredFragment?.element;
    if (element == null || !element.isFinal || element.isAbstract) {
      throw DartitectConfigException(
        request.pointer,
        'factory declarations must be concrete final classes',
      );
    }
    if (element.typeParameters.isNotEmpty) {
      throw DartitectConfigException(
        request.pointer,
        'factory declarations cannot be generic',
      );
    }
    final constructor = element.unnamedConstructor;
    if (constructor == null ||
        constructor.formalParameters.any(
          (parameter) =>
              parameter.isRequiredNamed || parameter.isRequiredPositional,
        )) {
      throw DartitectConfigException(
        request.pointer,
        'factory declarations require an unnamed zero-argument constructor',
      );
    }
    final annotation = declaration.metadata
        .where(
          (candidate) =>
              candidate.element?.library?.uri.toString() ==
                  _annotationLibrary &&
              candidate.element?.enclosingElement?.displayName ==
                  request.annotation,
        )
        .singleOrNull;
    if (annotation == null) {
      throw DartitectConfigException(
        request.pointer,
        'expected @${request.annotation} resolved from package:dartitect',
      );
    }
    final annotationValue = annotation.elementAnnotation
        ?.computeConstantValue();
    final declaredBinding = annotationValue
        ?.getField(request.annotationField)
        ?.toStringValue();
    if (request.annotationField.isNotEmpty &&
        declaredBinding != request.bindingName) {
      throw DartitectConfigException(
        request.pointer,
        '@${request.annotation} must name "${request.bindingName}"',
      );
    }

    final methods = <String, DartitectFactoryMethodIr>{};
    for (final methodName in request.requiredMethods) {
      final method = element.methods
          .where(
            (candidate) =>
                candidate.name == methodName &&
                !candidate.isStatic &&
                candidate.isPublic,
          )
          .singleOrNull;
      if (method == null) {
        throw DartitectConfigException(
          request.pointer,
          '${request.source.declaration} must declare $methodName()',
        );
      }
      _validateConcreteType(
        method.returnType,
        request.pointer,
        '$methodName return type',
        allowVoid: methodName == 'dispose',
      );
      if (methodName == 'createViewModel' && _isAsyncType(method.returnType)) {
        throw DartitectConfigException(
          request.pointer,
          'createViewModel() must return a concrete ViewModel synchronously',
        );
      }
      if (methodName == 'watch' && !_isStreamOfVoid(method.returnType)) {
        throw DartitectConfigException(
          request.pointer,
          'watch() must return Stream<void>',
        );
      }
      if (methodName == 'read' && !_isFutureOfResult(method.returnType)) {
        throw DartitectConfigException(
          request.pointer,
          'read() must return Future<Result<T, F>>',
        );
      }
      for (final parameter in method.formalParameters) {
        _validateConcreteType(
          parameter.type,
          request.pointer,
          '$methodName parameter ${parameter.name}',
        );
      }
      final libraries = <String>{};
      _collectLibraries(method.returnType, libraries);
      for (final parameter in method.formalParameters) {
        _collectLibraries(parameter.type, libraries);
      }
      final publicLibraries = libraries
          .map(
            (uri) => _importableLibraryUri(
              uri,
              analyzedLibraryUri: analyzedLibraryUri,
              analyzedLibraryReplacement: libraryUri,
              packageName: packageName,
              boundaries: <String>[boundary, originalBoundary],
            ),
          )
          .toSet();
      publicLibraries
        ..remove('dart:core')
        ..remove('dart:async')
        ..remove(libraryUri);
      if (publicLibraries.any((uri) => !uri.startsWith('package:'))) {
        throw DartitectConfigException(
          request.pointer,
          '$methodName uses a type that generated code cannot import',
        );
      }
      methods[methodName] = DartitectFactoryMethodIr(
        name: methodName,
        returnType: method.returnType.getDisplayString(),
        valueType: _unwrapFuture(method.returnType).getDisplayString(),
        parameters: <DartitectFactoryParameterIr>[
          for (final parameter in method.formalParameters)
            DartitectFactoryParameterIr(
              name: parameter.name ?? '',
              type: parameter.type.getDisplayString(),
              named: parameter.isNamed,
              required:
                  parameter.isRequiredNamed || parameter.isRequiredPositional,
            ),
        ],
        libraryUris: publicLibraries.toList()..sort(),
        disposalKind: _disposalKind(method.returnType),
      );
    }
    if (methods['client'] case final client?
        when client.valueType != 'DioJsonClient') {
      throw DartitectConfigException(
        request.pointer,
        'client() must return DioJsonClient',
      );
    }
    if (request.role == DartitectSemanticFactoryRole.storage ||
        request.role == DartitectSemanticFactoryRole.transport) {
      final open = element.methods.singleWhere(
        (method) => method.name == 'open' && !method.isStatic,
      );
      final dispose = element.methods.singleWhere(
        (method) => method.name == 'dispose' && !method.isStatic,
      );
      if (dispose.formalParameters.length != 1) {
        throw DartitectConfigException(
          request.pointer,
          'dispose() must accept exactly the context returned by open()',
        );
      }
      final opened = _unwrapFuture(open.returnType);
      if (opened.getDisplayString() !=
          dispose.formalParameters.single.type.getDisplayString()) {
        throw DartitectConfigException(
          request.pointer,
          'dispose() parameter must exactly match the context returned by open()',
        );
      }
    }
    return DartitectSemanticFactoryIr(
      role: request.role,
      bindingName: request.bindingName,
      sourcePath: request.source.source,
      libraryUri: libraryUri,
      declarationType: request.source.declaration,
      methods: Map<String, DartitectFactoryMethodIr>.unmodifiable(methods),
    );
  }

  static List<_FactoryRequest> _requests(DartitectConfig config) {
    final output = <_FactoryRequest>[];
    final contractTransports = config.contracts.values
        .map((contract) => contract.transport)
        .toSet();
    for (final entry in config.storageContexts.entries) {
      output.add(
        _FactoryRequest(
          role: DartitectSemanticFactoryRole.storage,
          bindingName: entry.key,
          source: entry.value.factorySource,
          pointer: '/storageContexts/${_pointer(entry.key)}/factorySource',
          annotation: entry.value.scope == FeatureScope.application
              ? 'DartitectApplicationContextFactory'
              : 'DartitectSessionContextFactory',
          annotationField: 'context',
          requiredMethods: const <String>{'open', 'dispose'},
        ),
      );
    }
    for (final entry in config.transports.entries) {
      output.add(
        _FactoryRequest(
          role: DartitectSemanticFactoryRole.transport,
          bindingName: entry.key,
          source: entry.value.factorySource,
          pointer: '/transports/${_pointer(entry.key)}/factorySource',
          annotation: 'DartitectTransportContextFactory',
          annotationField: 'context',
          requiredMethods: <String>{
            'open',
            'dispose',
            if (contractTransports.contains(entry.key)) 'client',
          },
        ),
      );
    }
    if (config.session case final session?) {
      output.add(
        _FactoryRequest(
          role: DartitectSemanticFactoryRole.session,
          bindingName: 'session',
          source: session.factorySource,
          pointer: '/session/factorySource',
          annotation: 'DartitectSessionFactory',
          annotationField: '',
          requiredMethods: const <String>{'create'},
        ),
      );
    }
    for (final entry in config.features.declarations.entries) {
      final declaration = entry.value;
      final methods = <String>{'createRepository', 'createViewModel'};
      if (declaration.storageContext != null) methods.add('createLocalPort');
      if (declaration.transport != null) {
        methods
          ..add('createRemotePort')
          ..add('createMapper');
      }
      if (declaration.localAuthority ==
          FeatureLocalAuthorityStrategy.generatedPull) {
        methods
          ..add('watch')
          ..add('read');
      } else if (declaration.storageContext != null) {
        methods.add('createLocalAuthority');
      }
      if (declaration.profile == FeatureProfile.replica ||
          declaration.profile == FeatureProfile.offlineFull) {
        methods
          ..add('createDataset')
          ..add('createCheckpointStore');
      }
      if (declaration.profile == FeatureProfile.offlineFull) {
        methods
          ..add('createOutboxStore')
          ..add('createIdempotencyPolicy')
          ..add('createConflictPolicy')
          ..add('synchronizeMutation')
          ..add('classifyMutationFailure');
      }
      output.add(
        _FactoryRequest(
          role: DartitectSemanticFactoryRole.feature,
          bindingName: entry.key,
          source: declaration.factorySource,
          pointer:
              '/features/declarations/${_pointer(entry.key)}/factorySource',
          annotation: 'DartitectFeatureFactory',
          annotationField: 'feature',
          requiredMethods: methods,
        ),
      );
    }
    output.sort((left, right) {
      final bySource = left.source.source.compareTo(right.source.source);
      return bySource != 0
          ? bySource
          : left.source.declaration.compareTo(right.source.declaration);
    });
    return output;
  }
}

final class _FactoryRequest {
  const _FactoryRequest({
    required this.role,
    required this.bindingName,
    required this.source,
    required this.pointer,
    required this.annotation,
    required this.annotationField,
    required this.requiredMethods,
  });

  final DartitectSemanticFactoryRole role;
  final String bindingName;
  final DartitectFactorySourceConfig source;
  final String pointer;
  final String annotation;
  final String annotationField;
  final Set<String> requiredMethods;
}

String _publicLibraryUri(String uri) {
  if (uri.startsWith('package:dartitect/src/')) {
    return 'package:dartitect/dartitect.dart';
  }
  if (uri.startsWith('package:dartitect_sync/src/')) {
    return 'package:dartitect_sync/dartitect_sync.dart';
  }
  if (uri.startsWith('package:dartitect_flutter/src/reactive/')) {
    return 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
  }
  if (uri.startsWith('package:dartitect_flutter/src/forms/')) {
    return 'package:dartitect_flutter/dartitect_flutter_forms.dart';
  }
  if (uri.startsWith('package:dartitect_flutter/src/queries/')) {
    return 'package:dartitect_flutter/dartitect_flutter_queries.dart';
  }
  if (uri.startsWith('package:dartitect_flutter/src/')) {
    return 'package:dartitect_flutter/dartitect_flutter.dart';
  }
  if (uri.startsWith('package:dartitect_dio/src/')) {
    return 'package:dartitect_dio/dartitect_dio.dart';
  }
  return uri;
}

String _importableLibraryUri(
  String uri, {
  required String analyzedLibraryUri,
  required String analyzedLibraryReplacement,
  required String packageName,
  required List<String> boundaries,
}) {
  if (uri == analyzedLibraryUri) return analyzedLibraryReplacement;
  final publicUri = _publicLibraryUri(uri);
  final parsed = Uri.tryParse(publicUri);
  if (parsed == null || parsed.scheme != 'file') return publicUri;
  final path = File.fromUri(parsed).absolute.path;
  for (final boundary in boundaries) {
    final relative = _relativeWithin(path, _join(boundary, 'lib'));
    if (relative != null && relative.isNotEmpty) {
      return 'package:$packageName/$relative';
    }
  }
  return publicUri;
}

String? _relativeWithin(String path, String boundary) {
  final normalizedPath = path
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  final normalizedBoundary = boundary
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  final comparablePath = Platform.isWindows
      ? normalizedPath.toLowerCase()
      : normalizedPath;
  final comparableBoundary = Platform.isWindows
      ? normalizedBoundary.toLowerCase()
      : normalizedBoundary;
  final prefix = '$comparableBoundary/';
  if (!comparablePath.startsWith(prefix)) return null;
  return normalizedPath.substring(normalizedBoundary.length + 1);
}

void _validateConcreteType(
  DartType type,
  String pointer,
  String description, {
  bool allowVoid = false,
  bool nested = false,
}) {
  final unwrapped = _unwrapFuture(type);
  if ((allowVoid || nested) && unwrapped is VoidType) return;
  if (unwrapped is DynamicType ||
      unwrapped is TypeParameterType ||
      unwrapped is VoidType ||
      unwrapped.nullabilitySuffix == NullabilitySuffix.question ||
      unwrapped.getDisplayString() == 'Object' ||
      unwrapped.getDisplayString() == 'Object?') {
    throw DartitectConfigException(
      pointer,
      '$description must be concrete and non-nullable',
    );
  }
  if (unwrapped is ParameterizedType) {
    for (final argument in unwrapped.typeArguments) {
      _validateConcreteType(argument, pointer, description, nested: true);
    }
  }
}

DartType _unwrapFuture(DartType type) {
  if (type is InterfaceType &&
      type.element.library.uri.toString() == 'dart:async' &&
      (type.element.name == 'Future' || type.element.name == 'FutureOr') &&
      type.typeArguments.length == 1) {
    return type.typeArguments.single;
  }
  return type;
}

bool _isAsyncType(DartType type) =>
    type is InterfaceType &&
    type.element.library.uri.toString() == 'dart:async' &&
    (type.element.name == 'Future' || type.element.name == 'FutureOr');

bool _isStreamOfVoid(DartType type) =>
    type is InterfaceType &&
    type.element.library.uri.toString() == 'dart:async' &&
    type.element.name == 'Stream' &&
    type.typeArguments.length == 1 &&
    type.typeArguments.single is VoidType;

bool _isFutureOfResult(DartType type) {
  if (type is! InterfaceType ||
      type.element.library.uri.toString() != 'dart:async' ||
      type.element.name != 'Future' ||
      type.typeArguments.length != 1) {
    return false;
  }
  final result = type.typeArguments.single;
  return result is InterfaceType &&
      result.element.library.uri.toString() ==
          'package:dartitect/src/result.dart' &&
      result.element.name == 'Result' &&
      result.typeArguments.length == 2;
}

DartitectFactoryDisposalKind _disposalKind(DartType type) {
  final value = _unwrapFuture(type);
  if (value is! InterfaceType) return DartitectFactoryDisposalKind.none;
  final interfaces = <InterfaceType>[value, ...value.allSupertypes];
  bool implementsContract(String name) => interfaces.any(
    (candidate) =>
        candidate.element.name == name &&
        candidate.element.library.uri.toString() ==
            'package:dartitect/src/lifecycle/contracts.dart',
  );
  if (implementsContract('AsyncDisposable')) {
    return DartitectFactoryDisposalKind.asynchronous;
  }
  if (implementsContract('Disposable')) {
    return DartitectFactoryDisposalKind.synchronous;
  }
  return DartitectFactoryDisposalKind.none;
}

void _collectLibraries(DartType type, Set<String> output) {
  if (type is InterfaceType) output.add(type.element.library.uri.toString());
  if (type is ParameterizedType) {
    for (final argument in type.typeArguments) {
      _collectLibraries(argument, output);
    }
  }
}

bool _isWithin(String path, String boundary) {
  final normalizedPath = path.replaceAll('\\', '/');
  final normalizedBoundary = boundary.replaceAll('\\', '/');
  final prefix = normalizedBoundary.endsWith('/')
      ? normalizedBoundary
      : '$normalizedBoundary/';
  return Platform.isWindows
      ? normalizedPath.toLowerCase().startsWith(prefix.toLowerCase())
      : normalizedPath.startsWith(prefix);
}

String _join(String left, String right) =>
    '${left.replaceAll(RegExp(r'[\\/]+$'), '')}/$right';

String _pointer(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  T? get singleOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    final value = iterator.current;
    return iterator.moveNext() ? null : value;
  }
}
