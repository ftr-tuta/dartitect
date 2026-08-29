import 'dart:convert';
import 'dart:io';

/// Generates or checks the shared scanner/analyzer boundary policy.
Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final source = jsonDecode(
    await File('${root.path}/tool/boundary_policy.json').readAsString(),
  );
  if (source is! Map<String, Object?> || source['schemaVersion'] != 1) {
    throw const FormatException('Invalid boundary policy schema.');
  }
  final codes = (source['codes']! as Map<String, Object?>)
      .cast<String, String>();
  final layers = (source['defaultLayers']! as Map<String, Object?>).map(
    (key, value) => MapEntry(key, (value! as List<Object?>).cast<String>()),
  );
  final roots = (source['defaultCompositionRoots']! as List<Object?>)
      .cast<String>();
  final generatedInfrastructure =
      (source['defaultGeneratedInfrastructure']! as List<Object?>)
          .cast<String>();
  final generatedSuffixes =
      (source['defaultGeneratedSuffixes']! as List<Object?>).cast<String>();
  final forbidden = (source['forbiddenPackages']! as List<Object?>)
      .cast<String>();
  final infrastructure = (source['infrastructurePackages']! as List<Object?>)
      .cast<String>();
  final providerTypes = (source['providerTypes']! as List<Object?>)
      .cast<String>();
  final flutterBoundaryTypes =
      (source['flutterBoundaryTypes']! as List<Object?>).cast<String>();
  final architectureCodegen =
      (source['architectureCodegenAnnotations']! as List<Object?>)
          .cast<String>();
  final providerCodegen =
      (source['providerCodegenAnnotations']! as List<Object?>).cast<String>();
  final borrowingValueHosts = (source['borrowingValueHosts']! as List<Object?>)
      .cast<String>();
  final knownDisposableTypes =
      (source['knownDisposableTypes']! as List<Object?>).cast<String>();
  final generated = await _formatDart(
    _render(
      codes,
      layers,
      roots,
      generatedInfrastructure,
      generatedSuffixes,
      forbidden,
      infrastructure,
      providerTypes,
      flutterBoundaryTypes,
      architectureCodegen,
      providerCodegen,
      borrowingValueHosts,
      knownDisposableTypes,
    ),
  );
  final targets = <File>[
    File(
      '${root.path}/packages/dartitect_cli/lib/src/rules/'
      'generated_boundary_policy.dart',
    ),
    File(
      '${root.path}/packages/dartitect_lints/lib/src/'
      'generated_boundary_policy.dart',
    ),
  ];
  if (arguments.contains('--check')) {
    final stale = <String>[];
    for (final target in targets) {
      if (!await target.exists() || await target.readAsString() != generated) {
        stale.add(target.path.substring(root.path.length + 1));
      }
    }
    if (stale.isNotEmpty) {
      stderr.writeln('Generated boundary policy is stale: ${stale.join(', ')}');
      exitCode = 1;
      return;
    }
    stdout.writeln('Shared boundary policy is current in both tooling hosts.');
    return;
  }
  for (final target in targets) {
    await target.writeAsString(generated, flush: true);
  }
  stdout.writeln('Generated shared boundary policy for CLI and lints.');
}

Future<String> _formatDart(String source) async {
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-boundary-policy-',
  );
  try {
    final file = File('${temporary.path}/generated_boundary_policy.dart');
    await file.writeAsString(source, flush: true);
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'format',
      file.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Could not format generated boundary policy: ${result.stderr}',
      );
    }
    return await file.readAsString();
  } finally {
    await temporary.delete(recursive: true);
  }
}

