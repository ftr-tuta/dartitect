import 'dart:convert';
import 'dart:io';

import '../packages/dartitect_cli/lib/src/config/dartitect_config.dart';

Future<void> main(List<String> arguments) async {
  final workspace = File.fromUri(Platform.script).parent.parent.absolute;
  final builds = arguments.contains('--builds');
  final requested = arguments
      .where((argument) => !argument.startsWith('--'))
      .toSet();
  const scenarios = <_Scenario>[
    _Scenario('minimal', observability: 'none'),
    _Scenario('extensions', observability: 'none', extensions: true),
    _Scenario(
      'online',
      observability: 'developer',
      feature: _FeatureScenario('search', profile: 'online', transport: true),
    ),
    _Scenario(
      'offline',
      observability: 'developer',
      feature: _FeatureScenario(
        'orders',
        profile: 'offline-full',
        scope: 'session',
        storage: true,
        transport: true,
        pagination: true,
        capabilities: 'credentials,attachments,forms,queries',
      ),
    ),
    _Scenario('sentry', observability: 'sentry', background: true),
  ];
  for (final scenario in scenarios) {
    if (requested.isNotEmpty && !requested.contains(scenario.label)) continue;
    await _validateScenario(workspace, scenario, builds: builds);
  }
}

Future<void> _validateScenario(
  Directory workspace,
  _Scenario scenario, {
  required bool builds,
}) async {
  final parent = await Directory.systemTemp.createTemp(
    'dartitect generated matrix ${scenario.label} ',
  );
  final project = Directory('${parent.path}/generated_${scenario.label}');
  var succeeded = false;
  stdout.writeln('Validating generated scenario: ${scenario.label}');
  try {
    await _run(workspace, 'dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'create',
      'app',
      'generated_${scenario.label}',
      '--root',
      parent.path,
      '--targets=linux,web',
    ]);
    await _configureScenario(workspace, project, scenario);
    await _run(project, 'flutter', const <String>['pub', 'get']);
    final feature = scenario.feature;
    if (feature != null) {
      await _run(workspace, 'dart', <String>[
        'run',
        'dartitect_cli:dartitect',
        'create',
        'feature',
        feature.name,
        '--root',
        project.path,
        '--profile=${feature.profile}',
        '--scope=${feature.scope}',
        '--targets=linux,web',
        if (feature.storage) '--storage-context=primary',
        if (feature.transport) '--transport=api',
        if (feature.pagination) '--pagination=cursor',
        '--diagnostics=full',
        if (feature.capabilities.isNotEmpty)
          '--capabilities=${feature.capabilities}',
      ]);
    }
    await _run(workspace, 'dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'wiring',
      'sync',
      '--apply',
      '--root',
      project.path,
    ]);
    await _run(workspace, 'dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'codex',
      'sync',
      '--root',
      project.path,
    ]);
    await File('${project.path}/analysis_options.yaml').writeAsString('''
analyzer:
  exclude:
    - "**/*.g.dart"
plugins:
  dartitect_lints:
    path: ${_yamlPath('${workspace.path}/tool/analyzer_plugin_workspace/dartitect_lints')}
''', flush: true);
    if (scenario.background) {
      await File('${project.path}/lib/background.dart').writeAsString('''
import 'dart:isolate';

import 'package:dartitect_observability/dartitect_observability.dart';

@pragma('vm:entry-point')
Future<void> backgroundMain(SendPort output) async {
  final runtime = ObservabilityRuntime();
  runtime.logger.info('Background composition started.');
  output.send('ready');
  await runtime.disposeAsync();
}
''', flush: true);
    }
    await _run(project, 'flutter', const <String>['pub', 'get']);
    await _run(workspace, 'dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'doctor',
      '--deep',
      '--root',
      project.path,
    ]);
    await _run(workspace, 'dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'scan',
      '--root',
      project.path,
    ]);
    final analysisMillis = await _runTimed(project, 'flutter', const <String>[
      'analyze',
    ]);
    final int buildMillis;
    if (scenario.feature == null && !scenario.extensions) {
      buildMillis = await _runTimed(project, 'flutter', const <String>[
        'build',
        'bundle',
      ]);
    } else {
      buildMillis = await _runTimed(project, 'flutter', const <String>['test']);
    }
    await _writeConsumerTaxMetrics(
      project,
      analysisMillis: analysisMillis,
      buildMillis: buildMillis,
    );
    await _run(workspace, 'dart', <String>[
      'run',
      'dartitect_cli:dartitect',
      'inspect',
      '--consumer-tax',
      '--json',
      '--root',
      project.path,
    ]);
    if (scenario.label == 'minimal') {
      await _verifyMinimalDependencyClosure(project);
    }
    await _verifyProviderNeutralScaffold(project, scenario);
    if (builds) {
      await _run(project, 'flutter', const <String>['build', 'web']);
      if (Platform.isLinux) {
        await _run(project, 'flutter', const <String>['build', 'linux']);
      }
    }
    succeeded = true;
  } finally {
    if (succeeded) {
      await parent.delete(recursive: true);
    } else {
      stderr.writeln('Matrix artifacts retained at ${parent.path}');
    }
  }
}

