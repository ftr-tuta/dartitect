import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _corpusPath = 'tool/agent_evals/corpus.json';
const _dartitectSkill = 'dartitect-flutter-quality';
const _knownMcpTools = <String>{
  'analyze_files',
  'connect_dart_tooling_daemon',
  'flutter_driver',
  'get_app_logs',
  'get_runtime_errors',
  'get_selected_widget',
  'get_widget_tree',
  'hot_reload',
  'hot_restart',
  'launch_app',
  'list_devices',
  'list_running_apps',
  'run_tests',
  'set_widget_selection_mode',
  'stop_app',
};

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final root = File.fromUri(Platform.script).parent.parent.parent.absolute;
    final corpusFile = File('${root.path}/$_corpusPath');
    final corpus = _map(jsonDecode(await corpusFile.readAsString()));
    final validated = _validateCorpus(root, corpus);
    final repetitions =
        options.repetitions ??
        (options.suite == 'trend'
            ? validated.trendRepetitions
            : validated.requiredRepetitions);
    final expectedRepetitions = options.suite == 'trend'
        ? validated.trendRepetitions
        : validated.requiredRepetitions;
    if (repetitions != expectedRepetitions) {
      throw _UsageError(
        '${options.suite} requires exactly $expectedRepetitions repetition(s).',
      );
    }
    final count =
        validated.cases.length * validated.variants.length * repetitions;
    final expectedCount = options.suite == 'trend'
        ? validated.trendEvaluations
        : validated.requiredEvaluations;
    if (count != expectedCount) {
      throw StateError(
        'Matrix count $count differs from declared $expectedCount.',
      );
    }

    if (!options.execute) {
      stdout.writeln(
        'Flutter quality eval dry-run: ${validated.cases.length} cases x '
        '${validated.variants.length} variants x $repetitions repetition(s) '
        '= $count evaluations; sandbox=docker; retained payloads=none.',
      );
      return;
    }

    final sha = _requiredSha(options.sha);
    final model = _required(options.model, '--model');
    final receiptPath = _required(options.receipt, '--receipt');
    final flutterEvals = Directory(
      _required(options.flutterEvals, '--flutter-evals'),
    ).absolute;
    final officialPlugin = Directory(
      _required(options.officialPlugin, '--official-plugin'),
    ).absolute;
    await _requireGitIdentity(root, sha, 'candidate');
    await _requireGitIdentity(
      flutterEvals,
      validated.flutterEvalsPin,
      'flutter/evals',
    );
    await _requireGitIdentity(
      officialPlugin,
      validated.officialPluginPin,
      'flutter/agent-plugins',
    );
    _requireOfficialAssets(root, officialPlugin, validated.officialSkills);

    final image = _required(
      Platform.environment['DARTITECT_CODEX_EVAL_IMAGE'],
      'DARTITECT_CODEX_EVAL_IMAGE',
    );
    if (!RegExp(r'^[^@\s]+@sha256:[a-f0-9]{64}$').hasMatch(image)) {
      throw StateError(
        'DARTITECT_CODEX_EVAL_IMAGE must be pinned by sha256 digest.',
      );
    }
    _required(Platform.environment['OPENAI_API_KEY'], 'OPENAI_API_KEY');

    final temporary = await Directory.systemTemp.createTemp(
      'dartitect-flutter-quality-evals-',
    );
    try {
      final compose = File('${temporary.path}/compose.yaml');
      await compose.writeAsString(_compose(image));
      final plans = _plans(validated, repetitions);
      final evalSet = _buildEvalSet(
        root: root,
        temporary: temporary,
        compose: compose,
        officialPlugin: officialPlugin,
        model: model,
        validated: validated,
        plans: plans,
      );
      final evalSetFile = File('${temporary.path}/eval-set.json');
      await evalSetFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(evalSet)}\n',
      );

      final pythonPath = <String>[
        '${flutterEvals.path}/packages/dash_evals/src',
        '${flutterEvals.path}/packages/dataset_config_python/src',
      ].join(':');
      final process = await Process.run('docker', <String>[
        'run',
        '--rm',
        '--network',
        'host',
        '--volume',
        '/var/run/docker.sock:/var/run/docker.sock',
        '--volume',
        '${root.path}:${root.path}:ro',
        '--volume',
        '${flutterEvals.path}:${flutterEvals.path}:ro',
        '--volume',
        '${officialPlugin.path}:${officialPlugin.path}:ro',
        '--volume',
        '${temporary.path}:${temporary.path}:rw',
        '--workdir',
        root.path,
        '--env',
        'OPENAI_API_KEY',
        '--env',
        'PYTHONPATH=$pythonPath',
        image,
        'python3',
        '-m',
        'dash_evals.main',
        '--json',
        evalSetFile.path,
      ]);
      final processOutput = '${process.stdout}\n${process.stderr}';
      if (process.exitCode != 0) {
        throw StateError(
          'Pinned flutter/evals exited ${process.exitCode}; '
          'output digest ${sha256.convert(utf8.encode(processOutput))}.',
        );
      }

      final summary = await _summarize(
        Directory('${temporary.path}/logs'),
        plans,
        validated,
      );
      _enforceAcceptance(summary, validated);
      final receipt = _receipt(
        sha: sha,
        model: model,
        image: image,
        repetitions: repetitions,
        validated: validated,
        summary: summary,
        corpusDigest: await _corpusDigest(root, corpusFile, validated),
        configurationDigest: sha256
            .convert(utf8.encode(jsonEncode(evalSet)))
            .toString(),
        outputDigest: sha256
            .convert(utf8.encode('${summary.logDigest}:$processOutput'))
            .toString(),
      );
      _validateReceipt(receipt, validated);
      final receiptFile = File(receiptPath).absolute;
      await receiptFile.parent.create(recursive: true);
      await receiptFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
      );
      stdout.writeln(
        'Flutter quality evals passed $count evaluations for $sha; '
        'payload-free receipt: ${receiptFile.path}',
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  } on _UsageError catch (error) {
    stderr.writeln('Usage error: ${error.message}');
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Flutter quality evals failed: $error');
    exitCode = 1;
  }
}

