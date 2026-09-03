import 'dart:convert';
import 'dart:io';

const _entrypoints = <String>[
  'package:dartitect_flutter/dartitect_flutter_ui.dart',
  'package:dartitect_flutter_testing/dartitect_flutter_testing.dart',
];
const _officialSkills = <String>[
  'flutter-add-integration-test',
  'flutter-add-widget-preview',
  'flutter-add-widget-test',
  'flutter-apply-architecture-best-practices',
  'flutter-build-responsive-layout',
  'flutter-fix-layout-issues',
];
const _requiredEvidence = <String>[
  'analyze',
  'audit',
  'preview',
  'runtimeInspection',
  'tests',
  'platforms',
];
const _techniques = <String>[
  'constraintsResponsive',
  'devtoolsRuntime',
  'reusableWidgetsPreviews',
  'mvvm',
  'repositories',
  'multiplatform',
  'tests',
];
const _techniqueEvidence = <String>[
  'skills',
  'diagnostics',
  'preview',
  'runtime',
  'tests',
  'actions',
  'canaries',
  'platforms',
];
const _coordinatedJobs = <String>[
  'linux',
  'windows',
  'macos',
  'android-emulator',
  'drift-web',
  'clean-clone',
  'git-consumption',
  'osv',
];
const _linuxMatrixCells = <String>['Flutter 3.47.1 (floor)', 'Flutter stable'];
const _platforms = <String>[
  'android',
  'ios',
  'linux',
  'macos',
  'windows',
  'web',
];
const _semanticDiagnostics = <String>[
  'DT3120',
  'DT3121',
  'DT3122',
  'DT3123',
  'DT3124',
  'DT3125',
  'DT3126',
  'DT3127',
  'DT3128',
  'DT3130',
  'DT3131',
  'DT3132',
  'DT3140',
  'DT3141',
  'DT3142',
  'DT3143',
  'DT3144',
  'DT3145',
];
const _previewRows = <(String, String, String, num)>[
  ('compact', '360x640', 'light', 1.0),
  ('compact-200-percent', '430x932', 'dark', 2.0),
  ('medium', '768x1024', 'light', 1.0),
  ('expanded', '1440x900', 'light', 1.0),
];