Future<void> _configureScenario(
  Directory workspace,
  Directory project,
  _Scenario scenario,
) async {
  final file = File('${project.path}/dartitect.json');
  final prior = DartitectConfig.parse(await file.readAsString());
  const targets = <DartitectPlatform>[
    DartitectPlatform.linux,
    DartitectPlatform.web,
  ];
  final feature = scenario.feature;
  final next = DartitectConfig(
    configVersion: prior.configVersion,
    profile: prior.profile,
    layers: prior.layers,
    compositionRoots: prior.compositionRoots,
    generatedInfrastructure: prior.generatedInfrastructure,
    generatedSuffixes: prior.generatedSuffixes,
    suppressions: prior.suppressions,
    modeling: prior.modeling,
    extensionSources: scenario.extensions
        ? const <String>['lib/project_extensions.dart']
        : const <String>[],
    targets: DartitectTargetsConfig(targets),
    storageContexts: feature?.storage ?? false
        ? <String, DartitectStorageContextConfig>{
            'primary': DartitectStorageContextConfig(
              provider: 'drift',
              mode: DartitectStorageMode.durable,
              targets: targets,
            ),
          }
        : const <String, DartitectStorageContextConfig>{},
    transports: feature?.transport ?? false
        ? <String, DartitectTransportConfig>{
            'api': DartitectTransportConfig(provider: 'dio', targets: targets),
          }
        : const <String, DartitectTransportConfig>{},
    session: feature?.scope == 'session'
        ? DartitectSessionConfig(
            factorySource: DartitectFactorySourceConfig(
              source: 'lib/composition/session_factory.dart',
              declaration: 'SessionFactory',
            ),
          )
        : prior.session,
    observability: DartitectObservabilityConfig(
      provider: scenario.observability,
    ),
  );
  await file.writeAsString(next.encode(), flush: true);
  await _writeContextFactories(project, feature);
  if (scenario.extensions) {
    await File('${project.path}/lib/project_extensions.dart').writeAsString('''
import 'package:dartitect/dartitect.dart';

final class LocalClock {
  var disposed = false;
}

@DartitectProjectExtension()
final class LocalClockExtension
    implements DartitectLocalExtension<LocalClock> {
  @override
  LocalClock build() => LocalClock();

  @override
  void dispose(LocalClock binding) => binding.disposed = true;
}

final class LocalAudit {
  var disposed = false;
}

@DartitectProjectExtension()
final class LocalAuditExtension
    implements DartitectLocalExtension<LocalAudit> {
  @override
  LocalAudit build() => LocalAudit();

  @override
  void dispose(LocalAudit binding) => binding.disposed = true;
}
''', flush: true);
    await File('${project.path}/test/extension_ownership_test.dart')
        .writeAsString('''
import 'package:dartitect/dartitect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generated_extensions/composition/application_module.wiring.dartitect.g.dart';

void main() {
  test('generated local extensions are owned and disposed', () async {
    final coordinator = ApplicationModule.create();
    final attempt = await coordinator.run();
    final success = attempt as BootstrapSucceeded<ApplicationGraph>;
    final graph = success.graph;
    expect(graph.root.localClock.disposed, isFalse);
    expect(graph.root.localAudit.disposed, isFalse);

    await graph.disposeAsync();

    expect(graph.root.localClock.disposed, isTrue);
    expect(graph.root.localAudit.disposed, isTrue);
    await graph.disposeAsync();
    await coordinator.disposeAsync();
  });
}
''', flush: true);
  }
  await _addGitSdkDependencies(project, <String>{
    if (scenario.observability != 'none') 'dartitect_observability',
    if (scenario.observability == 'sentry') 'dartitect_sentry',
    if (feature?.transport ?? false) 'dartitect_dio',
    if (feature?.storage ?? false) 'dartitect_drift',
    if (feature?.profile == 'offline-full') 'dartitect_sync',
  });
  if (scenario.background) {
    final main = File('${project.path}/lib/main.dart');
    final mainSource = await main.readAsString();
    await main.writeAsString(
      mainSource
              .replaceFirst(
                "import 'package:dartitect_flutter/dartitect_flutter.dart';",
                "import 'package:dartitect_flutter/dartitect_flutter.dart';\n"
                    "import 'package:dartitect_observability/dartitect_observability.dart';\n"
                    "import 'package:dartitect_sentry/dartitect_sentry.dart';\n"
                    "import 'package:sentry/sentry.dart';",
              )
              .replaceFirst(
                '  create: ApplicationModule.create,',
                '  create: () => ApplicationModule.create(\n'
                    '    createObservability: _createObservability,\n'
                    '  ),',
              ) +
          '''

final _sentryHub = Hub(
  SentryOptions()
    ..dsn = 'https://public@example.invalid/1'
    ..transport = _DiscardingSentryTransport(),
);

ObservabilityRuntime _createObservability() => ObservabilityRuntime(
  logSinks: <LogSinkRegistration>[
    LogSinkRegistration.borrowed(SentryLogSink(hub: _sentryHub)),
  ],
);

final class _DiscardingSentryTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => null;
}
''',
      flush: true,
    );
    final pubspec = File('${project.path}/pubspec.yaml');
    final source = await pubspec.readAsString();
    await pubspec.writeAsString(
      source.replaceFirst(
        'dev_dependencies:\n',
        '  sentry: ^9.27.0\n'
            'dev_dependencies:\n',
      ),
      flush: true,
    );
  }
}

