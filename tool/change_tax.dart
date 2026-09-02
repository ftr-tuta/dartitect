import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

Future<void> main(List<String> arguments) async {
  final workspace = File.fromUri(Platform.script).parent.parent.absolute;
  final validateOnly = arguments.contains('--validate-only');
  final keepArtifacts = arguments.contains('--keep-artifacts');
  final jsonOutput = arguments.contains('--json');
  final scenarioFilters = arguments
      .where((argument) => argument.startsWith('--scenario='))
      .map((argument) => argument.substring('--scenario='.length))
      .toSet();
  final outputArgument = arguments
      .where((argument) => argument.startsWith('--output='))
      .singleOrNull;
  final unknown = arguments.where(
    (argument) =>
        argument != '--validate-only' &&
        argument != '--keep-artifacts' &&
        argument != '--json' &&
        !argument.startsWith('--scenario=') &&
        !argument.startsWith('--output='),
  );
  if (unknown.isNotEmpty) {
    throw ArgumentError(
      'Usage: dart run tool/change_tax.dart [--validate-only] [--json] '
      '[--keep-artifacts] [--scenario=<id>] [--output=<path>]',
    );
  }

  final contractFile = File('${workspace.path}/tool/change_tax_contract.json');
  final contract = _object(jsonDecode(await contractFile.readAsString()));
  final scenarios = _validateContract(contract);
  if (scenarioFilters.isNotEmpty) {
    final known = scenarios.map((scenario) => scenario.id).toSet();
    final unknownFilters = scenarioFilters.difference(known);
    if (unknownFilters.isNotEmpty) {
      throw ArgumentError('Unknown change-tax scenarios: $unknownFilters.');
    }
  }
  if (validateOnly) {
    stdout.writeln('Change-tax contract defines 12 reproducible scenarios.');
    return;
  }

  final root = await Directory.systemTemp.createTemp('dartitect-change-tax-');
  try {
    final source = Directory('${workspace.path}/${contract['source']}');
    final baseline = Directory('${root.path}/baseline');
    await _copyProject(source, baseline);
    await _prepareStandalonePubspec(workspace, baseline);
    await _run(baseline, 'flutter', const <String>['pub', 'get']);
    await _run(baseline, 'dart', const <String>[
      'run',
      'dartitect_cli:dartitect',
      'wiring',
      'sync',
      '--apply',
      '--json',
    ]);
    final baselineSnapshot = await _snapshot(baseline);
    final baselineTax = await ConsumerTaxInspector(baseline).inspect();
    if (!baselineTax.isCompliant ||
        baselineTax.architectureTax['observed'] != 0) {
      throw StateError('Change-tax baseline must have zero architecture tax.');
    }

    final receipts = <Map<String, Object?>>[];
    for (final scenario in scenarios) {
      if (scenarioFilters.isNotEmpty &&
          !scenarioFilters.contains(scenario.id)) {
        continue;
      }
      if (!jsonOutput) stdout.writeln('Change-tax: ${scenario.id}');
      final candidate = Directory('${root.path}/${scenario.id}');
      await _copyProject(baseline, candidate, includeToolState: true);
      await _applyMutation(candidate, scenario);

      final generation = await _timedRun(candidate, 'dart', const <String>[
        'run',
        'dartitect_cli:dartitect',
        'wiring',
        'sync',
        '--apply',
        '--json',
      ]);
      final generationJson = _lastJsonObject(generation.stdout);
      final candidateSnapshot = await _snapshot(candidate);
      final difference = _diff(baselineSnapshot, candidateSnapshot);
      final tax = await ConsumerTaxInspector(candidate).inspect();
      final architectureTax = tax.architectureTax['observed']! as int;
      final baselineArchitectureTax =
          baselineTax.architectureTax['observed']! as int;
      if (!tax.isCompliant ||
          architectureTax != 0 ||
          architectureTax - baselineArchitectureTax != 0) {
        throw StateError(
          '${scenario.id} introduced manual plumbing: '
          '${tax.findings.map((finding) => finding.code).toList()}.',
        );
      }
      final analyzer = await _timedRun(candidate, 'flutter', const <String>[
        'analyze',
        '--no-pub',
      ]);
      final build = await _timedRun(candidate, 'flutter', const <String>[
        'build',
        'bundle',
        '--debug',
        '--no-pub',
      ]);
      receipts.add(<String, Object?>{
        'id': scenario.id,
        'mutation': scenario.mutation,
        'pendingDecisions': scenario.pendingDecisions,
        'manual': difference.manual.toJson(),
        'generated': difference.generated.toJson(),
        'architectureTax': <String, Object?>{
          'before': baselineArchitectureTax,
          'after': architectureTax,
          'delta': architectureTax - baselineArchitectureTax,
          'limit': 0,
        },
        'execution': <String, Object?>{
          'generation': <String, Object?>{
            ...generation.toJson(),
            'writes': generationJson['writes'],
          },
          'analyzer': analyzer.toJson(),
          'build': build.toJson(),
        },
      });
      if (!keepArtifacts) await candidate.delete(recursive: true);
    }

    final runner = Platform.environment['DARTITECT_CI_RUNNER_ID'];
    final report = <String, Object?>{
      'schemaVersion': 1,
      'command': 'change-tax',
      'source': contract['source'],
      'scenarioCount': receipts.length,
      'contractScenarioCount': scenarios.length,
      'runner': runner ?? 'local-${Platform.operatingSystem}',
      'timingsComparable':
          Platform.environment['CI'] == 'true' && runner != null,
      'timingPolicy': runner == null
          ? 'local timings are evidence only and are not ratcheted'
          : 'compare only with the same DARTITECT_CI_RUNNER_ID',
      'manualPlumbingDelta': 0,
      'scenarios': receipts,
      'result': 'passed',
    };
    final encoded = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    if (outputArgument case final argument?) {
      final rawPath = argument.substring('--output='.length);
      final output = File(
        rawPath.startsWith('/') ? rawPath : '${workspace.path}/$rawPath',
      );
      await output.parent.create(recursive: true);
      await output.writeAsString(encoded, flush: true);
    }
    if (jsonOutput) {
      stdout.write(encoded);
    } else {
      stdout.writeln(
        'Change-tax passed ${receipts.length} scenario(s) with zero manual '
        'plumbing delta.',
      );
    }
  } finally {
    if (!keepArtifacts) {
      await root.delete(recursive: true);
    } else {
      stderr.writeln('Change-tax artifacts retained at ${root.path}');
    }
  }
}

