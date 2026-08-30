import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';

import '../config/dartitect_config.dart';

const _annotationLibrary =
    'package:dartitect/src/extensions/local_extension.dart';
const _annotationName = 'DartitectProjectExtension';
const _interfaceName = 'DartitectLocalExtension';

/// Semantic, renderer-neutral declaration for one local extension binding.
final class DartitectLocalExtensionIr {
  /// Creates one validated extension declaration.
  const DartitectLocalExtensionIr({
    required this.sourcePath,
    required this.libraryUri,
    required this.declarationType,
    required this.bindingType,
    required this.bindingLibraryUris,
    required this.fieldName,
  });

  /// Project-relative source named by config v2.
  final String sourcePath;

  /// Importable package URI containing the declaration.
  final String libraryUri;

  /// Concrete annotated declaration class.
  final String declarationType;

  /// Concrete `B` from `DartitectLocalExtension<B>`.
  final String bindingType;

  /// Package imports required by the binding type and its type arguments.
  final List<String> bindingLibraryUris;

  /// Generated application-graph field name.
  final String fieldName;

  /// Stable semantic signature used by managed generation.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': sourcePath,
    'library': libraryUri,
    'declarationType': declarationType,
    'bindingType': bindingType,
    'bindingLibraries': bindingLibraryUris,
    'field': fieldName,
  };
}

/// Analyzer-backed compiler for confined project-local extension sources.
///
/// This compiler reads and resolves Dart source only. It never imports a Dart
/// library into the CLI isolate, invokes a constructor, or loads a plugin.
final class DartitectLocalExtensionCompiler {
  /// Creates a compiler confined to [root].
  DartitectLocalExtensionCompiler(Directory root) : root = root.absolute;

  /// Consumer project boundary.
  final Directory root;

  /// Resolves, validates, and deterministically orders [sources].
  Future<List<DartitectLocalExtensionIr>> compile(
    Iterable<String> sources,
  ) async {
    final requested = sources.toList()..sort();
    if (requested.isEmpty) return const <DartitectLocalExtensionIr>[];
    final boundary = await root.resolveSymbolicLinks();
    final files = <({String relative, File file})>[];
    for (var index = 0; index < requested.length; index += 1) {
      final relative = requested[index];
      final file = File(_join(root.path, relative));
      if (!await file.exists()) {
        throw DartitectConfigException(
          '/extensionSources/$index',
          'extension source does not exist',
        );
      }
      final resolved = File(await file.resolveSymbolicLinks());
      if (!_isWithin(resolved.path, boundary)) {
        throw DartitectConfigException(
          '/extensionSources/$index',
          'extension source resolves outside the project boundary',
        );
      }
      files.add((relative: relative, file: resolved));
    }

    final collection = AnalysisContextCollection(
      includedPaths: <String>[boundary],
      excludedPaths: <String>[
        _join(boundary, '.dart_tool'),
        _join(boundary, 'build'),
      ],
    );
    final output = <DartitectLocalExtensionIr>[];
    try {
      for (var index = 0; index < files.length; index += 1) {
        final candidate = files[index];
        final result = await collection
            .contextFor(candidate.file.path)
            .currentSession
            .getResolvedUnit(candidate.file.path);
        if (result is! ResolvedUnitResult) {
          throw DartitectConfigException(
            '/extensionSources/$index',
            'Analyzer could not resolve the extension source',
          );
        }
        final error = result.diagnostics
            .where((diagnostic) => diagnostic.severity == Severity.error)
            .firstOrNull;
        if (error != null) {
          throw DartitectConfigException(
            '/extensionSources/$index',
            'extension source has analyzer error '
                '${error.diagnosticCode.lowerCaseName}',
          );
        }
        final uri = result.libraryElement.uri.toString();
        if (!uri.startsWith('package:')) {
          throw DartitectConfigException(
            '/extensionSources/$index',
            'extension sources must be importable from a package lib directory',
          );
        }
        final declarations = result.unit.declarations
            .whereType<ClassDeclaration>()
            .where(_hasLexicalAnnotation)
            .toList();
        if (declarations.isEmpty) {
          throw DartitectConfigException(
            '/extensionSources/$index',
            'expected at least one @DartitectProjectExtension declaration',
          );
        }
        for (final declaration in declarations) {
          output.add(
            _compileDeclaration(
              declaration,
              sourcePath: candidate.relative,
              libraryUri: uri,
              pointer: '/extensionSources/$index',
            ),
          );
        }
      }
    } finally {
      await collection.dispose();
    }
    output.sort((left, right) {
      final byField = left.fieldName.compareTo(right.fieldName);
      return byField != 0
          ? byField
          : left.declarationType.compareTo(right.declarationType);
    });
    final fields = <String>{'sessions', 'scheduler', 'observability'};
    final declarationTypes = <String>{};
    for (final extension in output) {
      if (!fields.add(extension.fieldName)) {
        throw DartitectConfigException(
          '/extensionSources',
          'extension field collision or reserved field for ${extension.fieldName}',
        );
      }
      if (!declarationTypes.add(extension.declarationType)) {
        throw DartitectConfigException(
          '/extensionSources',
          'extension declaration name collision for ${extension.declarationType}',
        );
      }
    }
    return List<DartitectLocalExtensionIr>.unmodifiable(output);
  }