Future<void> _writeContextFactories(
  Directory project,
  _FeatureScenario? feature,
) async {
  if (feature == null ||
      (!feature.storage && !feature.transport && feature.scope != 'session')) {
    return;
  }
  final composition = Directory('${project.path}/lib/composition');
  await composition.create(recursive: true);
  if (feature.storage) {
    await File('${composition.path}/storage_context_factory.dart')
        .writeAsString('''
import 'package:dartitect/dartitect.dart';

final class StorageContext {}

@DartitectApplicationContextFactory('primary')
final class StorageContextFactory {
  const StorageContextFactory();

  Future<StorageContext> open() async => StorageContext();

  Future<void> dispose(StorageContext context) async {}
}
''', flush: true);
  }
  if (feature.transport) {
    await File('${composition.path}/transport_context_factory.dart')
        .writeAsString('''
import 'package:dartitect/dartitect.dart';

final class TransportContext {}

@DartitectTransportContextFactory('api')
final class TransportContextFactory {
  const TransportContextFactory();

  Future<TransportContext> open() async => TransportContext();

  Future<void> dispose(TransportContext context) async {}
}
''', flush: true);
  }
  if (feature.scope == 'session') {
    await File('${composition.path}/session_factory.dart').writeAsString('''
import 'package:dartitect/dartitect.dart';

final class AuthenticatedSession {}

@DartitectSessionFactory()
final class SessionFactory {
  const SessionFactory();

  AuthenticatedSession create() => AuthenticatedSession();
}
''', flush: true);
  }
}

Future<void> _addGitSdkDependencies(
  Directory project,
  Set<String> selected,
) async {
  if (selected.isEmpty) return;
  final direct = selected.toList()..sort();
  final pubspec = File('${project.path}/pubspec.yaml');
  var source = await pubspec.readAsString();
  const marker = 'dev_dependencies:\n';
  if (!source.contains(marker)) {
    throw StateError('Generated pubspec lacks dev_dependencies.');
  }
  source = source.replaceFirst(
    marker,
    '${direct.map((package) => '  $package:\n'
        '    git:\n'
        '      url: https://github.com/ftr-tuta/dartitect.git\n'
        '      path: packages/$package\n'
        "      tag_pattern: 'v{{version}}'\n"
        '    version: 1.0.0\n').join()}'
    '$marker',
  );
  await pubspec.writeAsString(source, flush: true);
}

