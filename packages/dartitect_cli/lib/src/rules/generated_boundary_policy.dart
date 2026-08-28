// GENERATED CODE - DO NOT EDIT BY HAND.
// Generated from tool/boundary_policy.json by tool/generate_boundary_policy.dart.

/// Stable diagnostic codes shared by scan and analyzer hosts.
abstract final class DartitectRuleCodes {
  /// Stable DT1001 diagnostic code.
  static const String domainFlutter = 'DT1001';

  /// Stable DT1002 diagnostic code.
  static const String domainInfrastructure = 'DT1002';

  /// Stable DT1003 diagnostic code.
  static const String dataPresentation = 'DT1003';

  /// Stable DT1004 diagnostic code.
  static const String buildContextBoundary = 'DT1004';

  /// Stable DT1005 diagnostic code.
  static const String presentationInfrastructure = 'DT1005';

  /// Stable DT1006 diagnostic code.
  static const String forbiddenArchitecture = 'DT1006';

  /// Stable DT1007 diagnostic code.
  static const String privateSrc = 'DT1007';

  /// Stable DT1008 diagnostic code.
  static const String implementationBoundary = 'DT1008';

  /// Stable DT1009 diagnostic code.
  static const String providerTypeBoundary = 'DT1009';

  /// Stable DT1010 diagnostic code.
  static const String flutterTypeBoundary = 'DT1010';

  /// Stable DT1011 diagnostic code.
  static const String architectureCodegen = 'DT1011';

  /// Stable DT1012 diagnostic code.
  static const String providerCodegenBoundary = 'DT1012';

  /// Stable DT1013 diagnostic code.
  static const String serviceLocator = 'DT1013';

  /// Stable DT1014 diagnostic code.
  static const String packageDependencyCycle = 'DT1014';

  /// Stable DT1015 diagnostic code.
  static const String packageReexport = 'DT1015';

  /// Stable DT1016 diagnostic code.
  static const String scopeBoundary = 'DT1016';

  /// Stable DT1045 diagnostic code.
  static const String temporaryDisposableHostValue = 'DT1045';
}

/// Generated Native-First boundary policy shared without package coupling.
abstract final class DartitectArchitectureRules {
  /// Default named layer globs for stable config v1 and analyzer diagnostics.
  static const Map<String, List<String>> defaultLayers = <String, List<String>>{
    'domain': <String>['**/domain/**'],
    'application': <String>['**/application/**'],
    'data': <String>['**/data/**'],
    'infrastructure': <String>['**/infrastructure/**'],
    'presentation': <String>[
      '**/presentation/**',
      '**/*_page.dart',
      '**/*_view.dart',
      '**/*_view_model.dart',
    ],
  };

  /// Default explicit composition roots.
  static const List<String> defaultCompositionRoots = <String>[
    'lib/main.dart',
    'test/**',
    '**/composition/**',
    '**/*_composition_root.dart',
  ];

  /// Default generated provider-infrastructure locations.
  static const List<String> defaultGeneratedInfrastructure = <String>[
    '**/infrastructure/**/*.g.dart',
  ];

  /// Reviewed suffixes recognized only with a standard generated-code header.
  static const List<String> defaultGeneratedSuffixes = <String>[
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.router.dart',
  ];

  /// Architecture/state frameworks excluded by the native-first profile.
  static const Set<String> forbiddenPackages = <String>{
    'flutter_riverpod',
    'hooks_riverpod',
    'riverpod',
    'riverpod_annotation',
    'riverpod_generator',
    'provider',
    'get_it',
    'get_it_mixin',
    'watch_it',
    'injectable',
    'flutter_modular',
    'stacked',
    'elementary',
    'bloc',
    'flutter_bloc',
    'hydrated_bloc',
    'get',
    'mobx',
    'flutter_mobx',
    'signals',
    'signals_flutter',
  };

  /// Provider packages that remain in infrastructure/composition.
  static const Set<String> infrastructurePackages = <String>{
    'dio',
    'drift',
    'objectbox',
    'dartitect_dio',
    'dartitect_drift',
    'dartitect_objectbox',
    'retrofit',
    'json_annotation',
  };

  /// Provider types forbidden outside infrastructure and composition.
  static const Set<String> providerTypes = <String>{
    'Dio',
    'RequestOptions',
    'Response',
    'CancelToken',
    'GeneratedDatabase',
    'Store',
    'Box',
    'Query',
    'QueryBuilder',
  };

  /// Flutter/router types retained only at View or composition boundaries.
  static const Set<String> flutterBoundaryTypes = <String>{
    'Widget',
    'BuildContext',
    'State',
    'GoRouter',
  };

  /// Architecture/state code-generation annotations forbidden everywhere.
  static const Set<String> architectureCodegenAnnotations = <String>{
    'injectable',
    'riverpod',
    'ProviderFor',
  };

  /// Provider serialization/schema annotations restricted to infrastructure.
  static const Set<String> providerCodegenAnnotations = <String>{
    'JsonSerializable',
    'DriftDatabase',
    'DriftAccessor',
    'UseRowClass',
    'Entity',
    'RestApi',
  };

  /// Flutter hosts whose `.value` constructors borrow their value.
  static const Set<String> borrowingValueHosts = <String>{
    'ApplicationHost',
    'SessionHost',
    'ViewModelHost',
  };

  /// Known lifecycle-owning values unsafe as inline borrowed temporaries.
  static const Set<String> knownDisposableTypes = <String>{
    'BootstrapCoordinator',
    'BoundedLocalHistory',
    'CancellationSource',
    'DioOwner',
    'OwnedRuntimeSlot',
    'ReactiveOwner',
    'ResourceOwner',
    'SessionRuntimeController',
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
  /// Creates a classifier from validated stable-v1 boundaries.
  const DartitectBoundaryClassifier({
    required this.layers,
    required this.compositionRoots,
    required this.generatedInfrastructure,
    this.generatedSuffixes =
        DartitectArchitectureRules.defaultGeneratedSuffixes,
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
    final normalized = path.replaceAll('\\', '/');
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
  final lines = source.split(RegExp(r'\r?\n')).take(8);
  final header = RegExp(
    r'^\s*//\s*GENERATED CODE\s*-\s*DO NOT (?:MODIFY|EDIT) BY HAND\.?\s*$',
    caseSensitive: false,
  );
  return lines.any(header.hasMatch);
}

/// Matches a normalized path against `*`, `?`, and recursive `**` globs.
bool dartitectGlobMatches(String glob, String path) {
  final normalizedGlob = glob.replaceAll('\\', '/');
  final normalizedPath = path.replaceAll('\\', '/');
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
  pattern.write(r'$');
  return RegExp(pattern.toString()).hasMatch(normalizedPath);
}