String _render(
  Map<String, String> codes,
  Map<String, List<String>> layers,
  List<String> roots,
  List<String> generatedInfrastructure,
  List<String> generatedSuffixes,
  List<String> forbidden,
  List<String> infrastructure,
  List<String> providerTypes,
  List<String> flutterBoundaryTypes,
  List<String> architectureCodegen,
  List<String> providerCodegen,
  List<String> borrowingValueHosts,
  List<String> knownDisposableTypes,
) {
  String strings(Iterable<String> values, {String indent = '    '}) => values
      .map((value) => "$indent'${value.replaceAll("'", "\\'")}',")
      .join('\n');
  final layerEntries = layers.entries
      .map(
        (entry) =>
            "    '${entry.key}': <String>[\n"
            '${strings(entry.value, indent: '      ')}\n'
            '    ],',
      )
      .join('\n');
  return '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Generated from tool/boundary_policy.json by tool/generate_boundary_policy.dart.

/// Stable diagnostic codes shared by scan and analyzer hosts.
abstract final class DartitectRuleCodes {
${codes.entries.map((entry) => "  /// Stable ${entry.value} diagnostic code.\n  static const String ${entry.key} = '${entry.value}';").join('\n\n')}
}

/// Generated Native-First boundary policy shared without package coupling.
abstract final class DartitectArchitectureRules {
  /// Default named layer globs for stable config v2 and analyzer diagnostics.
  static const Map<String, List<String>> defaultLayers =
      <String, List<String>>{
$layerEntries
  };

  /// Default explicit composition roots.
  static const List<String> defaultCompositionRoots = <String>[
${strings(roots)}
  ];

  /// Default generated provider-infrastructure locations.
  static const List<String> defaultGeneratedInfrastructure = <String>[
${strings(generatedInfrastructure)}
  ];

  /// Reviewed suffixes recognized only with a standard generated-code header.
  static const List<String> defaultGeneratedSuffixes = <String>[
${strings(generatedSuffixes)}
  ];

  /// Architecture/state frameworks excluded by the native-first profile.
  static const Set<String> forbiddenPackages = <String>{
${strings(forbidden)}
  };

  /// Provider packages that remain in infrastructure/composition.
  static const Set<String> infrastructurePackages = <String>{
${strings(infrastructure)}
  };

  /// Provider types forbidden outside infrastructure and composition.
  static const Set<String> providerTypes = <String>{
${strings(providerTypes)}
  };

  /// Flutter/router types retained only at View or composition boundaries.
  static const Set<String> flutterBoundaryTypes = <String>{
${strings(flutterBoundaryTypes)}
  };

  /// Architecture/state code-generation annotations forbidden everywhere.
  static const Set<String> architectureCodegenAnnotations = <String>{
${strings(architectureCodegen)}
  };

  /// Provider serialization/schema annotations restricted to infrastructure.
  static const Set<String> providerCodegenAnnotations = <String>{
${strings(providerCodegen)}
  };

  /// Flutter hosts whose `.value` constructors borrow their value.
  static const Set<String> borrowingValueHosts = <String>{
${strings(borrowingValueHosts)}
  };

  /// Known lifecycle-owning values unsafe as inline borrowed temporaries.
  static const Set<String> knownDisposableTypes = <String>{
${strings(knownDisposableTypes)}
  };
}

/// Layer and composition facts for one project-relative path.
final class DartitectSourceClassification {
  /// Creates path classification facts.
  const DartitectSourceClassification({
    required this.layers,
    required this.isCompositionRoot,
    required this.isGeneratedInfrastructure,
  });

  /// Configured layer names matching this path.
  final Set<String> layers;

  /// Whether the path matches a configured composition-root glob.
  final bool isCompositionRoot;

  /// Whether the path matches a reviewed generated-infrastructure glob.
  final bool isGeneratedInfrastructure;

  /// Whether this source is classified as [layer].
  bool isLayer(String layer) => layers.contains(layer);
}

/// Deterministic path classifier shared by scan and lint hosts.
final class DartitectBoundaryClassifier {
  /// Creates a classifier from validated stable-v2 boundaries.
  const DartitectBoundaryClassifier({
    required this.layers,
    required this.compositionRoots,
    required this.generatedInfrastructure,
    this.generatedSuffixes = DartitectArchitectureRules.defaultGeneratedSuffixes,
  });

  /// Creates the native MVVM default classifier.
  factory DartitectBoundaryClassifier.defaults() => DartitectBoundaryClassifier(
    layers: DartitectArchitectureRules.defaultLayers,
    compositionRoots: DartitectArchitectureRules.defaultCompositionRoots,
    generatedInfrastructure:
        DartitectArchitectureRules.defaultGeneratedInfrastructure,
    generatedSuffixes: DartitectArchitectureRules.defaultGeneratedSuffixes,
  );

  /// Configured layer and composition-root globs.
  final Map<String, List<String>> layers;

  /// Configured composition-root globs.
  final List<String> compositionRoots;

  /// Configured generated-infrastructure globs.
  final List<String> generatedInfrastructure;

  /// Generated source suffixes accepted together with a reviewed header.
  final List<String> generatedSuffixes;

  /// Classifies a POSIX or platform path.
  DartitectSourceClassification classify(String path, {String? source}) {
    final normalized = path.replaceAll('\\\\', '/');
    final matchedLayers = <String>{
      for (final entry in layers.entries)
        if (entry.value.any((glob) => dartitectGlobMatches(glob, normalized)))
          entry.key,
    };
    return DartitectSourceClassification(
      layers: Set<String>.unmodifiable(matchedLayers),
      isCompositionRoot: compositionRoots.any(
        (glob) => dartitectGlobMatches(glob, normalized),
      ),
      isGeneratedInfrastructure:
          generatedInfrastructure.any(
            (glob) => dartitectGlobMatches(glob, normalized),
          ) ||
          source != null &&
              generatedSuffixes.any(normalized.endsWith) &&
              dartitectHasGeneratedHeader(source),
    );
  }
}

/// Whether the first eight lines contain a reviewed generated-code header.
bool dartitectHasGeneratedHeader(String source) {
  final lines = source.split(RegExp(r'\\r?\\n')).take(8);
  final header = RegExp(
    r'^\\s*//\\s*GENERATED CODE\\s*-\\s*DO NOT (?:MODIFY|EDIT) BY HAND\\.?\\s*\$',
    caseSensitive: false,
  );
  return lines.any(header.hasMatch);
}

/// Matches a normalized path against `*`, `?`, and recursive `**` globs.
bool dartitectGlobMatches(String glob, String path) {
  final normalizedGlob = glob.replaceAll('\\\\', '/');
  final normalizedPath = path.replaceAll('\\\\', '/');
  final pattern = StringBuffer('^');
  for (var index = 0; index < normalizedGlob.length; index += 1) {
    final character = normalizedGlob[index];
    if (character == '*') {
      final recursive =
          index + 1 < normalizedGlob.length && normalizedGlob[index + 1] == '*';
      if (recursive) {
        index += 1;
        if (index + 1 < normalizedGlob.length &&
            normalizedGlob[index + 1] == '/') {
          index += 1;
          pattern.write('(?:.*/)?');
        } else {
          pattern.write('.*');
        }
      } else {
        pattern.write('[^/]*');
      }
    } else if (character == '?') {
      pattern.write('[^/]');
    } else {
      pattern.write(RegExp.escape(character));
    }
  }
  pattern.write(r'\$');
  return RegExp(pattern.toString()).hasMatch(normalizedPath);
}
''';
}