List<_Scenario> _validateContract(Map<String, Object?> contract) {
  if (contract['schemaVersion'] != 1 ||
      contract['source'] is! String ||
      contract['scenarioCount'] != 12) {
    throw const FormatException('Invalid change-tax contract header.');
  }
  final requirements = _object(contract['requirements']);
  if (requirements['temporaryCopy'] != true ||
      requirements['manualPlumbingDelta'] != 0 ||
      requirements['recordsManualAndGeneratedDiff'] != true ||
      requirements['recordsGenerationAnalyzerAndBuild'] != true ||
      requirements['localTimingsAreNotRatcheted'] != true) {
    throw const FormatException('Every change-tax requirement must be true.');
  }
  final values = _objects(contract['scenarios']);
  final scenarios = values.map(_Scenario.fromJson).toList(growable: false);
  if (scenarios.length != 12 ||
      scenarios.map((scenario) => scenario.id).toSet().length != 12 ||
      scenarios.any((scenario) => scenario.pendingDecisions.isEmpty)) {
    throw const FormatException(
      'Change-tax requires 12 unique scenarios with pending decisions.',
    );
  }
  return scenarios;
}

Future<void> _applyMutation(Directory root, _Scenario scenario) async {
  final file = File('${root.path}/dartitect.json');
  final config = _object(jsonDecode(await file.readAsString()));
  final features = _object(_object(config['features'])['declarations']);
  Map<String, Object?> feature() => _object(features[scenario.feature]);
  switch (scenario.mutation) {
    case 'add_capability':
      final declaration = feature();
      final capabilities = _strings(declaration['capabilities']).toSet()
        ..add(scenario.value!);
      declaration['capabilities'] = capabilities.toList()..sort();
    case 'set_feature_field':
      feature()[scenario.field!] = scenario.value;
    case 'clear_feature_list':
      feature()[scenario.field!] = <Object?>[];
      if (scenario.field == 'operations') {
        await _removeOpenApiOperationAssertion(root);
      }
    case 'set_feature_list':
      feature()[scenario.field!] = scenario.values;
    case 'set_observability':
      _object(config['observability'])['provider'] = scenario.value;
      if (scenario.value == 'sentry') await _configureSentry(root);
    case 'scheduler_web_only':
      final scheduler = _object(config['scheduler']);
      scheduler['targets'] = <String>['web'];
      for (final declaration
          in features.values.whereType<Map<String, Object?>>()) {
        if (_strings(declaration['headlessTargets']).isNotEmpty) {
          declaration['headlessTargets'] = <String>['web'];
        }
      }
    default:
      throw StateError('Unsupported mutation ${scenario.mutation}.');
  }
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
    flush: true,
  );
}