_ValidatedCorpus _validateCorpus(Directory root, Map<String, Object?> corpus) {
  if (corpus['schemaVersion'] != 1 ||
      corpus['artifact'] != 'dartitect-flutter-quality-evals-v1') {
    throw const FormatException('Unsupported agent eval corpus.');
  }
  final pins = _map(corpus['pins']);
  final configuration = _map(corpus['configuration']);
  final fixtures = _maps(corpus['fixtures']);
  final cases = _maps(corpus['cases']);
  final variants = _maps(corpus['variants']);
  final acceptance = _map(corpus['acceptance']);
  final receipt = _map(corpus['receipt']);
  final skills = _strings(corpus['officialSkills']);
  if (fixtures.length != 9 || cases.length != 7 || variants.length != 3) {
    throw const FormatException(
      'Expected nine fixtures, seven cases, and three variants.',
    );
  }
  final fixtureIds = <String>{};
  final fixturePaths = <String>[];
  for (final fixture in fixtures) {
    final id = _string(fixture['id']);
    final path = _string(fixture['path']);
    if (!fixtureIds.add(id) || !File('${root.path}/$path').existsSync()) {
      throw FormatException('Invalid fixture $id at $path.');
    }
    fixturePaths.add(path);
  }
  final caseIds = <String>{};
  for (final item in cases) {
    final id = _string(item['id']);
    if (!caseIds.add(id)) throw FormatException('Duplicate case $id.');
    final bindings = _map(item['fixtures']);
    if (bindings.isEmpty ||
        bindings.values.any((value) => !fixtureIds.contains(value))) {
      throw FormatException('Case $id has invalid fixture bindings.');
    }
    final hiddenTest = item['hiddenTest'];
    if (hiddenTest != null &&
        !File('${root.path}/${_string(hiddenTest)}').existsSync()) {
      throw FormatException('Case $id has a missing hidden test.');
    }
    _string(item['prompt']);
    _string(item['target']);
  }
  final expectedVariants = <String>[
    'baseline',
    'officialSkills',
    'officialSkills+Dartitect',
  ];
  if (!_same(
    variants.map((item) => _string(item['id'])).toList(),
    expectedVariants,
  )) {
    throw const FormatException('Variant order or names changed.');
  }
  if (skills.length != 6 || skills.toSet().length != skills.length) {
    throw const FormatException('Expected six unique official skills.');
  }
  final privacyValues = <Object?>[
    configuration['retainTranscripts'],
    configuration['retainScreenshots'],
    configuration['retainSemantics'],
    configuration['retainScreenContent'],
  ];
  if (privacyValues.any((value) => value != false)) {
    throw const FormatException('Eval payload retention must remain disabled.');
  }
  return _ValidatedCorpus(
    raw: corpus,
    flutterEvalsPin: _sha(_string(pins['flutterEvals'])),
    officialPluginPin: _sha(_string(pins['flutterAgentPlugins'])),
    requiredRepetitions: _integer(configuration['requiredRepetitions']),
    trendRepetitions: _integer(configuration['trendRepetitions']),
    messageLimit: _integer(configuration['messageLimit']),
    timeLimit: _integer(configuration['timeLimitSeconds']),
    maxParallel: _integer(configuration['maxParallel']),
    officialSkills: skills,
    fixtures: fixtures,
    fixturePaths: fixturePaths,
    cases: cases,
    variants: variants,
    requiredEvaluations: _integer(acceptance['requiredEvaluations']),
    trendEvaluations: _integer(acceptance['trendEvaluations']),
    receiptAllowedFields: _strings(receipt['allowedFields']),
    receiptProhibitedFields: _strings(receipt['prohibitedFields']),
  );
}

