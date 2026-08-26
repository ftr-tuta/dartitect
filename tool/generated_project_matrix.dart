import 'dart:io';

Future<void> main(List<String> arguments) async {
  final workspace = File.fromUri(Platform.script).parent.parent.absolute;
  final builds = arguments.contains('--builds');
  const scenarios = <_Scenario>[
    _Scenario('core', 'none', <String>[], blueprint: 'simple'),
    _Scenario(
      'observability',
      'developer',
      <String>[],
      blueprint: 'remote-read',
    ),
    _Scenario('dio', 'developer', <String>['dio'], blueprint: 'local-first'),
    _Scenario('objectbox', 'developer', <String>[
      'objectbox',
    ], blueprint: 'offline-mutation'),
    _Scenario('sentry', 'sentry', <String>[
      'sentry',
    ], blueprint: 'sync-dataset'),
    _Scenario('full', 'sentry', <String>['dio', 'objectbox', 'sentry']),
    _Scenario('background', 'developer', <String>[], background: true),
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
      '--observability=${scenario.observability}',
      if (scenario.adapters.isNotEmpty)
        '--adapters=${scenario.adapters.join(',')}',
      if (scenario.blueprint != null) '--blueprint=${scenario.blueprint}',
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
    path: ${_yamlPath('${workspace.path}/packages/dartitect_lints')}
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
    if (builds) {
      await _run(project, 'flutter', const <String>['build', 'web']);
      if (Platform.isLinux) {
        await _run(project, 'flutter', const <String>['build', 'linux']);
      }
    }
    if (scenario.adapters.contains('objectbox') && Platform.isLinux) {
      await _run(
        Directory('${workspace.path}/tool/objectbox_native_fixture'),
        'flutter',
        const <String>['test'],
      );
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
    this.label,
    this.observability,
    this.adapters, {
    this.background = false,
    this.blueprint,
  });

  final String label;
  final String observability;
  final List<String> adapters;
  final bool background;
  final String? blueprint;
}
