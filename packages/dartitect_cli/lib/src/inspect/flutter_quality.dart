import 'dart:convert';
import 'dart:io';

/// Evidence state for one executable Flutter quality technique.
enum FlutterQualityStatus {
  /// A blocking contradiction or invalid boundary was found.
  fail,

  /// The technique applies but required evidence is absent.
  notEvidenced,

  /// Evidence exists with a non-blocking concern.
  warning,

  /// All inspected evidence passed.
  pass,

  /// The technique does not apply to the inspected project.
  notApplicable,
}

/// Result for one Flutter quality technique.
final class FlutterQualityTechnique {
  /// Creates immutable technique evidence.
  const FlutterQualityTechnique({required this.status, required this.evidence});

  /// Technique status.
  final FlutterQualityStatus status;

  /// Relative, payload-free evidence statements.
  final List<String> evidence;

  /// JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'evidence': evidence,
  };
}

/// Complete result for `dartitect inspect flutter-quality`.
final class FlutterQualityInspection {
  /// Creates a report and applies the specified status precedence.
  FlutterQualityInspection(Map<String, FlutterQualityTechnique> techniques)
    : techniques = Map<String, FlutterQualityTechnique>.unmodifiable(
        techniques,
      ),
      overallStatus = aggregateStatus(techniques.values);

  /// Ordered technique evidence.
  final Map<String, FlutterQualityTechnique> techniques;

  /// Aggregate status.
  final FlutterQualityStatus overallStatus;

  /// Process exit code.
  int get exitCode => switch (overallStatus) {
    FlutterQualityStatus.fail || FlutterQualityStatus.notEvidenced => 1,
    FlutterQualityStatus.warning ||
    FlutterQualityStatus.pass ||
    FlutterQualityStatus.notApplicable => 0,
  };

  /// Stable JSON document.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'inspect flutter-quality',
    'overallStatus': overallStatus.name,
    'techniques': <String, Object?>{
      for (final entry in techniques.entries) entry.key: entry.value.toJson(),
    },
    'exitCode': exitCode,
  };

  /// Aggregates with fail > notEvidenced > warning > pass.
  static FlutterQualityStatus aggregateStatus(
    Iterable<FlutterQualityTechnique> techniques,
  ) {
    final applicable = techniques
        .map((technique) => technique.status)
        .where((status) => status != FlutterQualityStatus.notApplicable)
        .toSet();
    if (applicable.isEmpty) return FlutterQualityStatus.notApplicable;
    for (final status in const <FlutterQualityStatus>[
      FlutterQualityStatus.fail,
      FlutterQualityStatus.notEvidenced,
      FlutterQualityStatus.warning,
      FlutterQualityStatus.pass,
    ]) {
      if (applicable.contains(status)) return status;
    }
    return FlutterQualityStatus.notApplicable;
  }
}

/// Offline, bounded project inspector for the seven Flutter quality practices.
final class FlutterQualityInspector {
  /// Creates an inspector confined to [root].
  FlutterQualityInspector(Directory root) : root = root.absolute;

  /// Project root.
  final Directory root;