Future<void> _removeOpenApiOperationAssertion(Directory root) async {
  final test = File('${root.path}/test/large_consumer_test.dart');
  var source = await test.readAsString();
  source = source
      .replaceFirst(
        "import 'package:large_consumer_canary/contracts/app_api.contracts.dartitect.g.dart';\n",
        '',
      )
      .replaceFirst(
        '    expect(onlineapplication1.root.appApiGetProbe, '
            'isA<GetProbeOperation>());\n',
        '',
      );
  await test.writeAsString(source, flush: true);
}

Future<void> _configureSentry(Directory root) async {
  final pubspec = File('${root.path}/pubspec.yaml');
  var pubspecSource = await pubspec.readAsString();
  final workspaceVersion = RegExp(
    r'^version:\s+(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspecSource)?.group(1);
  if (workspaceVersion == null) {
    throw StateError('Large-consumer source lacks its workspace version.');
  }
  const devDependencies = '\ndev_dependencies:\n';
  pubspecSource = pubspecSource.replaceFirst(
    devDependencies,
    '\n  dartitect_sentry:\n'
    '    git:\n'
    '      url: https://github.com/ftr-tuta/dartitect.git\n'
    '      path: packages/dartitect_sentry\n'
    "      tag_pattern: 'v{{version}}'\n"
    '    version: $workspaceVersion\n'
    '  sentry: ^9.27.0\n'
    '$devDependencies',
  );
  if (!pubspecSource.contains('  dartitect_sentry:\n') ||
      !pubspecSource.contains('  sentry: ^9.27.0\n')) {
    throw StateError(
      'Large-consumer source lacks the dev_dependencies boundary.',
    );
  }
  await pubspec.writeAsString(pubspecSource, flush: true);

  await File('${root.path}/lib/sentry_observability.dart').writeAsString('''
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sentry/dartitect_sentry.dart';
import 'package:sentry/sentry.dart';

final _hub = Hub(
  SentryOptions()
    ..dsn = 'https://public@example.invalid/1'
    ..transport = _DiscardingTransport(),
);

DestinationAwareObservabilityRuntime createSentryObservability() =>
    ObservabilityRuntime.withPrivacy(
  privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
    profile: ObservabilityPrivacyProfile.balanced,
  ),
  destinations: <ObservabilityDestinationRegistration>[
    ObservabilityDestinationRegistration.remote(
      name: 'sentry',
      logSinks: <PreparedLogSinkRegistration>[
        PreparedLogSinkRegistration.borrowed(
          SentryLogSink.sanitizedInput(hub: _hub),
        ),
      ],
    ),
  ],
);

final class _DiscardingTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => null;
}
''', flush: true);

  final main = File('${root.path}/lib/main.dart');
  var mainSource = await main.readAsString();
  mainSource = mainSource
      .replaceFirst(
        "import 'presentation/large_app.dart';",
        "import 'presentation/large_app.dart';\n"
            "import 'sentry_observability.dart';",
      )
      .replaceFirst(
        '  create: ApplicationModule.create,',
        '  create: () => ApplicationModule.create(\n'
            '    createObservability: createSentryObservability,\n'
            '  ),',
      );
  await main.writeAsString(mainSource, flush: true);

  final test = File('${root.path}/test/large_consumer_test.dart');
  var testSource = await test.readAsString();
  testSource = testSource
      .replaceFirst(
        "import 'package:large_consumer_canary/large_factories.dart';",
        "import 'package:large_consumer_canary/large_factories.dart';\n"
            "import 'package:large_consumer_canary/sentry_observability.dart';",
      )
      .replaceFirst(
        'final coordinator = ApplicationModule.create();',
        'final coordinator = ApplicationModule.create(\n'
            '      createObservability: createSentryObservability,\n'
            '    );',
      );
  await test.writeAsString(testSource, flush: true);
}

Future<void> _prepareStandalonePubspec(
  Directory workspace,
  Directory project,
) async {
  final pubspec = File('${project.path}/pubspec.yaml');
  var source = await pubspec.readAsString();
  source = source.replaceFirst('resolution: workspace\n\n', '');
  final release = _object(
    jsonDecode(
      await File('${workspace.path}/tool/package_release_contract.json')
          .readAsString(),
    ),
  );
  final packages = _strings(release['dependencyOrder']);
  source =
      '$source\ndependency_overrides:\n'
      '${packages.map((name) => '  $name:\n'
          '    path: ${_yamlPath('${workspace.path}/packages/$name')}\n').join()}';
  await pubspec.writeAsString(source, flush: true);
}