Future<void> _verifyProviderNeutralScaffold(
  Directory project,
  _Scenario scenario,
) async {
  final main = await File('${project.path}/lib/main.dart').readAsString();
  for (final token in const <String>[
    'ThemeData(useMaterial3: true)',
    'GlobalMaterialLocalizations.delegates',
    'DartitectResponsiveWindowBuilder(',
    'NavigationBar(',
    'NavigationRail(',
  ]) {
    if (!main.contains(token)) {
      throw StateError('Generated app shell is missing $token.');
    }
  }
  final matrixTest = await File('${project.path}/test/ui_matrix_test.dart')
      .readAsString();
  if (!matrixTest.contains('testDartitectUiMatrix(') ||
      !matrixTest.contains('FilledButton(')) {
    throw StateError('Generated app lacks the paired Material UI base test.');
  }
  final pubspec = await File('${project.path}/pubspec.yaml').readAsString();
  if (!pubspec.contains('flutter_localizations:') ||
      !pubspec.contains('dartitect_flutter_testing:')) {
    throw StateError('Generated app lacks localization or UI test wiring.');
  }

  final dartFiles = <File>[];
  await for (final entity in Directory(
    '${project.path}/lib',
  ).list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) dartFiles.add(entity);
  }
  for (final file in dartFiles) {
    final relative = file.path
        .substring(project.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final source = await file.readAsString();
    if ((relative.contains('/domain/') ||
            relative.contains('/application/') ||
            relative.contains('/presentation/')) &&
        (source.contains('package:drift/') ||
            source.contains('package:dartitect_drift/'))) {
      throw StateError('Drift leaked into provider-neutral $relative.');
    }
  }
  if (scenario.feature != null &&
      !dartFiles.any(
        (file) =>
            file.path.contains(
              '${Platform.pathSeparator}presentation${Platform.pathSeparator}',
            ) &&
            file.readAsStringSync().contains('CommandStateBuilder'),
      )) {
    throw StateError('Generated feature lacks exhaustive command rendering.');
  }
}

Future<void> _run(
  Directory workingDirectory,
  String executable,
  List<String> arguments,
) async {
  await _runTimed(workingDirectory, executable, arguments);
}

Future<int> _runTimed(
  Directory workingDirectory,
  String executable,
  List<String> arguments,
) async {
  final timer = Stopwatch()..start();
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory.path,
  ).timeout(const Duration(minutes: 8));
  if (result.exitCode != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  timer.stop();
  return timer.elapsedMilliseconds;
}

Future<void> _writeConsumerTaxMetrics(
  Directory project, {
  required int analysisMillis,
  required int buildMillis,
}) async {
  final target = File('${project.path}/.dartitect/consumer-tax-metrics.json');
  await target.parent.create(recursive: true);
  await target.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'schemaVersion': 1, 'analysisMillis': analysisMillis, 'buildMillis': buildMillis})}\n',
    flush: true,
  );
}

Future<void> _verifyMinimalDependencyClosure(Directory project) async {
  final lock = await File('${project.path}/pubspec.lock').readAsString();
  const forbidden = <String>{
    'dio',
    'dartitect_dio',
    'drift',
    'dartitect_drift',
    'dartitect_sync',
    'workmanager',
    'dartitect_workmanager',
  };
  final resolved = RegExp(
    r'^  ([a-zA-Z][a-zA-Z0-9_]*):$',
    multiLine: true,
  ).allMatches(lock).map((match) => match.group(1)!).toSet();
  final leaked = forbidden.intersection(resolved).toList()..sort();
  if (leaked.isNotEmpty) {
    throw StateError(
      'Minimal generated project resolved unselected capabilities: $leaked.',
    );
  }
}

String _yamlPath(String path) => path.contains(' ') ? "'$path'" : path;

final class _Scenario {
  const _Scenario(
    this.label, {
    required this.observability,
    this.background = false,
    this.extensions = false,
    this.feature,
  });

  final String label;
  final String observability;
  final bool background;
  final bool extensions;
  final _FeatureScenario? feature;
}

final class _FeatureScenario {
  const _FeatureScenario(
    this.name, {
    required this.profile,
    this.scope = 'application',
    this.storage = false,
    this.transport = false,
    this.pagination = false,
    this.capabilities = '',
  });

  final String name;
  final String profile;
  final String scope;
  final bool storage;
  final bool transport;
  final bool pagination;
  final String capabilities;
}