  /// Inspects local source and evidence without executing project code.
  Future<FlutterQualityInspection> inspect() async {
    final pubspec = File(_join(root.path, 'pubspec.yaml'));
    final pubspecSource = await pubspec.exists()
        ? await pubspec.readAsString()
        : '';
    final dartFiles = await _dartSources();
    final sources = dartFiles.values.join('\n');
    final isFlutter =
        RegExp(r'^\s*flutter\s*:', multiLine: true).hasMatch(pubspecSource) ||
        sources.contains('package:flutter/');
    if (!isFlutter) {
      return FlutterQualityInspection(<String, FlutterQualityTechnique>{
        for (final name in _techniqueNames)
          name: const FlutterQualityTechnique(
            status: FlutterQualityStatus.notApplicable,
            evidence: <String>['No Flutter application boundary was detected.'],
          ),
      });
    }

    final presentation = dartFiles.entries
        .where(
          (entry) =>
              entry.key.contains('/presentation/') ||
              entry.key.endsWith('_page.dart') ||
              entry.key.endsWith('_view.dart'),
        )
        .map((entry) => entry.value)
        .join('\n');
    final hasResponsive =
        sources.contains('LayoutBuilder(') ||
        sources.contains('DartitectResponsiveWindowBuilder(') ||
        sources.contains('DartitectResponsiveRegionBuilder(');
    final hasPreview =
        sources.contains('@Preview(') ||
        sources.contains('@DartitectPreviewMatrix(');
    final previewViolation = dartFiles.entries.any(
      (entry) =>
          (entry.value.contains('@Preview(') ||
              entry.value.contains('@DartitectPreviewMatrix(')) &&
          _containsAny(entry.value, const <String>[
            'dart:io',
            'dart:ffi',
            'package:dio/',
            'Store(',
            'openDatabase(',
          ]),
    );
    final hasViewModel =
        sources.contains('extends DartitectViewModel') &&
        (sources.contains('TasksView') || sources.contains('ViewModelHost'));
    final presentationOwnsInfrastructure = _containsAny(
      presentation,
      const <String>[
        'package:dartitect_dio/',
        'package:dartitect_drift/',
        'package:dartitect_objectbox/',
        'dart:io',
      ],
    );
    final hasRepository =
        RegExp(r'abstract\s+(?:interface\s+)?class\s+\w*Repository')
            .hasMatch(sources) ||
        RegExp(r'class\s+\w*Repository\s+implements').hasMatch(sources);
    final directWidgetIo =
        presentation.contains('http.') ||
        presentation.contains('Dio(') ||
        presentation.contains('openDatabase(');
    final platformEvidence = <String>[
      for (final platform in _platformDirectories)
        if (await Directory(_join(root.path, platform)).exists()) platform,
    ];
    final testFiles = dartFiles.keys
        .where(
          (path) =>
              path.startsWith('test/') || path.startsWith('integration_test/'),
        )
        .toList();
    final hasWidgetTest = testFiles.any(
      (path) =>
          dartFiles[path]!.contains('testWidgets(') ||
          dartFiles[path]!.contains('WidgetTester'),
    );
    final runtimeEvidence = File(
      _join(root.path, 'tool/flutter_quality_runtime_evidence.json'),
    );
    final runtimeEvidenceExists = await runtimeEvidence.exists();
    final runtimeEvidenceValid = runtimeEvidenceExists
        ? _validRuntimeEvidence(await runtimeEvidence.readAsString())
        : false;

    return FlutterQualityInspection(<String, FlutterQualityTechnique>{
      'constraintsResponsive': FlutterQualityTechnique(
        status: hasResponsive
            ? FlutterQualityStatus.pass
            : FlutterQualityStatus.notEvidenced,
        evidence: <String>[
          if (hasResponsive)
            'Constraint-driven responsive builders were found.'
          else
            'No constraint-driven responsive builder was found.',
        ],
      ),
      'devtoolsRuntime': FlutterQualityTechnique(
        status: runtimeEvidenceExists
            ? runtimeEvidenceValid
                  ? FlutterQualityStatus.pass
                  : FlutterQualityStatus.fail
            : FlutterQualityStatus.notEvidenced,
        evidence: <String>[
          if (!runtimeEvidenceExists)
            'No payload-free runtime or real Flutter MCP receipt was found.'
          else if (runtimeEvidenceValid)
            'Payload-free runtime evidence includes real Flutter MCP discovery.'
          else
            'Runtime evidence is invalid or does not prove real Flutter MCP use.',
        ],
      ),
      'reusableWidgetsPreviews': FlutterQualityTechnique(
        status: previewViolation
            ? FlutterQualityStatus.fail
            : hasPreview
            ? FlutterQualityStatus.pass
            : FlutterQualityStatus.notEvidenced,
        evidence: <String>[
          if (previewViolation)
            'A preview source reaches a prohibited I/O or provider token.'
          else if (hasPreview)
            'Dev-only Flutter preview annotations were found.'
          else
            'No Flutter preview annotation was found.',
        ],
      ),
      'mvvm': FlutterQualityTechnique(
        status: presentationOwnsInfrastructure
            ? FlutterQualityStatus.fail
            : hasViewModel
            ? FlutterQualityStatus.pass
            : FlutterQualityStatus.notEvidenced,
        evidence: <String>[
          if (presentationOwnsInfrastructure)
            'Presentation imports or owns infrastructure.'
          else if (hasViewModel)
            'A Dartitect ViewModel and observing View boundary were found.'
          else
            'No complete Dartitect MVVM boundary was found.',
        ],
      ),
      'repositories': FlutterQualityTechnique(
        status: directWidgetIo
            ? FlutterQualityStatus.fail
            : hasRepository
            ? FlutterQualityStatus.pass
            : FlutterQualityStatus.notEvidenced,
        evidence: <String>[
          if (directWidgetIo)
            'Presentation starts repository/provider I/O directly.'
          else if (hasRepository)
            'A provider-neutral repository contract was found.'
          else
            'No repository contract was found.',
        ],
      ),
      'multiplatform': FlutterQualityTechnique(
        status: platformEvidence.length == _platformDirectories.length
            ? FlutterQualityStatus.pass
            : platformEvidence.isEmpty
            ? FlutterQualityStatus.notEvidenced
            : FlutterQualityStatus.warning,
        evidence: <String>[
          'Platform directories: ${platformEvidence.isEmpty ? 'none' : platformEvidence.join(', ')}.',
        ],
      ),
      'tests': FlutterQualityTechnique(
        status: hasWidgetTest
            ? FlutterQualityStatus.pass
            : testFiles.isEmpty
            ? FlutterQualityStatus.notEvidenced
            : FlutterQualityStatus.warning,
        evidence: <String>[
          if (hasWidgetTest)
            'Flutter widget-test evidence was found.'
          else if (testFiles.isEmpty)
            'No Dart or Flutter test source was found.'
          else
            'Tests exist, but no widget-test evidence was found.',
        ],
      ),
    });
  }

  Future<Map<String, String>> _dartSources() async {
    final sources = <String, String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = _relative(entity.path);
      if (_excluded(relative)) continue;
      sources[relative] = await entity.readAsString();
    }
    return sources;
  }

  bool _validRuntimeEvidence(String source) {
    try {
      final value = jsonDecode(source);
      return value is Map<String, Object?> &&
          value['schemaVersion'] == 1 &&
          value['flutterMcp'] == 'real' &&
          value['uploadsScreenContent'] == false;
    } on FormatException {
      return false;
    }
  }

  String _relative(String path) => path
      .substring(root.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');

  static bool _excluded(String path) =>
      path.startsWith('.dart_tool/') ||
      path.startsWith('build/') ||
      path.startsWith('tool/agent_evals/fixtures/') ||
      path.startsWith('tool/agent_evals/scorers/') ||
      path.contains('/.dart_tool/') ||
      path.contains('/build/') ||
      path.endsWith('.g.dart');

  static bool _containsAny(String source, Iterable<String> needles) =>
      needles.any(source.contains);

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

const _techniqueNames = <String>[
  'constraintsResponsive',
  'devtoolsRuntime',
  'reusableWidgetsPreviews',
  'mvvm',
  'repositories',
  'multiplatform',
  'tests',
];

const _platformDirectories = <String>[
  'android',
  'ios',
  'linux',
  'macos',
  'windows',
  'web',
];