Future<_Snapshot> _snapshot(Directory root) async {
  final manual = <String, List<String>>{};
  final generated = <String, List<String>>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (_ignored(relative)) continue;
    final isGenerated =
        relative.endsWith('.dartitect.g.dart') ||
        relative.startsWith('.dartitect/generation/');
    if (!isGenerated && relative != 'dartitect.json') continue;
    final lines = const LineSplitter().convert(await entity.readAsString());
    (isGenerated ? generated : manual)[relative] = lines;
  }
  return _Snapshot(manual: manual, generated: generated);
}

_Difference _diff(_Snapshot before, _Snapshot after) => _Difference(
  manual: _diffGroup(before.manual, after.manual),
  generated: _diffGroup(before.generated, after.generated),
);

_DiffGroup _diffGroup(
  Map<String, List<String>> before,
  Map<String, List<String>> after,
) {
  var added = 0;
  var removed = 0;
  var changedFiles = 0;
  final paths = <String>{...before.keys, ...after.keys}.toList()..sort();
  for (final path in paths) {
    final left = before[path] ?? const <String>[];
    final right = after[path] ?? const <String>[];
    if (_sameLines(left, right)) continue;
    changedFiles += 1;
    final common = _longestCommonSubsequenceLength(left, right);
    removed += left.length - common;
    added += right.length - common;
  }
  return _DiffGroup(
    files: changedFiles,
    addedLines: added,
    removedLines: removed,
  );
}

int _longestCommonSubsequenceLength(List<String> left, List<String> right) {
  var previous = List<int>.filled(right.length + 1, 0);
  for (final leftLine in left) {
    final current = List<int>.filled(right.length + 1, 0);
    for (var column = 1; column <= right.length; column += 1) {
      current[column] = leftLine == right[column - 1]
          ? previous[column - 1] + 1
          : (current[column - 1] > previous[column]
                ? current[column - 1]
                : previous[column]);
    }
    previous = current;
  }
  return previous.last;
}

