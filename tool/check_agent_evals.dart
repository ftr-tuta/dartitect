import 'dart:convert';
import 'dart:io';

const _flutterEvalsPin = '739c590ad0e028b1393a8604574463e287e5078e';
const _officialPluginPin = 'df9bebe7ec3c96f80f499e5d62ba1ebe81892500';
const _skills = <String>[
  'flutter-add-integration-test',
  'flutter-add-widget-preview',
  'flutter-add-widget-test',
  'flutter-apply-architecture-best-practices',
  'flutter-build-responsive-layout',
  'flutter-fix-layout-issues',
];
const _variants = <String>[
  'baseline',
  'officialSkills',
  'officialSkills+Dartitect',
];
const _cases = <String>[
  'constraintsResponsive',
  'devtoolsRuntime',
  'reusableWidgetsPreviews',
  'mvvm',
  'repositories',
  'multiplatform',
  'tests',
];
const _allowedReceiptFields = <String>[
  'schemaVersion',
  'sha',
  'pins',
  'model',
  'configuration',
  'counts',
  'scores',
  'usage',
  'digests',
  'result',
];
const _prohibitedReceiptFields = <String>[
  'transcript',
  'screenshots',
  'semantics',
  'screenContent',
  'prompt',
  'completion',
];

Future<void> main(List<String> arguments) async {
  try {
    final options = _options(arguments);
    final root = File.fromUri(Platform.script).parent.parent.absolute;
    final corpusFile =
        options ?? File('${root.path}/tool/agent_evals/corpus.json');
    final corpus = _map(jsonDecode(await corpusFile.readAsString()));
    final failures = <String>[];
    void require(bool condition, String message) {
      if (!condition) failures.add(message);
    }

    require(corpus['schemaVersion'] == 1, 'Unsupported agent eval schema.');
    require(
      corpus['artifact'] == 'dartitect-flutter-quality-evals-v1',
      'Wrong agent eval artifact.',
    );
    final pins = _map(corpus['pins']);
    require(
      pins['flutterEvals'] == _flutterEvalsPin,
      'flutter/evals pin changed.',
    );
    require(
      pins['flutterAgentPlugins'] == _officialPluginPin,
      'flutter/agent-plugins pin changed.',
    );
    require(
      _same(_strings(corpus['officialSkills']), _skills),
      'The six official Flutter skills changed.',
    );

    final configuration = _map(corpus['configuration']);
    require(configuration['sandbox'] == 'docker', 'Docker is required.');
    require(
      configuration['requiredRepetitions'] == 1 &&
          configuration['trendRepetitions'] == 3,
      'Required/trend repetitions must be one/three.',
    );
    for (final key in const <String>[
      'retainTranscripts',
      'retainScreenshots',
      'retainSemantics',
      'retainScreenContent',
    ]) {
      require(configuration[key] == false, '$key must remain disabled.');
    }

    final fixtures = _maps(corpus['fixtures']);
    require(fixtures.length == 9, 'Expected exactly nine fixtures.');
    final fixtureIds = <String>{};
    for (final fixture in fixtures) {
      final id = '${fixture['id']}';
      final path = '${fixture['path']}';
      require(fixtureIds.add(id), 'Duplicate fixture $id.');
      final source = _read(root, path, failures);
      require(
        path.startsWith('tool/agent_evals/fixtures/'),
        '$id escaped fixtures.',
      );
      require(
        source.contains('flutter') || source.contains('Task'),
        '$id is empty.',
      );
      require(
        !source.contains('package:dartitect'),
        '$id depends on Dartitect.',
      );
    }

    final cases = _maps(corpus['cases']);
    require(cases.length == 7, 'Expected exactly seven aggregate cases.');
    require(
      _same(cases.map((item) => '${item['id']}').toList(), _cases),
      'The seven case names or order changed.',
    );
    final usedFixtures = <String>[];
    for (final evalCase in cases) {
      final id = '${evalCase['id']}';
      require(
        evalCase['technique'] == id,
        '$id must map one-to-one to its quality technique.',
      );
      final task = evalCase['task'];
      require(
        task == 'flutter_bug_fix' || task == 'mcp_coding_task',
        '$id uses an unsupported pinned task.',
      );
      final bindings = _map(evalCase['fixtures']);
      require(bindings.isNotEmpty, '$id has no fixture.');
      for (final entry in bindings.entries) {
        require(
          entry.key.startsWith('/workspace/lib/'),
          '$id has a non-library destination.',
        );
        final fixture = '${entry.value}';
        usedFixtures.add(fixture);
        require(
          fixtureIds.contains(fixture),
          '$id references unknown $fixture.',
        );
      }
      require(
        '${evalCase['prompt']}'.trim().isNotEmpty &&
            '${evalCase['target']}'.trim().isNotEmpty,
        '$id lacks prompt or target.',
      );
      final hiddenTest = evalCase['hiddenTest'];
      if (id == 'devtoolsRuntime') {
        require(hiddenTest == null, 'DevTools must use the real MCP scorer.');
        require(evalCase['requiresMcp'] == true, 'DevTools must require MCP.');
      } else {
        require(hiddenTest is String, '$id lacks a structural hidden test.');
        if (hiddenTest is String) _read(root, hiddenTest, failures);
        require(
          evalCase['requiresMcp'] == false,
          '$id unexpectedly requires MCP.',
        );
      }
    }
    usedFixtures.sort();
    final declaredFixtures = fixtureIds.toList()..sort();
    require(
      _same(usedFixtures, declaredFixtures),
      'Every fixture must be assigned exactly once across aggregate cases.',
    );

    final variants = _maps(corpus['variants']);
    require(
      _same(variants.map((item) => '${item['id']}').toList(), _variants),
      'The three comparison variants changed.',
    );
    require(
      variants[0]['officialSkills'] == false &&
          variants[0]['dartitectSkill'] == false &&
          variants[0]['dartMcp'] == false,
      'Baseline is not isolated.',
    );
    require(
      variants[1]['officialSkills'] == true &&
          variants[1]['dartitectSkill'] == false &&
          variants[1]['dartMcp'] == true,
      'Official-skills variant is invalid.',
    );
    require(
      variants[2]['officialSkills'] == true &&
          variants[2]['dartitectSkill'] == true &&
          variants[2]['dartMcp'] == true,
      'Full Dartitect variant is invalid.',
    );

    final acceptance = _map(corpus['acceptance']);
    require(
      acceptance['requiredEvaluations'] == 21 &&
          acceptance['trendEvaluations'] == 63,
      'Evaluation matrix must contain 21 required and 63 trend runs.',
    );
    require(
      acceptance['fullVariantStructuralPass'] == true &&
          acceptance['fullVariantRealMcpCase'] == 'devtoolsRuntime' &&
          acceptance['fullStrictlyAboveOfficialUnlessOfficialMaximum'] == true,
      'Full-variant acceptance weakened.',
    );
    require(
      _same(_strings(acceptance['fullNotBelow']), const <String>[
        'baseline',
        'officialSkills',
      ]),
      'Full variant comparators changed.',
    );

    final receipt = _map(corpus['receipt']);
    require(receipt['schemaVersion'] == 1, 'Wrong receipt schema.');
    require(
      _same(_strings(receipt['allowedFields']), _allowedReceiptFields),
      'Receipt allowlist changed.',
    );
    require(
      _same(_strings(receipt['prohibitedFields']), _prohibitedReceiptFields),
      'Receipt payload denylist changed.',
    );

    final runner = _read(root, 'tool/agent_evals/run.dart', failures);
    for (final token in const <String>[
      "'docker'",
      "'dash_evals.main'",
      "'mcp_tool_usage'",
      "'dart_analyze'",
      "'flutter_test'",
      'DARTITECT_CODEX_EVAL_IMAGE',
      'sha256:',
      'temporary.delete(recursive: true)',
    ]) {
      require(runner.contains(token), 'Runner lacks $token.');
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          !entity.path.endsWith('${Platform.pathSeparator}pubspec.yaml') ||
          entity.path.contains(
            '${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}',
          ) ||
          entity.path.contains(
            '${Platform.pathSeparator}build${Platform.pathSeparator}',
          )) {
        continue;
      }
      final pubspec = await entity.readAsString();
      require(
        !pubspec.contains('flutter/evals') &&
            !pubspec.contains('flutter_evals') &&
            !pubspec.contains('dash_evals'),
        '${entity.path} depends on flutter/evals.',
      );
    }

    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
    stdout.writeln(
      'agent-evals-v1 passed: nine fixtures, seven aggregate cases, '
      '21 required/63 trend evaluations, exact pins, Docker, and '
      'payload-free receipts.',
    );
  } on Object catch (error) {
    stderr.writeln('Agent eval validation failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

File? _options(List<String> arguments) {
  File? corpus;
  for (final argument in arguments) {
    if (argument.startsWith('--corpus=')) {
      if (corpus != null) throw const FormatException('Duplicate --corpus.');
      corpus = File(argument.substring('--corpus='.length)).absolute;
    } else {
      throw FormatException('Unknown argument: $argument');
    }
  }
  return corpus;
}

String _read(Directory root, String path, List<String> failures) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    failures.add('Missing $path.');
    return '';
  }
  return file.readAsStringSync();
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List<Object?>) throw const FormatException('Expected list.');
  return value.map(_map).toList(growable: false);
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected string list.');
  }
  return value.cast<String>();
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);