void _requireOfficialAssets(
  Directory root,
  Directory plugin,
  List<String> skills,
) {
  for (final skill in skills) {
    if (!File('${plugin.path}/skills/$skill/SKILL.md').existsSync()) {
      throw StateError('Pinned official skill is missing: $skill.');
    }
  }
  if (!File('${plugin.path}/.codex-plugin/plugin.json').existsSync() ||
      !File('${plugin.path}/.mcp.json').existsSync()) {
    throw StateError('Pinned dart-flutter plugin manifest or MCP is missing.');
  }
  if (!File('${root.path}/.agents/skills/$_dartitectSkill/SKILL.md')
      .existsSync()) {
    throw StateError('Dartitect Flutter quality skill is missing.');
  }
}

List<_EvaluationPlan> _plans(_ValidatedCorpus corpus, int repetitions) => [
  for (var repetition = 1; repetition <= repetitions; repetition += 1)
    for (final evalCase in corpus.cases)
      for (final variant in corpus.variants)
        _EvaluationPlan(
          caseId: _string(evalCase['id']),
          variantId: _string(variant['id']),
          repetition: repetition,
          evalCase: evalCase,
          variant: variant,
        ),
];

Map<String, Object?> _buildEvalSet({
  required Directory root,
  required Directory temporary,
  required File compose,
  required Directory officialPlugin,
  required String model,
  required _ValidatedCorpus validated,
  required List<_EvaluationPlan> plans,
}) {
  final fixtures = <String, String>{
    for (final fixture in validated.fixtures)
      _string(fixture['id']): '${root.path}/${_string(fixture['path'])}',
  };
  final tasks = <Map<String, Object?>>[];
  for (final plan in plans) {
    final bindings = _map(plan.evalCase['fixtures']);
    final sampleFiles = <String, String>{
      '/workspace/pubspec.yaml':
          '${root.path}/tool/agent_evals/support/pubspec.yaml',
      for (final entry in bindings.entries)
        entry.key: fixtures[_string(entry.value)]!,
    };
    final skills = <String>[
      if (plan.variant['officialSkills'] == true)
        for (final skill in validated.officialSkills)
          '${officialPlugin.path}/skills/$skill',
      if (plan.variant['dartitectSkill'] == true)
        '${root.path}/.agents/skills/$_dartitectSkill',
    ];
    final mcpServers = <Map<String, Object?>>[
      if (plan.variant['dartMcp'] == true)
        <String, Object?>{
          'name': 'Dart',
          'command': 'dart',
          'args': <String>['mcp-server'],
        },
    ];
    final variantConfig = <String, Object?>{
      if (skills.isNotEmpty) 'skills': skills,
      if (mcpServers.isNotEmpty) 'mcp_servers': mcpServers,
    };
    final hiddenTest = plan.evalCase['hiddenTest'];
    tasks.add(<String, Object?>{
      'name': plan.taskName,
      'func': _string(plan.evalCase['task']),
      'dataset': <String, Object?>{
        'name': plan.taskName,
        'format': 'memory',
        'samples': <Map<String, Object?>>[
          <String, Object?>{
            'id': plan.taskName,
            'input': _string(plan.evalCase['prompt']),
            'target': _string(plan.evalCase['target']),
            'files': sampleFiles,
            'setup': 'cd /workspace && flutter pub get',
            'metadata': <String, Object?>{
              'workspace': '/workspace',
              if (hiddenTest != null)
                'tests': '${root.path}/${_string(hiddenTest)}',
              'case_id': plan.caseId,
              'variant_id': plan.variantId,
              'repetition': plan.repetition,
            },
          },
        ],
      },
      'metadata': <String, Object?>{
        'variant': plan.variantId,
        if (variantConfig.isNotEmpty) 'variant_config': variantConfig,
        'case_id': plan.caseId,
        'repetition': plan.repetition,
      },
      'sandbox': <String>['docker', compose.path],
      'time_limit': validated.timeLimit,
      'message_limit': validated.messageLimit,
    });
  }
  final inspectModel = model.contains('/') ? model : 'openai/$model';
  return <String, Object?>{
    'tasks': tasks,
    'log_dir': '${temporary.path}/logs',
    'model': <String>[inspectModel],
    'sandbox': <String>['docker', compose.path],
    'sandbox_cleanup': true,
    'retry_attempts': 3,
    'fail_on_error': 0.0,
    'max_samples': validated.maxParallel,
    'max_tasks': validated.maxParallel,
    'max_sandboxes': validated.maxParallel,
    'log_format': 'json',
    'log_images': false,
    'log_realtime': false,
    'trace': false,
    'metadata': <String, Object?>{
      'artifact': 'dartitect-flutter-quality-evals-v1',
    },
  };
}