bool _sameLines(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<void> _copyProject(
  Directory source,
  Directory destination, {
  bool includeToolState = false,
}) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path
        .substring(source.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (_ignored(relative, includeToolState: includeToolState)) continue;
    final target =
        '${destination.path}/${relative.replaceAll('/', Platform.pathSeparator)}';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    } else if (entity is Link) {
      throw StateError('Change-tax source cannot contain symlinks: $relative.');
    }
  }
}

bool _ignored(String path, {bool includeToolState = false}) {
  final first = path.split('/').first;
  if (const <String>{'build', '.idea'}.contains(first)) return true;
  if (!includeToolState && first == '.dart_tool') return true;
  if (path.startsWith('linux/flutter/ephemeral/')) return true;
  return path == '.flutter-plugins-dependencies';
}

Future<_CommandReceipt> _timedRun(
  Directory workingDirectory,
  String executable,
  List<String> arguments,
) async {
  final timer = Stopwatch()..start();
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  ).timeout(const Duration(minutes: 12));
  timer.stop();
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed in ${workingDirectory.path}:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return _CommandReceipt(
    command: '$executable ${arguments.join(' ')}',
    durationMilliseconds: timer.elapsedMilliseconds,
    stdout: result.stdout as String,
  );
}

Future<void> _run(
  Directory workingDirectory,
  String executable,
  List<String> arguments,
) async {
  await _timedRun(workingDirectory, executable, arguments);
}

Map<String, Object?> _lastJsonObject(String output) {
  for (final line in const LineSplitter().convert(output).reversed) {
    if (!line.trimLeft().startsWith('{')) continue;
    final decoded = jsonDecode(line);
    if (decoded is Map<String, Object?>) return decoded;
  }
  throw const FormatException('Command did not emit a JSON object.');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON object list.');
  }
  return value.map(_object).toList(growable: false);
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

String _yamlPath(String value) => value.contains(' ') ? "'$value'" : value;

final class _Scenario {
  const _Scenario({
    required this.id,
    required this.mutation,
    required this.pendingDecisions,
    this.feature,
    this.field,
    this.value,
    this.values = const <String>[],
  });

  factory _Scenario.fromJson(Map<String, Object?> json) => _Scenario(
    id: json['id']! as String,
    mutation: json['mutation']! as String,
    pendingDecisions: _strings(json['pendingDecisions']),
    feature: json['feature'] as String?,
    field: json['field'] as String?,
    value: json['value'] as String?,
    values: json['values'] == null
        ? const <String>[]
        : _strings(json['values']),
  );

  final String id;
  final String mutation;
  final List<String> pendingDecisions;
  final String? feature;
  final String? field;
  final String? value;
  final List<String> values;
}

final class _Snapshot {
  const _Snapshot({required this.manual, required this.generated});

  final Map<String, List<String>> manual;
  final Map<String, List<String>> generated;
}

final class _Difference {
  const _Difference({required this.manual, required this.generated});

  final _DiffGroup manual;
  final _DiffGroup generated;
}

final class _DiffGroup {
  const _DiffGroup({
    required this.files,
    required this.addedLines,
    required this.removedLines,
  });

  final int files;
  final int addedLines;
  final int removedLines;

  Map<String, Object?> toJson() => <String, Object?>{
    'files': files,
    'addedLines': addedLines,
    'removedLines': removedLines,
    'changedLines': addedLines + removedLines,
  };
}

final class _CommandReceipt {
  const _CommandReceipt({
    required this.command,
    required this.durationMilliseconds,
    required this.stdout,
  });

  final String command;
  final int durationMilliseconds;
  final String stdout;

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command,
    'exitCode': 0,
    'durationMilliseconds': durationMilliseconds,
  };
}
