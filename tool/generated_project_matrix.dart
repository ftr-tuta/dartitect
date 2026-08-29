import 'dart:io';

Future<void> main(List<String> arguments) async {
  final workspace = File.fromUri(Platform.script).parent.parent.absolute;
  final builds = arguments.contains('--builds');
  const scenarios = <_Scenario>[
    _Scenario('minimal', preset: 'minimal', observability: 'none'),
    _Scenario(
      'online',
      preset: 'minimal',
      observability: 'developer',
      feature: _FeatureScenario('search', profile: 'online'),
    ),
    _Scenario(
      'offline',
      preset: 'offline-hybrid',
      observability: 'developer',
      feature: _FeatureScenario(
        'orders',
        profile: 'offline-full',
        scope: 'session',
        persistenceNative: 'drift',
        persistenceWeb: 'drift',
        pagination: true,
        headless: true,
        capabilities: 'credentials,attachments,forms,queries',
      ),
    ),
    _Scenario(
      'sentry',
      preset: 'offline-hybrid',
      observability: 'sentry',
      background: true,
    ),
  ];
  for (final scenario in scenarios) {
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
      '--preset=${scenario.preset}',
      '--transport=dio',
      '--observability=${scenario.observability}',
      '--scheduler=workmanager',
    ]);
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
        '--persistence-native=${feature.persistenceNative}',
        '--persistence-web=${feature.persistenceWeb}',
        '--transport=dio',
        if (feature.pagination) '--pagination=cursor',
        if (feature.headless) '--headless-sync',
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
    await _run(project, 'flutter', const <String>['test']);
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
  if (scenario.preset != 'offline-hybrid') return;
  final recipe = File('${project.path}/docs/drift-composition-root.md');
  if (!await recipe.exists()) {
    throw StateError('Drift composition-root recipe was not generated.');
  }
  final managedOperationalSchema = dartFiles.any(
    (file) =>
        file.path.endsWith('.dartitect.g.dart') &&
        (file.path.contains('drift') || file.path.contains('outbox')),
  );
  if (!managedOperationalSchema) {
    throw StateError('Drift operational schema was not generated as managed.');
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
    required this.preset,
    required this.observability,
    this.background = false,
    this.feature,
  });

  final String label;
  final String preset;
  final String observability;
  final bool background;
  final _FeatureScenario? feature;
}

final class _FeatureScenario {
  const _FeatureScenario(
    this.name, {
    required this.profile,
    this.scope = 'application',
    this.persistenceNative = 'none',
    this.persistenceWeb = 'none',
    this.pagination = false,
    this.headless = false,
    this.capabilities = '',
  });

  final String name;
  final String profile;
  final String scope;
  final String persistenceNative;
  final String persistenceWeb;
  final bool pagination;
  final bool headless;
  final String capabilities;
}
