import 'dart:convert';
import 'dart:io';

import 'generated_boundary_policy.dart';

/// Resolves stable-v3 boundary configuration for an analyzer source file.
///
/// The nearest `dartitect.json` wins. Paths are made relative to that file so
/// the analyzer host applies the same project-relative globs as CLI scans on
/// POSIX and Windows hosts.
final class DartitectLintBoundaryResolver {
  const DartitectLintBoundaryResolver._();

  /// Classifies [sourcePath] with its nearest valid stable-v3 configuration.
  static DartitectSourceClassification classify(String sourcePath) {
    return resolve(sourcePath).classification;
  }

  /// Resolves classification and any explicit configuration diagnostic.
  static DartitectLintBoundaryResolution resolve(
    String sourcePath, {
    String? source,
  }) {
    final resolved = _resolve(sourcePath);
    final relativePath = _relativePath(resolved.rootPath, sourcePath);
    if (source == null) {
      try {
        source = File(sourcePath).readAsStringSync();
      } on FileSystemException {
        source = null;
      }
    }
    return DartitectLintBoundaryResolution(
      classification: resolved.classifier.classify(
        relativePath,
        source: source,
      ),
      configurationError: resolved.configurationError,
      suppressedCodes: resolved.suppressions
          .where((suppression) => suppression.matches(relativePath))
          .map((suppression) => suppression.code)
          .toSet(),
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
        String? configurationError;
        try {
          final parsed = _parse(config.readAsStringSync());
          classifier = parsed?.classifier;
          if (parsed == null) {
            configurationError =
                'Invalid dartitect.json; fix stable-v3 boundary configuration.';
          } else {
            return _ResolvedBoundaryPolicy(
              rootPath: directory.absolute.path,
              classifier: parsed.classifier,
              suppressions: parsed.suppressions,
              configurationError: null,
            );
          }
        } on FileSystemException {
          classifier = null;
          configurationError =
              'dartitect.json could not be read; fix its permissions.';
        }
        return _ResolvedBoundaryPolicy(
          rootPath: directory.absolute.path,
          classifier: classifier ?? DartitectBoundaryClassifier.defaults(),
          suppressions: const <_LintSuppression>[],
          configurationError: configurationError,
        );
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }

    return _ResolvedBoundaryPolicy(
      rootPath: _defaultPackageRoot(sourcePath),
      classifier: DartitectBoundaryClassifier.defaults(),
      suppressions: const <_LintSuppression>[],
      configurationError: null,
    );
  }

  static _ParsedBoundaryConfig? _parse(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> ||
          decoded['configVersion'] != 3 ||
          decoded['profile'] != 'native_strict') {
        return null;
      }
      final rawLayers = decoded['layers'];
      final rawRoots = decoded['compositionRoots'];
      final rawGenerated = decoded['generatedInfrastructure'];
      final rawSuffixes = decoded['generatedSuffixes'];
      final rawSuppressions = decoded['suppressions'] ?? const <Object?>[];
      if (rawLayers is! Map<String, Object?> ||
          rawRoots is! List<Object?> ||
          rawGenerated is! List<Object?> ||
          rawSuppressions is! List<Object?> ||
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
      final suffixes = rawSuffixes == null
          ? DartitectArchitectureRules.defaultGeneratedSuffixes
          : _parseSuffixes(rawSuffixes);
      if (roots == null || generated == null || suffixes == null) return null;
      final suppressions = <_LintSuppression>[];
      for (final value in rawSuppressions) {
        if (value is! Map<String, Object?>) return null;
        if (value.keys.toSet().difference(const <String>{
          'code',
          'path',
          'reason',
          'owner',
          'expiresAt',
        }).isNotEmpty) {
          return null;
        }
        final code = value['code'];
        final path = value['path'];
        final reason = value['reason'];
        final owner = value['owner'];
        final expires = value['expiresAt'];
        if (code is! String ||
            !RegExp(r'^DT\d{4}$').hasMatch(code) ||
            path is! String ||
            _parseGlobs(<Object?>[path]) == null ||
            reason is! String ||
            reason.trim().isEmpty ||
            owner is! String ||
            owner.trim().isEmpty ||
            expires is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expires)) {
          return null;
        }
        final expiresAt = DateTime.tryParse('${expires}T00:00:00Z');
        if (expiresAt == null) return null;
        suppressions.add(
          _LintSuppression(
            code: code,
            path: path.replaceAll('\\', '/'),
            expiresAt: expiresAt,
          ),
        );
      }
      return _ParsedBoundaryConfig(
        classifier: DartitectBoundaryClassifier(
          layers: Map<String, List<String>>.unmodifiable(layers),
          compositionRoots: List<String>.unmodifiable(roots),
          generatedInfrastructure: List<String>.unmodifiable(generated),
          generatedSuffixes: List<String>.unmodifiable(suffixes),
        ),
        suppressions: List<_LintSuppression>.unmodifiable(suppressions),
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

  static List<String>? _parseSuffixes(Object? value) {
    if (value is! List<Object?> || value.isEmpty) return null;
    final output = <String>[];
    for (final raw in value) {
      if (raw is! String ||
          !RegExp(
            r'^\.[a-z0-9_.-]+\.dart$',
            caseSensitive: false,
          ).hasMatch(raw) ||
          raw.contains('/') ||
          raw.contains('\\')) {
        return null;
      }
      if (!output.contains(raw)) output.add(raw);
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
    required this.suppressions,
    required this.configurationError,
  });

  final String rootPath;
  final DartitectBoundaryClassifier classifier;
  final List<_LintSuppression> suppressions;
  final String? configurationError;
}

final class _ParsedBoundaryConfig {
  const _ParsedBoundaryConfig({
    required this.classifier,
    required this.suppressions,
  });

  final DartitectBoundaryClassifier classifier;
  final List<_LintSuppression> suppressions;
}

final class _LintSuppression {
  const _LintSuppression({
    required this.code,
    required this.path,
    required this.expiresAt,
  });

  final String code;
  final String path;
  final DateTime expiresAt;

  bool matches(String sourcePath) =>
      DateTime.now().toUtc().isBefore(expiresAt) &&
      dartitectGlobMatches(path, sourcePath);
}

/// Analyzer-side boundary resolution with a fail-visible config outcome.
final class DartitectLintBoundaryResolution {
  /// Creates one resolved lint policy.
  const DartitectLintBoundaryResolution({
    required this.classification,
    required this.configurationError,
    required this.suppressedCodes,
  });

  /// Source classification used by rule evaluation.
  final DartitectSourceClassification classification;

  /// Sanitized explicit diagnostic when defaults replaced invalid config.
  final String? configurationError;

  /// Active reviewed `dartitect.json` suppressions matching this source.
  final Set<String> suppressedCodes;
}
