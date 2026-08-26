import 'dart:convert';
import 'dart:io';

import 'generated_boundary_policy.dart';

/// Resolves stable-v1 boundary configuration for an analyzer source file.
///
/// The nearest `dartitect.json` wins. Paths are made relative to that file so
/// the analyzer host applies the same project-relative globs as CLI scans on
/// POSIX and Windows hosts.
final class DartitectLintBoundaryResolver {
  const DartitectLintBoundaryResolver._();

  /// Classifies [sourcePath] with its nearest valid stable-v1 configuration.
  static DartitectSourceClassification classify(String sourcePath) {
    final resolved = _resolve(sourcePath);
    return resolved.classifier.classify(
      _relativePath(resolved.rootPath, sourcePath),
    );
  }

  static _ResolvedBoundaryPolicy _resolve(String sourcePath) {
    var directory = File(sourcePath).absolute.parent;
    while (true) {
      final config = File(
        '${directory.path}${Platform.pathSeparator}dartitect.json',
      );
      if (config.existsSync()) {
        DartitectBoundaryClassifier? classifier;
        try {
          classifier = _parse(config.readAsStringSync());
        } on FileSystemException {
          classifier = null;
        }
        return _ResolvedBoundaryPolicy(
          rootPath: directory.absolute.path,
          classifier: classifier ?? DartitectBoundaryClassifier.defaults(),
        );
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }

    return _ResolvedBoundaryPolicy(
      rootPath: _defaultPackageRoot(sourcePath),
      classifier: DartitectBoundaryClassifier.defaults(),
    );
  }

  static DartitectBoundaryClassifier? _parse(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> ||
          decoded['configVersion'] != 1 ||
          decoded['profile'] != 'native_strict') {
        return null;
      }
      final rawLayers = decoded['layers'];
      final rawRoots = decoded['compositionRoots'];
      final rawGenerated = decoded['generatedInfrastructure'];
      if (rawLayers is! Map<String, Object?> ||
          rawRoots is! List<Object?> ||
          rawGenerated is! List<Object?> ||
          rawLayers.isEmpty ||
          rawRoots.isEmpty ||
          rawGenerated.isEmpty) {
        return null;
      }
      const requiredLayers = <String>{
        'presentation',
        'application',
        'domain',
        'data',
        'infrastructure',
      };
      if (!rawLayers.keys.toSet().containsAll(requiredLayers)) return null;

      final layers = <String, List<String>>{};
      for (final entry in rawLayers.entries) {
        if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(entry.key)) return null;
        final globs = _parseGlobs(entry.value);
        if (globs == null) return null;
        layers[entry.key] = globs;
      }
      final roots = _parseGlobs(rawRoots);
      final generated = _parseGlobs(rawGenerated);
      if (roots == null || generated == null) return null;
      return DartitectBoundaryClassifier(
        layers: Map<String, List<String>>.unmodifiable(layers),
        compositionRoots: List<String>.unmodifiable(roots),
        generatedInfrastructure: List<String>.unmodifiable(generated),
      );
    } on FormatException {
      return null;
    }
  }

  static List<String>? _parseGlobs(Object? value) {
    if (value is! List<Object?> || value.isEmpty) return null;
    final output = <String>[];
    for (final raw in value) {
      if (raw is! String) return null;
      final glob = raw.trim().replaceAll('\\', '/');
      if (glob.isEmpty ||
          glob.startsWith('/') ||
          RegExp(r'^[A-Za-z]:').hasMatch(glob) ||
          glob.split('/').contains('..')) {
        return null;
      }
      output.add(glob);
    }
    return output;
  }

  static String _defaultPackageRoot(String sourcePath) {
    final normalized = File(sourcePath).absolute.path.replaceAll('\\', '/');
    final libIndex = normalized.lastIndexOf('/lib/');
    if (libIndex >= 0) return normalized.substring(0, libIndex);
    return File(sourcePath).absolute.parent.path;
  }

  static String _relativePath(String rootPath, String sourcePath) {
    final root = File(rootPath).absolute.path.replaceAll('\\', '/');
    final source = File(sourcePath).absolute.path.replaceAll('\\', '/');
    final rootPrefix = root.endsWith('/') ? root : '$root/';
    final comparableRoot = Platform.isWindows
        ? rootPrefix.toLowerCase()
        : rootPrefix;
    final comparableSource = Platform.isWindows ? source.toLowerCase() : source;
    if (comparableSource.startsWith(comparableRoot)) {
      return source.substring(rootPrefix.length);
    }
    return source;
  }
}

final class _ResolvedBoundaryPolicy {
  const _ResolvedBoundaryPolicy({
    required this.rootPath,
    required this.classifier,
  });

  final String rootPath;
  final DartitectBoundaryClassifier classifier;
}