Future<void> main(List<String> arguments) async {
  try {
    final root = _root(arguments);
    final contract = _map(
      jsonDecode(
        File('${root.path}/tool/ui_quality_contract.json').readAsStringSync(),
      ),
    );
    final failures = <String>[];
    void require(bool condition, String message) {
      if (!condition) failures.add(message);
    }

    require(contract['schemaVersion'] == 2, 'Unsupported contract schema.');
    require(contract['artifact'] == 'ui-quality-v2', 'Wrong artifact name.');
    require(contract['goal'] == 'RC3-FLUTTER-QUALITY', 'Wrong quality goal.');
    require(
      contract['releaseVersion'] == '1.1.0-rc.3',
      'Wrong cohort version.',
    );
    require(
      contract['stableVersion'] == '1.0.0',
      'The distributed stable version changed.',
    );
    require(contract['mode'] == 'native-strict', 'Native Strict is required.');

    final topology = _map(contract['topology']);
    require(topology['packages'] == 25, 'Expected 25 packages.');
    require(topology['publicEntrypoints'] == 35, 'Expected 35 entrypoints.');
    require(
      _same(_strings(contract['entrypoints']), _entrypoints),
      'UI entrypoint evidence is incomplete.',
    );
    require(
      _same(_strings(contract['publicAdditions']), const <String>[
        'DartitectPreviewMatrix',
      ]),
      'The RC3 public addition is not exact.',
    );
    require(
      _same(_strings(contract['requiredEvidence']), _requiredEvidence),
      'The executable evidence contract is incomplete.',
    );

    final plugin = _map(contract['officialPlugin']);
    require(
      plugin['selector'] == 'dart-flutter@dart-flutter',
      'Wrong official Flutter plugin selector.',
    );
    require(
      plugin['mcpCommand'] == 'dart mcp-server',
      'Wrong official Flutter MCP command.',
    );
    require(
      _same(_strings(plugin['skills']), _officialSkills),
      'The official Flutter skill set is incomplete.',
    );

    final techniques = _map(contract['techniques']);
    require(
      _same(techniques.keys.toList(), _techniques),
      'The seven quality techniques or their order changed.',
    );
    for (final name in _techniques) {
      final technique = _map(techniques[name]);
      require(
        technique.keys.toSet().containsAll(_techniqueEvidence) &&
            technique.length == _techniqueEvidence.length,
        '$name must declare every evidence dimension.',
      );
      for (final dimension in _techniqueEvidence) {
        require(
          _strings(technique[dimension]).isNotEmpty,
          '$name has no $dimension evidence.',
        );
      }
      require(
        _strings(technique['skills']).contains('dartitect-flutter-quality'),
        '$name is not routed through dartitect-flutter-quality.',
      );
      require(
        _strings(technique['actions']).every(_coordinatedJobs.contains),
        '$name references an unknown deterministic Actions job.',
      );
      require(
        _same(_strings(technique['platforms']), _platforms),
        '$name does not cover the six platforms.',
      );
    }

    final parity = _map(contract['diagnosticParity']);
    require(
      _same(_strings(parity['objectiveErrors']), const <String>[
        'DT3001',
        'DT3002',
      ]),
      'Objective UI diagnostics changed.',
    );
    require(
      _same(_strings(parity['semanticErrors']), _semanticDiagnostics),
      'Semantic Flutter diagnostics are incomplete.',
    );
    require(
      _strings(parity['syntacticWarnings'])
          .toSet()
          .containsAll(_semanticDiagnostics),
      'The syntactic scanner does not reserve every semantic diagnostic.',
    );
    _mustExist(root, '${parity['corpus']}', failures);
    _mustExist(root, '${parity['checker']}', failures);

    final previewMatrices = _map(contract['previewMatrices']);
    final previews = _list(previewMatrices['device']).map(_map).toList();
    require(
      previews.length == _previewRows.length,
      'The device preview matrix must contain four ordered rows.',
    );
    for (
      var index = 0;
      index < previews.length && index < _previewRows.length;
      index++
    ) {
      final actual = previews[index];
      final expected = _previewRows[index];
      require(
        actual['name'] == expected.$1 &&
            actual['size'] == expected.$2 &&
            actual['brightness'] == expected.$3 &&
            actual['textScale'] == expected.$4,
        'Preview row $index differs from the RC3 contract.',
      );
    }
    require(
      previewMatrices['accessibility'] == 'DartitectUiMatrix',
      'Accessibility coverage must remain in DartitectUiMatrix.',
    );

    final performance = _map(contract['performance']);
    require(
      _strings(performance['blocking']).length == 9,
      'Structural performance blockers are incomplete.',
    );
    require(
      _same(_strings(performance['informative']), const <String>[
        'frame-time',
        'memory',
      ]),
      'Timing and memory must remain informative.',
    );
    final actions = _map(contract['githubActionsEvidence']);
    require(
      actions['workflow'] == '.github/workflows/ci.yaml' &&
          actions['requiredCheck'] == 'CI / Required' &&
          actions['readinessArtifact'] == 'actions-readiness-v1' &&
          _same(_strings(actions['coordinatedJobs']), _coordinatedJobs) &&
          _same(_strings(actions['linuxMatrixCells']), _linuxMatrixCells) &&
          actions['coordinatedExecutions'] == 9 &&
          actions['hostedRunnersOnly'] == true,
      'Deterministic GitHub Actions evidence is incomplete.',
    );
    final ci = _read(root, '${actions['workflow']}', failures);
    for (final job in _coordinatedJobs) {
      require(
        ci.contains('      - $job'),
        'CI / Required does not coordinate $job.',
      );
    }
    for (final cell in _linuxMatrixCells) {
      require(ci.contains('label: $cell'), 'Linux matrix is missing $cell.');
    }
    require(
      ci.contains('name: CI / Required'),
      'The deterministic Actions aggregate is missing.',
    );
    final privacy = _map(contract['privacy']);
    require(
      privacy.length == 4 && privacy.values.every((value) => value == false),
      'Quality evidence must remain payload-free.',
    );

    if (failures.isNotEmpty) throw StateError(failures.join('\n'));

    final api = _map(
      jsonDecode(_read(root, 'tool/api_surface.snapshot.json', failures)),
    );
    final surfaces = _map(api['entrypoints']);
    for (final entrypoint in _entrypoints) {
      final relative =
          'packages/${entrypoint.substring('package:'.length).replaceFirst('/', '/lib/')}';
      require(
        surfaces.containsKey(relative),
        'API snapshot lacks $entrypoint.',
      );
    }

    final previewSource = _read(
      root,
      'packages/dartitect_flutter_testing/lib/src/preview_matrix.dart',
      failures,
    );
    final orderedPreviewTokens = <String>[
      "name: 'compact'",
      'size: Size(360, 640)',
      "name: 'compact-200-percent'",
      'size: Size(430, 932)',
      "name: 'medium'",
      'size: Size(768, 1024)',
      "name: 'expanded'",
      'size: Size(1440, 900)',
    ];
    var cursor = -1;
    for (final token in orderedPreviewTokens) {
      final next = previewSource.indexOf(token, cursor + 1);
      require(
        next > cursor,
        'Preview implementation is missing ordered $token.',
      );
      cursor = next;
    }
    require(
      previewSource.contains(
        'final class DartitectPreviewMatrix extends MultiPreview',
      ),
      'DartitectPreviewMatrix must be a final MultiPreview subtype.',
    );
    require(
      RegExp(r'group: _dartitectPreviewGroup')
                  .allMatches(previewSource)
                  .length ==
              4 &&
          previewSource.contains("const _dartitectPreviewGroup = 'Dartitect'"),
      'Every preview must use the Dartitect group.',
    );

    final previewFixture = _read(
      root,
      'packages/dartitect_flutter_testing/lib/src/dev/preview_fixture.dart',
      failures,
    );
    require(
      previewFixture.contains('@DartitectPreviewMatrix()') &&
          previewFixture.contains('PreviewTaskViewData') &&
          previewFixture.contains('VoidCallback'),
      'Preview-safe fixture evidence is incomplete.',
    );
    for (final prohibited in const <String>[
      'dart:io',
      'dart:ffi',
      'package:dio/',
      'package:dartitect_drift/',
      'package:dartitect_objectbox/',
    ]) {
      require(
        !previewFixture.contains(prohibited),
        'Preview fixture reaches prohibited $prohibited.',
      );
    }

    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
    stdout.writeln(
      'ui-quality-v2 passed: seven executable techniques, 25 packages, '
      '35 entrypoints, six platforms, official Flutter tooling, and '
      'nine deterministic GitHub Actions executions.',
    );
  } on Object catch (error) {
    stderr.writeln('UI quality validation failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

Directory _root(List<String> arguments) {
  Directory? root;
  for (final argument in arguments) {
    if (argument.startsWith('--root=')) {
      if (root != null) throw const FormatException('Duplicate root.');
      root = Directory(argument.substring('--root='.length)).absolute;
    } else {
      throw FormatException('Unknown argument: $argument');
    }
  }
  return root ?? File.fromUri(Platform.script).parent.parent.absolute;
}

String _read(Directory root, String path, List<String> failures) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    failures.add('Missing $path.');
    return '{}';
  }
  return file.readAsStringSync();
}

void _mustExist(Directory root, String path, List<String> failures) {
  if (!FileSystemEntity.typeSync('${root.path}/$path').isFile &&
      !FileSystemEntity.typeSync('${root.path}/$path').isDirectory) {
    failures.add('Missing $path.');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON list.');
  }
  return value;
}

List<String> _strings(Object? value) {
  final list = _list(value);
  if (list.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return list.cast<String>();
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

extension on FileSystemEntityType {
  bool get isFile => this == FileSystemEntityType.file;
  bool get isDirectory => this == FileSystemEntityType.directory;
}