Future<_EvalSummary> _summarize(
  Directory logDirectory,
  List<_EvaluationPlan> plans,
  _ValidatedCorpus corpus,
) async {
  if (!logDirectory.existsSync()) {
    throw StateError('Pinned eval harness produced no log directory.');
  }
  final documents = <_LogDocument>[];
  final rawForDigest = <String>[];
  await for (final entity in logDirectory.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final raw = await entity.readAsString();
    rawForDigest.add('${entity.path}:$raw');
    try {
      documents.add(_LogDocument(raw, jsonDecode(raw)));
    } on FormatException {
      // Non-JSON support logs are ignored; their bytes remain in the digest.
    }
  }
  if (documents.isEmpty) throw StateError('No JSON eval logs were produced.');
  final evaluations = <_EvaluationResult>[];
  final skillUsage = <String, int>{};
  final toolUsage = <String, int>{};
  for (final plan in plans) {
    final matching = documents
        .where((document) => document.raw.contains(plan.taskName))
        .toList();
    if (matching.isEmpty) {
      throw StateError('Missing eval log for ${plan.taskName}.');
    }
    final scores = <_Score>[];
    final localSkillUsage = <String, int>{};
    final localToolUsage = <String, int>{};
    for (final document in matching) {
      _collectScores(document.decoded, scores);
      _collectUsage(
        document.decoded,
        corpus.officialSkills,
        localSkillUsage,
        localToolUsage,
      );
    }
    for (final entry in localSkillUsage.entries) {
      skillUsage.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    for (final entry in localToolUsage.entries) {
      toolUsage.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    final uniqueScores = <String, _Score>{
      for (final score in scores) '${score.name}:${score.value}': score,
    }.values.toList();
    if (uniqueScores.isEmpty) {
      throw StateError('No scorer results for ${plan.taskName}.');
    }
    final requiresMcp = plan.evalCase['requiresMcp'] == true;
    final requiredScorers = requiresMcp
        ? <String>['mcp_tool_usage']
        : <String>['dart_analyze', 'flutter_test'];
    final structuralPass = requiredScorers.every(
      (required) => uniqueScores.any(
        (score) => score.name.contains(required) && score.passed,
      ),
    );
    final relevant = uniqueScores.where((score) => score.numeric != null);
    final score = relevant.isEmpty
        ? 0.0
        : relevant.map((item) => item.numeric!).reduce((a, b) => a + b) /
              relevant.length;
    final mcpTools = <String>{
      for (final name in localToolUsage.keys)
        if (_knownMcpTools.contains(name) || name.startsWith('Dart_')) name,
    };
    evaluations.add(
      _EvaluationResult(
        plan: plan,
        score: score,
        structuralPass: structuralPass,
        mcpProven: !requiresMcp || mcpTools.isNotEmpty,
      ),
    );
  }
  rawForDigest.sort();
  return _EvalSummary(
    evaluations: evaluations,
    skillUsage: skillUsage,
    toolUsage: toolUsage,
    logDigest: sha256.convert(utf8.encode(rawForDigest.join('\n'))).toString(),
  );
}

void _collectScores(Object? node, List<_Score> output) {
  if (node is List<Object?>) {
    for (final item in node) {
      _collectScores(item, output);
    }
    return;
  }
  if (node is! Map<String, Object?>) return;
  final scores = node['scores'];
  if (scores is Map<String, Object?>) {
    for (final entry in scores.entries) {
      final value = entry.value;
      if (value is Map<String, Object?> && value.containsKey('value')) {
        output.add(_Score(entry.key, value['value']));
      }
    }
  }
  if (node['scorer'] is String && node.containsKey('value')) {
    output.add(_Score(node['scorer']! as String, node['value']));
  }
  for (final value in node.values) {
    _collectScores(value, output);
  }
}

void _collectUsage(
  Object? node,
  List<String> officialSkills,
  Map<String, int> skills,
  Map<String, int> tools,
) {
  if (node is List<Object?>) {
    for (final item in node) {
      _collectUsage(item, officialSkills, skills, tools);
    }
    return;
  }
  if (node is! Map<String, Object?>) return;
  final function = node['function'];
  if (function is String) {
    if (_knownMcpTools.contains(function) || function.startsWith('Dart_')) {
      tools.update(function, (value) => value + 1, ifAbsent: () => 1);
    }
    if (function == 'skill') {
      final arguments = jsonEncode(node['arguments']);
      for (final skill in <String>[...officialSkills, _dartitectSkill]) {
        if (arguments.contains(skill)) {
          skills.update(skill, (value) => value + 1, ifAbsent: () => 1);
        }
      }
    }
  }
  final mcpNames = node['mcp_tools_called'];
  if (mcpNames is List<Object?>) {
    for (final item in mcpNames.whereType<String>()) {
      if (_knownMcpTools.contains(item) || item.startsWith('Dart_')) {
        tools.update(item, (value) => value + 1, ifAbsent: () => 1);
      }
    }
  }
  for (final value in node.values) {
    _collectUsage(value, officialSkills, skills, tools);
  }
}

void _enforceAcceptance(_EvalSummary summary, _ValidatedCorpus corpus) {
  final full = summary.evaluations.where(
    (result) => result.plan.variantId == 'officialSkills+Dartitect',
  );
  final failedStructural = full.where((result) => !result.structuralPass);
  if (failedStructural.isNotEmpty) {
    throw StateError(
      'Full variant failed structural scorers: '
      '${failedStructural.map((item) => item.plan.taskName).join(', ')}.',
    );
  }
  final devtools = full.where(
    (result) => result.plan.caseId == 'devtoolsRuntime',
  );
  if (devtools.isEmpty || devtools.any((result) => !result.mcpProven)) {
    throw StateError('Full DevTools case did not prove real MCP usage.');
  }
  final scores = summary.variantScores;
  final baseline = scores['baseline']!;
  final official = scores['officialSkills']!;
  final complete = scores['officialSkills+Dartitect']!;
  if (complete + 1e-9 < baseline || complete + 1e-9 < official) {
    throw StateError('Full aggregate score regressed against a comparator.');
  }
  if (official < 1.0 - 1e-9 && complete <= official + 1e-9) {
    throw StateError(
      'Full aggregate score must exceed non-maximal official skills.',
    );
  }
}

Map<String, Object?> _receipt({
  required String sha,
  required String model,
  required String image,
  required int repetitions,
  required _ValidatedCorpus validated,
  required _EvalSummary summary,
  required String corpusDigest,
  required String configurationDigest,
  required String outputDigest,
}) => <String, Object?>{
  'schemaVersion': 1,
  'sha': sha,
  'pins': <String, String>{
    'flutterEvals': validated.flutterEvalsPin,
    'flutterAgentPlugins': validated.officialPluginPin,
  },
  'model': model,
  'configuration': <String, Object?>{
    'sandbox': 'docker',
    'imageDigest': image.substring(image.indexOf('@') + 1),
    'repetitions': repetitions,
    'messageLimit': validated.messageLimit,
    'timeLimitSeconds': validated.timeLimit,
    'maxParallel': validated.maxParallel,
  },
  'counts': <String, Object?>{
    'cases': validated.cases.length,
    'variants': validated.variants.length,
    'evaluations': summary.evaluations.length,
    'structuralPasses': summary.evaluations
        .where((item) => item.structuralPass)
        .length,
  },
  'scores': <String, double>{
    for (final entry in summary.variantScores.entries)
      entry.key: double.parse(entry.value.toStringAsFixed(6)),
  },
  'usage': <String, Object?>{
    'skills': Map<String, int>.fromEntries(
      summary.skillUsage.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    ),
    'tools': Map<String, int>.fromEntries(
      summary.toolUsage.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    ),
    'mcpProven': summary.evaluations.any(
      (item) => item.plan.caseId == 'devtoolsRuntime' && item.mcpProven,
    ),
  },
  'digests': <String, String>{
    'corpus': corpusDigest,
    'configuration': configurationDigest,
    'results': outputDigest,
  },
  'result': 'PASS',
};

void _validateReceipt(Map<String, Object?> receipt, _ValidatedCorpus corpus) {
  if (!_same(receipt.keys.toList(), corpus.receiptAllowedFields)) {
    throw StateError('Receipt fields differ from the payload-free allowlist.');
  }
  void visit(Object? value, [String? key]) {
    if (key != null && corpus.receiptProhibitedFields.contains(key)) {
      throw StateError('Receipt contains prohibited field $key.');
    }
    if (value is Map<String, Object?>) {
      for (final entry in value.entries) {
        visit(entry.value, entry.key);
      }
    } else if (value is List<Object?>) {
      for (final item in value) {
        visit(item);
      }
    }
  }

  visit(receipt);
}

Future<String> _corpusDigest(
  Directory root,
  File corpusFile,
  _ValidatedCorpus corpus,
) async {
  final bytes = BytesBuilder(copy: false);
  bytes.add(await corpusFile.readAsBytes());
  for (final path in <String>[
    ...corpus.fixturePaths,
    for (final item in corpus.cases)
      if (item['hiddenTest'] != null) _string(item['hiddenTest']),
    'tool/agent_evals/support/pubspec.yaml',
  ]..sort()) {
    bytes
      ..add(utf8.encode(path))
      ..add(await File('${root.path}/$path').readAsBytes());
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

Future<void> _requireGitIdentity(
  Directory directory,
  String expected,
  String label,
) async {
  final result = await Process.run('git', <String>[
    '-C',
    directory.path,
    'rev-parse',
    'HEAD',
  ]);
  final actual = '${result.stdout}'.trim();
  if (result.exitCode != 0 || actual != expected) {
    throw StateError(
      '$label must resolve to exact SHA $expected, got $actual.',
    );
  }
}

String _compose(String image) =>
    '''
services:
  default:
    image: $image
    init: true
    network_mode: none
    working_dir: /workspace
    command: ["sleep", "infinity"]
''';

String _requiredSha(String? value) => _sha(_required(value, '--sha'));

String _sha(String value) {
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(value)) {
    throw _UsageError('Expected an exact lowercase 40-character SHA.');
  }
  return value;
}

String _required(String? value, String label) {
  if (value == null || value.trim().isEmpty) {
    throw _UsageError('Missing $label.');
  }
  return value.trim();
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

String _string(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Expected non-empty string.');
  }
  return value;
}

int _integer(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('Expected positive integer.');
  }
  return value;
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

final class _Options {
  const _Options({
    required this.execute,
    required this.suite,
    required this.repetitions,
    this.sha,
    this.model,
    this.flutterEvals,
    this.officialPlugin,
    this.receipt,
  });

  factory _Options.parse(List<String> arguments) {
    var execute = false;
    var dryRun = false;
    var suite = 'required';
    int? repetitions;
    String? sha;
    String? model;
    String? flutterEvals;
    String? officialPlugin;
    String? receipt;
    for (final argument in arguments) {
      if (argument == '--execute') {
        execute = true;
      } else if (argument == '--dry-run') {
        dryRun = true;
      } else if (argument.startsWith('--suite=')) {
        suite = argument.substring('--suite='.length);
      } else if (argument.startsWith('--repetitions=')) {
        repetitions = int.tryParse(argument.substring('--repetitions='.length));
        if (repetitions == null) {
          throw _UsageError('Invalid --repetitions.');
        }
      } else if (argument.startsWith('--sha=')) {
        sha = argument.substring('--sha='.length);
      } else if (argument.startsWith('--model=')) {
        model = argument.substring('--model='.length);
      } else if (argument.startsWith('--flutter-evals=')) {
        flutterEvals = argument.substring('--flutter-evals='.length);
      } else if (argument.startsWith('--official-plugin=')) {
        officialPlugin = argument.substring('--official-plugin='.length);
      } else if (argument.startsWith('--receipt=')) {
        receipt = argument.substring('--receipt='.length);
      } else {
        throw _UsageError('Unknown argument: $argument');
      }
    }
    if (execute == dryRun) {
      throw _UsageError('Choose exactly one of --execute or --dry-run.');
    }
    if (suite != 'required' && suite != 'trend') {
      throw _UsageError('--suite must be required or trend.');
    }
    return _Options(
      execute: execute,
      suite: suite,
      repetitions: repetitions,
      sha: sha,
      model: model,
      flutterEvals: flutterEvals,
      officialPlugin: officialPlugin,
      receipt: receipt,
    );
  }

  final bool execute;
  final String suite;
  final int? repetitions;
  final String? sha;
  final String? model;
  final String? flutterEvals;
  final String? officialPlugin;
  final String? receipt;
}

final class _ValidatedCorpus {
  const _ValidatedCorpus({
    required this.raw,
    required this.flutterEvalsPin,
    required this.officialPluginPin,
    required this.requiredRepetitions,
    required this.trendRepetitions,
    required this.messageLimit,
    required this.timeLimit,
    required this.maxParallel,
    required this.officialSkills,
    required this.fixtures,
    required this.fixturePaths,
    required this.cases,
    required this.variants,
    required this.requiredEvaluations,
    required this.trendEvaluations,
    required this.receiptAllowedFields,
    required this.receiptProhibitedFields,
  });

  final Map<String, Object?> raw;
  final String flutterEvalsPin;
  final String officialPluginPin;
  final int requiredRepetitions;
  final int trendRepetitions;
  final int messageLimit;
  final int timeLimit;
  final int maxParallel;
  final List<String> officialSkills;
  final List<Map<String, Object?>> fixtures;
  final List<String> fixturePaths;
  final List<Map<String, Object?>> cases;
  final List<Map<String, Object?>> variants;
  final int requiredEvaluations;
  final int trendEvaluations;
  final List<String> receiptAllowedFields;
  final List<String> receiptProhibitedFields;
}

final class _EvaluationPlan {
  const _EvaluationPlan({
    required this.caseId,
    required this.variantId,
    required this.repetition,
    required this.evalCase,
    required this.variant,
  });

  final String caseId;
  final String variantId;
  final int repetition;
  final Map<String, Object?> evalCase;
  final Map<String, Object?> variant;

  String get taskName => '$caseId:$variantId:r$repetition';
}

final class _Score {
  const _Score(this.name, this.value);

  final String name;
  final Object? value;

  double? get numeric => switch (value) {
    final num number => number.toDouble(),
    'C' || 'correct' || true => 1.0,
    'I' || 'incorrect' || false => 0.0,
    _ => null,
  };

  bool get passed => (numeric ?? 0) >= 1.0;
}

final class _LogDocument {
  const _LogDocument(this.raw, this.decoded);

  final String raw;
  final Object? decoded;
}

final class _EvaluationResult {
  const _EvaluationResult({
    required this.plan,
    required this.score,
    required this.structuralPass,
    required this.mcpProven,
  });

  final _EvaluationPlan plan;
  final double score;
  final bool structuralPass;
  final bool mcpProven;
}

final class _EvalSummary {
  const _EvalSummary({
    required this.evaluations,
    required this.skillUsage,
    required this.toolUsage,
    required this.logDigest,
  });

  final List<_EvaluationResult> evaluations;
  final Map<String, int> skillUsage;
  final Map<String, int> toolUsage;
  final String logDigest;

  Map<String, double> get variantScores => <String, double>{
    for (final variant in <String>[
      'baseline',
      'officialSkills',
      'officialSkills+Dartitect',
    ])
      variant: _mean(
        evaluations
            .where((item) => item.plan.variantId == variant)
            .map((item) => item.score),
      ),
  };

  static double _mean(Iterable<double> values) {
    final collected = values.toList(growable: false);
    if (collected.isEmpty) return 0;
    return collected.reduce((a, b) => a + b) / collected.length;
  }
}

final class _UsageError implements Exception {
  const _UsageError(this.message);

  final String message;
}