  static DartitectLocalExtensionIr _compileDeclaration(
    ClassDeclaration declaration, {
    required String sourcePath,
    required String libraryUri,
    required String pointer,
  }) {
    final annotation = declaration.metadata
        .where(_isSemanticAnnotation)
        .singleOrNull;
    if (annotation == null) {
      final lexical = declaration.metadata.firstWhere(_isLexicalAnnotation);
      final element = lexical.element;
      final resolved = element == null
          ? 'an unresolved element'
          : '${element.library?.uri}/${element.enclosingElement?.displayName}';
      throw DartitectConfigException(
        pointer,
        '$_annotationName must resolve to package:dartitect, not $resolved',
      );
    }
    final element = declaration.declaredFragment?.element;
    if (element == null || !element.isFinal || element.isAbstract) {
      throw DartitectConfigException(
        pointer,
        'local extension declarations must be concrete final classes',
      );
    }
    if (element.name == null || element.name!.startsWith('_')) {
      throw DartitectConfigException(
        pointer,
        'local extension declarations must be public',
      );
    }
    if (element.typeParameters.isNotEmpty) {
      throw DartitectConfigException(
        pointer,
        'local extension declarations cannot be generic',
      );
    }
    final constructor = element.unnamedConstructor;
    if (constructor == null ||
        constructor.formalParameters.any(
          (parameter) =>
              parameter.isRequiredNamed || parameter.isRequiredPositional,
        )) {
      throw DartitectConfigException(
        pointer,
        'local extension declarations require an unnamed zero-argument constructor',
      );
    }
    final contract = element.allSupertypes
        .where(
          (type) =>
              type.element.name == _interfaceName &&
              type.element.library.uri.toString() == _annotationLibrary,
        )
        .singleOrNull;
    if (contract == null || contract.typeArguments.length != 1) {
      throw DartitectConfigException(
        pointer,
        'local extensions must implement $_interfaceName<B>',
      );
    }
    final binding = contract.typeArguments.single;
    if (binding is DynamicType ||
        binding is TypeParameterType ||
        binding.nullabilitySuffix == NullabilitySuffix.question ||
        binding.getDisplayString() == 'Object' ||
        binding.getDisplayString() == 'Object?') {
      throw DartitectConfigException(
        pointer,
        'extension binding B must be a concrete non-nullable type',
      );
    }
    final libraries = <String>{};
    _collectLibraries(binding, libraries);
    libraries.remove('dart:core');
    libraries.remove(libraryUri);
    if (libraries.any((uri) => !uri.startsWith('package:'))) {
      throw DartitectConfigException(
        pointer,
        'extension binding types must be importable package types',
      );
    }
    final className = element.name!;
    return DartitectLocalExtensionIr(
      sourcePath: sourcePath,
      libraryUri: libraryUri,
      declarationType: className,
      bindingType: binding.getDisplayString(),
      bindingLibraryUris: libraries.toList()..sort(),
      fieldName: _fieldName(className),
    );
  }

  static void _collectLibraries(DartType type, Set<String> output) {
    if (type is InterfaceType) {
      output.add(type.element.library.uri.toString());
    }
    if (type is ParameterizedType) {
      for (final argument in type.typeArguments) {
        _collectLibraries(argument, output);
      }
    }
  }

  static bool _hasLexicalAnnotation(ClassDeclaration declaration) =>
      declaration.metadata.any(_isLexicalAnnotation);

  static bool _isLexicalAnnotation(Annotation annotation) =>
      annotation.name.toSource().split('.').last == _annotationName;

  static bool _isSemanticAnnotation(Annotation annotation) {
    final element = annotation.element;
    return element?.library?.uri.toString() == _annotationLibrary &&
        element?.enclosingElement?.displayName == _annotationName;
  }

  static String _fieldName(String declarationType) {
    var stem = declarationType;
    for (final suffix in const <String>['LocalExtension', 'Extension']) {
      if (stem.endsWith(suffix) && stem.length > suffix.length) {
        stem = stem.substring(0, stem.length - suffix.length);
        break;
      }
    }
    final words = stem
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match[1]}_${match[2]}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Z]+)([A-Z][a-z])'),
          (match) => '${match[1]}_${match[2]}',
        )
        .toLowerCase()
        .split('_')
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'extensionBinding';
    return words.first +
        words
            .skip(1)
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join();
  }
}

bool _isWithin(String path, String boundary) {
  final normalizedPath = path.replaceAll('\\', '/');
  final normalizedBoundary = boundary.replaceAll('\\', '/');
  final prefix = normalizedBoundary.endsWith('/')
      ? normalizedBoundary
      : '$normalizedBoundary/';
  if (Platform.isWindows) {
    return normalizedPath.toLowerCase().startsWith(prefix.toLowerCase());
  }
  return normalizedPath.startsWith(prefix);
}

String _join(String left, String right) =>
    '${left.replaceAll(RegExp(r'[\\/]+$'), '')}/$right';
