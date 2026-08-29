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
      '--no-baseline',
      '--root',
      project.path,
    ]);
    await _run(project, 'flutter', const <String>['analyze']);
    if (scenario.feature == null) {
      await _run(project, 'flutter', const <String>['build', 'bundle']);
    } else {
      await _run(project, 'flutter', const <String>['test']);
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
    observability: DartitectObservabilityConfig(
      provider: scenario.observability,
    ),
  );
  await file.writeAsString(next.encode(), flush: true);
  if (feature?.profile == 'offline-full') {
    final pubspec = File('${project.path}/pubspec.yaml');
    final source = await pubspec.readAsString();
    await pubspec.writeAsString(
      source
          .replaceFirst(
            'dev_dependencies:\n',
            '  dartitect_sync:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_sync')}\n'
                'dev_dependencies:\n',
          )
          .replaceFirst(
            'dependency_overrides:\n',
            'dependency_overrides:\n'
                '  dartitect_jobs:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_jobs')}\n'
                '  dartitect_resilience:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_resilience')}\n'
                '  dartitect_sync:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_sync')}\n',
          ),
      flush: true,
    );
  }
  if (scenario.background) {
    final pubspec = File('${project.path}/pubspec.yaml');
    final source = await pubspec.readAsString();
    await pubspec.writeAsString(
      source
          .replaceFirst(
            'dev_dependencies:\n',
            '  dartitect_observability:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_observability')}\n'
                '  dartitect_sentry:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_sentry')}\n'
                'dev_dependencies:\n',
          )
          .replaceFirst(
            'dependency_overrides:\n',
            'dependency_overrides:\n'
                '  dartitect_observability:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_observability')}\n'
                '  dartitect_sentry:\n'
                '    path: ${_yamlPath('${workspace.path}/packages/dartitect_sentry')}\n',
          ),
      flush: true,
    );
  }
}

Future<void> _verifyProviderNeutralScaffold(
  Directory project,
  _Scenario scenario,
) async {
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
}

Future<void> _run(
  Directory workingDirectory,
  String executable,
  List<String> arguments,
) async {
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
}

String _yamlPath(String path) => path.contains(' ') ? "'$path'" : path;

final class _Scenario {
  const _Scenario(
    this.label, {
    required this.observability,
    this.background = false,
    this.feature,
  });

  final String label;
  final String observability;
  final bool background;
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
