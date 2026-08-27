import 'dart:convert';
import 'dart:io';

import '../config/dartitect_config.dart';
import '../diagnostics/models.dart';
import '../diagnostics/sarif.dart';
import '../fleet/fleet_service.dart';
import '../generation/generation_engine.dart';
import '../generation/scaffolds.dart';
import '../model/model_generator.dart';
import '../policy/ecosystem_policy.dart';
import '../project/dartitect_project_service.dart';
import '../scan/project_scanner.dart';

/// Stable CLI exit statuses.
enum DartitectExitCode {
  /// Command completed with no validation findings.
  success(0),

  /// Command completed and found validation concerns.
  findings(1),

  /// Command usage or configuration is invalid.
  usage(2),

  /// Unexpected IO or internal failure.
  internal(3);

  const DartitectExitCode(this.code);

  /// Process-compatible integer status.
  final int code;
}

/// Native command dispatcher with injectable output sinks.
final class DartitectCliRunner {
  /// Creates a CLI runner.
  DartitectCliRunner({
    StringSink? stdoutSink,
    StringSink? stderrSink,
    Directory? currentDirectory,
  }) : _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr,
       _currentDirectory = (currentDirectory ?? Directory.current).absolute;

  final StringSink _stdout;
  final StringSink _stderr;
  final Directory _currentDirectory;

  /// Parses and executes [arguments].
  Future<int> run(List<String> arguments) async {
    try {
      if (arguments.isEmpty ||
          arguments.singleOrNull == '--help' ||
          arguments.singleOrNull == '-h') {
        _stdout.writeln(_help);
        return DartitectExitCode.success.code;
      }
      if (arguments.singleOrNull == '--version') {
        _stdout.writeln(CommandEnvelope.sdkVersion);
        return DartitectExitCode.success.code;
      }

      final command = arguments.first;
      final parsed = _CliArguments(arguments.skip(1).toList());
      final root = parsed.root == null
          ? _currentDirectory
          : Directory(_absolute(parsed.root!));
      return switch (command) {
        'scan' => await _readOnly('scan', root, parsed),
        'doctor' => await _readOnly('doctor', root, parsed),
        'inspect' => await _readOnly('inspect', root, parsed),
        'init' => await _init(root, parsed),
        'create' => await _create(root, parsed),
        'baseline' => await _baseline(root, parsed),
        'codex' => await _codex(root, parsed),
        'model' => await _model(root, parsed),
        'dependencies' => await _dependencies(root, parsed),
        'fleet' => await _fleet(root, parsed),
        _ => _usageError('Unknown command "$command".'),
      };
    } on _UsageException catch (error) {
      return _usageError(error.message);
    } on DartitectConfigException catch (error) {
      return _usageError(error.toString());
    } on FormatException catch (error) {
      return _usageError(error.message);
    } on GenerationException catch (error) {
      _stderr.writeln(error.message);
      if (error.recoveryPaths.isNotEmpty) {
        _stderr.writeln(
          'Manual recovery may be required for: '
          '${error.recoveryPaths.join(', ')}',
        );
      }
      return switch (error.kind) {
        GenerationFailureKind.conflict => DartitectExitCode.findings.code,
        GenerationFailureKind.invalidConfiguration =>
          DartitectExitCode.usage.code,
        GenerationFailureKind.recovery ||
        GenerationFailureKind.io => DartitectExitCode.internal.code,
      };
    } on DartitectChangeException catch (error) {
      _stderr.writeln('${error.code}: ${error.message}');
      return DartitectExitCode.findings.code;
    } on FileSystemException catch (error) {
      _stderr.writeln('IO failure: ${error.message}');
      return DartitectExitCode.internal.code;
    } on Object catch (error, stackTrace) {
      _stderr.writeln('Internal failure: $error');
      if (arguments.contains('--verbose')) {
        _stderr.writeln(stackTrace);
      }
      return DartitectExitCode.internal.code;
    }
  }

  Future<int> _readOnly(
    String command,
    Directory root,
    _CliArguments arguments,
  ) async {
    arguments.requireNoPositionals();
    arguments.requireOnlyFlags(<String>{
      'json',
      if (command == 'scan') 'sarif',
      'deep',
      'verbose',
      if (command == 'scan') 'no-baseline',
    });
    if (arguments.flags.contains('json') && arguments.flags.contains('sarif')) {
      throw const _UsageException('--json and --sarif are mutually exclusive.');
    }
    final service = DartitectProjectService(root);
    final envelope = switch (command) {
      'scan' => await service.scanArchitecture(
        useBaseline: !arguments.flags.contains('no-baseline'),
      ),
      'doctor' => await service.doctorProject(
        deep: arguments.flags.contains('deep'),
      ),
      _ => await service.inspectProject(),
    };
    if (arguments.flags.contains('sarif')) {
      _stdout.writeln(jsonEncode(DartitectSarifReport.fromEnvelope(envelope)));
    } else {
      _writeEnvelope(envelope, json: arguments.flags.contains('json'));
    }
    return envelope.exitCode;
  }

  Future<int> _init(Directory root, _CliArguments arguments) async {
    arguments.requireNoPositionals();
    arguments.requireOnlyFlags(<String>{'dry-run', 'verbose'});
    final service = DartitectProjectService(root);
    final plan = await service.previewChange(DartitectChangeKind.init);
    for (final operation in plan.operations) {
      _stdout.writeln(operation);
    }
    if (arguments.flags.contains('dry-run')) {
      _stdout.writeln('DRY-RUN no files written.');
    } else {
      await service.applyChange(plan);
    }
    return DartitectExitCode.success.code;
  }

  Future<int> _create(Directory root, _CliArguments arguments) async {
    if (arguments.positionals.length < 2) {
      throw const _UsageException(
        'Usage: dartitect create <app|simple|remote-read|local-first|offline-mutation|sync-dataset|feature|viewmodel|repository|service> <name>.',
      );
    }
    final kind = arguments.positionals[0];
    final name = arguments.positionals[1];
    if (arguments.positionals.length > 2) {
      throw _UsageException('Unexpected argument: ${arguments.positionals[2]}');
    }
    arguments.requireOnlyFlags(<String>{
      'dry-run',
      'domain',
      'verbose',
      'observability',
      'adapters',
      'blueprint',
    });
    if (kind == 'app') {
      if (arguments.flags.contains('domain')) {
        throw const _UsageException(
          '--domain is valid only for create feature.',
        );
      }
      return _createApp(
        root,
        name,
        dryRun: arguments.flags.contains('dry-run'),
        observability: arguments.options['observability'] ?? 'developer',
        adapters: _parseAdapters(arguments.options['adapters']),
        blueprint: arguments.options['blueprint'] == null
            ? null
            : ScaffoldBlueprint.parse(arguments.options['blueprint']!),
      );
    }

    final scan = await ProjectScanner(root).scan();
    final scaffold = ScaffoldFactory(
      packageName: scan.packageName ?? 'application',
    );
    final operations = switch (kind) {
      'feature' => scaffold.feature(
        name,
        includeDomain: arguments.flags.contains('domain'),
      ),
      'viewmodel' => scaffold.viewModel(name),
      'repository' => scaffold.repository(name),
      'service' => scaffold.service(name),
      'simple' ||
      'remote-read' ||
      'local-first' ||
      'offline-mutation' ||
      'sync-dataset' => scaffold.blueprint(ScaffoldBlueprint.parse(kind), name),
      _ => throw _UsageException('Unknown create target "$kind".'),
    };
    final result = await GenerationEngine(root)
        .apply(operations, dryRun: arguments.flags.contains('dry-run'));
    _writeGeneration(result);
    return DartitectExitCode.success.code;
  }

  Future<int> _createApp(
    Directory parent,
    String input, {
    required bool dryRun,
    required String observability,
    required List<String> adapters,
    required ScaffoldBlueprint? blueprint,
  }) async {
    if (!const <String>{
      'none',
      'developer',
      'sentry',
    }.contains(observability)) {
      throw _UsageException('Unsupported observability mode "$observability".');
    }
    final enabledAdapters = <String>{...adapters};
    if (observability == 'sentry') enabledAdapters.add('sentry');
    for (final adapter in enabledAdapters) {
      if (!const <String>{
        'dio',
        'drift',
        'objectbox',
        'sentry',
      }.contains(adapter)) {
        throw _UsageException('Unsupported adapter "$adapter".');
      }
    }
    final name = ScaffoldName(input);
    final target = Directory(_join(parent.path, name.snake));
    if (await target.exists()) {
      throw GenerationException(
        'Target directory already exists: ${name.snake}.',
      );
    }
    if (dryRun) {
      _stdout.writeln('CREATE ${name.snake}/ (via flutter create)');
      _stdout.writeln('CREATE ${name.snake}/dartitect.json');
      _stdout.writeln('CREATE ${name.snake}/AGENTS.md');
      _stdout.writeln('APPLY native_mvvm Tasks feature');
      return DartitectExitCode.success.code;
    }

    await parent.create(recursive: true);
    final temporary = await parent.createTemp('.${name.snake}.dartitect-app-');
    var moved = false;
    try {
      final result = await Process.run('flutter', <String>[
        'create',
        '--project-name',
        name.snake,
        '--platforms',
        'android,ios,web,windows,linux,macos',
        temporary.path,
      ], workingDirectory: parent.path);
      if (result.exitCode != 0) {
        throw GenerationException(
          'flutter create failed: ${_firstLine('${result.stderr}${result.stdout}')}',
        );
      }

      await _customizeFlutterApp(
        temporary,
        name,
        observability: observability,
        adapters: enabledAdapters.toList()..sort(),
        blueprint: blueprint,
      );
      await temporary.rename(target.path);
      moved = true;
      _stdout.writeln('CREATE ${name.snake}/');
      return DartitectExitCode.success.code;
    } finally {
      if (!moved && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  Future<void> _customizeFlutterApp(
    Directory project,
    ScaffoldName name, {
    required String observability,
    required List<String> adapters,
    required ScaffoldBlueprint? blueprint,
  }) async {
    final pubspec = File(_join(project.path, 'pubspec.yaml'));
    var source = await pubspec.readAsString();
    final localSdk = _findLocalSdkRoot();
    final sdkPackages = <String>{
      'dartitect',
      'dartitect_flutter',
      if (observability != 'none') 'dartitect_observability',
      if (blueprint == ScaffoldBlueprint.offlineMutation ||
          blueprint == ScaffoldBlueprint.syncDataset)
        'dartitect_sync',
      for (final adapter in adapters) 'dartitect_$adapter',
    }.toList()..sort();
    final localOverridePackages = _localSdkPackageClosure(sdkPackages);
    final dependencyBlock = localSdk == null
        ? sdkPackages.map((package) => '  $package: ^1.0.0-rc.3\n').join()
        : sdkPackages
              .map(
                (package) =>
                    '  $package:\n'
                    '    path: ${_yamlQuote(_join(localSdk.path, 'packages/$package'))}\n',
              )
              .join();
    source = source.replaceFirst(
      'dev_dependencies:\n',
      '${dependencyBlock}dev_dependencies:\n',
    );
    if (localSdk != null) {
      source =
          '$source\ndependency_overrides:\n${localOverridePackages.map((package) => '  $package:\n'
              '    path: ${_yamlQuote(_join(localSdk.path, 'packages/$package'))}\n').join()}';
    }
    await pubspec.writeAsString(source, flush: true);

    final widgetTest = File(_join(project.path, 'test/widget_test.dart'));
    if (await widgetTest.exists()) await widgetTest.delete();
    final mainFile = File(_join(project.path, 'lib/main.dart'));
    await mainFile.writeAsString(
      '''import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import 'features/tasks/presentation/tasks_view.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final firstFrame = FirstFrameGate.defer(binding);
  try {
    runApp(const ${name.pascal}App());
  } finally {
    firstFrame.release();
  }
}

final class ${name.pascal}App extends StatelessWidget {
  const ${name.pascal}App({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: '${name.pascal}',
    home: Scaffold(body: Center(child: TasksPage())),
  );
}
''',
      flush: true,
    );

    final scaffold = ScaffoldFactory(packageName: name.snake);
    await GenerationEngine(project).apply(<FileGenerationOperation>[
      ...scaffold.init(),
      ...scaffold.agents(),
      if (blueprint == null)
        ...scaffold.feature('tasks', includeDomain: false)
      else
        ...scaffold.blueprint(blueprint, 'tasks'),
    ]);
    if (adapters.contains('drift')) {
      final recipe = File(
        _join(project.path, 'docs/drift-composition-root.md'),
      );
      await recipe.parent.create(recursive: true);
      await recipe.writeAsString(_driftCompositionRootRecipe, flush: true);
    }
    final format = await Process.run('dart', <String>[
      'format',
      'lib',
      'test',
    ], workingDirectory: project.path);
    if (format.exitCode != 0) {
      throw GenerationException('Generated app formatting failed.');
    }
  }

  Future<int> _baseline(Directory root, _CliArguments arguments) async {
    if (arguments.positionals.length != 1 ||
        arguments.positionals.single != 'create') {
      throw const _UsageException(
        'Usage: dartitect baseline create [--dry-run].',
      );
    }
    arguments.requireOnlyFlags(<String>{'dry-run', 'verbose'});
    final service = DartitectProjectService(root);
    final plan = await service.previewChange(DartitectChangeKind.baseline);
    if (arguments.flags.contains('dry-run')) {
      _stdout.writeln('DRY-RUN ${plan.operations.single}');
      _stdout.write(plan.preview);
      return DartitectExitCode.success.code;
    }
    await service.applyChange(plan);
    _stdout.writeln(plan.operations.single);
    return DartitectExitCode.success.code;
  }

  Future<int> _codex(Directory root, _CliArguments arguments) async {
    if (arguments.positionals.length != 1 ||
        arguments.positionals.single != 'sync') {
      throw const _UsageException(
        'Usage: dartitect codex sync [--dry-run] [--overwrite-managed].',
      );
    }
    arguments.requireOnlyFlags(<String>{
      'dry-run',
      'overwrite-managed',
      'verbose',
    });
    final service = DartitectProjectService(root);
    final plan = await service.previewChange(
      DartitectChangeKind.codexSync,
      overwriteManaged: arguments.flags.contains('overwrite-managed'),
    );
    for (final operation in plan.operations) {
      _stdout.writeln(operation);
    }
    if (arguments.flags.contains('dry-run')) {
      _stdout.writeln('DRY-RUN no files written.');
    } else {
      await service.applyChange(plan);
    }
    return DartitectExitCode.success.code;
  }

  Future<int> _model(Directory root, _CliArguments arguments) async {
    if (arguments.positionals.length != 1 ||
        !const <String>{
          'check',
          'sync',
        }.contains(arguments.positionals.single)) {
      throw const _UsageException(
        'Usage: dartitect model <check|sync> [--json] [--dry-run|--apply].',
      );
    }
    arguments.requireOnlyFlags(<String>{
      'json',
      'verbose',
      if (arguments.positionals.single == 'sync') ...<String>{
        'dry-run',
        'apply',
      },
    });
    if (arguments.flags.contains('dry-run') &&
        arguments.flags.contains('apply')) {
      throw const _UsageException(
        '--dry-run and --apply are mutually exclusive.',
      );
    }
    final generator = DartitectModelGenerator(root);
    final command = arguments.positionals.single;
    if (command == 'check' || !arguments.flags.contains('apply')) {
      final report = await generator.inspect();
      _writeModelReport(
        report,
        json: arguments.flags.contains('json'),
        preview: command == 'sync',
      );
      return report.isFresh
          ? DartitectExitCode.success.code
          : DartitectExitCode.findings.code;
    }

    try {
      final result = await generator.apply();
      if (arguments.flags.contains('json')) {
        _stdout.writeln(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'command': 'model sync',
            'applied': true,
            'created': result.createdPaths,
            'updated': result.updatedPaths,
            'deleted': result.deletedPaths,
            'diagnostics': const <Object?>[],
          }),
        );
      } else {
        _writeGeneration(result);
      }
      return DartitectExitCode.success.code;
    } on ModelGenerationException catch (error) {
      final report = ModelGenerationReport(
        operations: const <FileGenerationOperation>[],
        diagnostics: error.diagnostics,
        plan: null,
      );
      _writeModelReport(
        report,
        json: arguments.flags.contains('json'),
        preview: false,
      );
      return DartitectExitCode.findings.code;
    }
  }

  void _writeModelReport(
    ModelGenerationReport report, {
    required bool json,
    required bool preview,
  }) {
    if (json) {
      _stdout.writeln(jsonEncode(report.toJson()));
      return;
    }
    for (final diagnostic in report.findings) {
      final line = diagnostic.line == null ? '' : ':${diagnostic.line}';
      _stdout.writeln(
        '${diagnostic.code} ${diagnostic.path}$line ${diagnostic.message}',
      );
    }
    if (preview) {
      for (final operation
          in report.plan?.operations ?? const <PlannedFileOperation>[]) {
        _stdout.writeln(
          '${operation.disposition.name.toUpperCase()} '
          '${operation.operation.relativePath}',
        );
      }
      _stdout.writeln('PREVIEW no files written. Use --apply to synchronize.');
    }
  }

  Future<int> _dependencies(Directory root, _CliArguments arguments) async {
    arguments.requireOnlyFlags(<String>{'json', 'verbose'});
    if (arguments.positionals.isEmpty) {
      throw const _UsageException(
        'Usage: dartitect dependencies <audit|explain PACKAGE> [--json].',
      );
    }
    final policy = await EcosystemPolicy.load(root);
    switch (arguments.positionals.first) {
      case 'audit':
        if (arguments.positionals.length != 1) {
          throw const _UsageException(
            'Usage: dartitect dependencies audit [--json].',
          );
        }
        final report = await EcosystemDependencyAuditor(root, policy).audit();
        if (arguments.flags.contains('json')) {
          _stdout.writeln(jsonEncode(report.toJson()));
        } else {
          for (final finding in report.findings) {
            final via = finding.directOwners.isEmpty
                ? ''
                : ' via ${finding.directOwners.join(', ')}';
            final replacement = finding.replacement == null
                ? ''
                : ' Use ${finding.replacement}.';
            _stdout.writeln(
              '${finding.code} ${finding.package}$via ${finding.message}'
              '$replacement',
            );
          }
          if (report.isClean) _stdout.writeln('dependencies audit: healthy');
        }
        return report.isClean
            ? DartitectExitCode.success.code
            : DartitectExitCode.findings.code;
      case 'explain':
        if (arguments.positionals.length != 2 ||
            !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(arguments.positionals[1])) {
          throw const _UsageException(
            'Usage: dartitect dependencies explain <package> [--json].',
          );
        }
        final record = policy.explain(arguments.positionals[1]);
        if (arguments.flags.contains('json')) {
          _stdout.writeln(
            jsonEncode(<String, Object?>{
              'schemaVersion': 1,
              'command': 'dependencies explain',
              ...record.toJson(),
            }),
          );
        } else {
          _stdout.writeln('${record.package}: ${record.decision.name}');
          _stdout.writeln('Owner: ${record.owner}');
          if (record.replacement case final replacement?) {
            _stdout.writeln('Replacement: $replacement');
          }
          _stdout.writeln('Documentation: ${record.documentation}');
        }
        return DartitectExitCode.success.code;
      default:
        throw _UsageException(
          'Unknown dependencies command "${arguments.positionals.first}".',
        );
    }
  }

  Future<int> _fleet(Directory root, _CliArguments arguments) async {
    if (arguments.positionals.length < 2) {
      throw const _UsageException(
        'Usage: dartitect fleet <versions|check|policy|upgrade> <project-root...>.',
      );
    }
    final command = arguments.positionals.first;
    final roots = arguments.positionals.skip(1).toList();
    final service = DartitectFleetService(root);
    late final DartitectFleetReport report;
    switch (command) {
      case 'versions':
        arguments.requireOnlyFlags(<String>{'json', 'verbose'});
        report = await service.versions(roots);
      case 'check':
        arguments.requireOnlyFlags(<String>{'json', 'verbose'});
        report = await service.check(roots);
      case 'policy':
        arguments.requireOnlyFlags(<String>{
          'json',
          'verbose',
          'bundle',
          'sha256',
        });
        final bundle = arguments.options['bundle'];
        final digest = arguments.options['sha256'];
        if (bundle == null || digest == null) {
          throw const _UsageException(
            'fleet policy requires --bundle=PATH and --sha256=DIGEST.',
          );
        }
        report = await service.policy(
          roots,
          bundlePath: bundle,
          expectedSha256: digest,
        );
      case 'upgrade':
        arguments.requireOnlyFlags(<String>{
          'json',
          'verbose',
          'dry-run',
          'to',
        });
        if (!arguments.flags.contains('dry-run') ||
            arguments.options['to'] == null) {
          throw const _UsageException(
            'fleet upgrade requires --dry-run and --to=1.0.0-rc.N.',
          );
        }
        report = await service.previewUpgrade(
          roots,
          targetCohort: arguments.options['to']!,
        );
      default:
        throw _UsageException('Unknown fleet command "$command".');
    }
    if (arguments.flags.contains('json')) {
      _stdout.writeln(jsonEncode(report.toJson()));
    } else {
      _stdout.writeln(
        '${report.command}: ${report.exitCode == 0 ? 'healthy' : 'findings'}',
      );
      for (final project in report.projects) {
        _stdout.writeln('${project['root']}: ${_fleetProjectSummary(project)}');
      }
      if (command == 'upgrade') {
        _stdout.writeln('DRY-RUN no files written.');
      }
    }
    return report.exitCode;
  }

  static String _fleetProjectSummary(Map<String, Object?> project) {
    if (project['plan'] case final Map<String, Object?> plan) {
      return (plan['operations']! as List<Object?>).join(', ');
    }
    if (project['dependencies'] case final List<Object?> dependencies) {
      return '${dependencies.length} Dartitect dependencies';
    }
    if (project['diagnostics'] case final List<Object?> diagnostics) {
      return diagnostics.isEmpty
          ? 'policy healthy'
          : '${diagnostics.length} policy findings';
    }
    final findings = (project['findings'] as List<Object?>?)?.length ?? 0;
    final violations = (project['violations'] as List<Object?>?)?.length ?? 0;
    return findings + violations == 0
        ? 'architecture healthy'
        : '${findings + violations} architecture findings';
  }

  static List<String> _parseAdapters(String? value) {
    if (value == null || value.trim().isEmpty) return <String>[];
    return value
        .split(',')
        .map((adapter) => adapter.trim())
        .where((adapter) => adapter.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  void _writeEnvelope(CommandEnvelope envelope, {required bool json}) {
    if (json) {
      _stdout.writeln(jsonEncode(envelope.toJson()));
      return;
    }
    _stdout.writeln(
      '${envelope.command}: ${envelope.exitCode == 0 ? 'healthy' : 'findings'}',
    );
    for (final finding in <DartitectFinding>[
      ...envelope.findings,
      ...envelope.violations,
    ]) {
      final location = finding.path == null
          ? ''
          : ' ${finding.path}${finding.line == null ? '' : ':${finding.line}'}';
      _stdout.writeln(
        '${finding.severity.name.toUpperCase()} ${finding.code}$location '
        '${finding.message}',
      );
      if (finding.remediation != null) {
        _stdout.writeln('  ${finding.remediation}');
      }
    }
  }

  void _writeGeneration(GenerationResult result) {
    for (final operation in result.plan.operations) {
      _stdout.writeln(
        '${operation.disposition.name.toUpperCase()} '
        '${operation.operation.relativePath}',
      );
    }
    if (result.dryRun) _stdout.writeln('DRY-RUN no files written.');
  }

  int _usageError(String message) {
    _stderr.writeln(message);
    _stderr.writeln('Run `dartitect --help` for usage.');
    return DartitectExitCode.usage.code;
  }

  String _absolute(String path) {
    if (path.startsWith(Platform.pathSeparator) ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return path;
    }
    return _join(_currentDirectory.path, path);
  }

  Directory? _findLocalSdkRoot() {
    var candidate = _currentDirectory;
    while (true) {
      final core = File(
        _join(candidate.path, 'packages/dartitect/pubspec.yaml'),
      );
      final flutter = File(
        _join(candidate.path, 'packages/dartitect_flutter/pubspec.yaml'),
      );
      if (core.existsSync() && flutter.existsSync()) return candidate;
      final parent = candidate.parent;
      if (parent.path == candidate.path) return null;
      candidate = parent;
    }
  }

  static List<String> _localSdkPackageClosure(Iterable<String> packages) {
    final closure = <String>{...packages};
    if (closure.contains('dartitect_flutter') ||
        closure.contains('dartitect_dio') ||
        closure.contains('dartitect_drift') ||
        closure.contains('dartitect_objectbox')) {
      closure
        ..add('dartitect')
        ..add('dartitect_observability');
    }
    if (closure.contains('dartitect_sentry')) {
      closure.add('dartitect_observability');
    }
    if (closure.contains('dartitect_observability') ||
        closure.contains('dartitect_testing') ||
        closure.contains('dartitect_dio') ||
        closure.contains('dartitect_drift') ||
        closure.contains('dartitect_objectbox')) {
      closure
        ..add('dartitect')
        ..add('dartitect_sync');
    }
    if (closure.contains('dartitect_sync')) {
      closure.add('dartitect');
    }
    return closure.toList()..sort();
  }

  static String _yamlQuote(String value) => "'${value.replaceAll("'", "''")}'";

  static String _firstLine(String output) {
    final sanitized = output.trim().split(RegExp(r'\r?\n')).firstOrNull ?? '';
    return sanitized.length <= 300
        ? sanitized
        : '${sanitized.substring(0, 300)}…';
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

  static const _driftCompositionRootRecipe = '''# Drift composition-root recipe

`dartitect create app --adapters=drift` adds only the `dartitect_drift`
dependency and this recipe. The application owns its Drift schema, migrations,
executor, codecs, database file or web assets, and generated code.

1. Put the consumer `GeneratedDatabase`, tables, and DAOs under the feature's
   `infrastructure/` directory. Keep them out of domain, application, and
   presentation.
2. Select the executor in consumer code with conditional exports: a stub, then
   `dart.library.ffi` for native and `dart.library.js_interop` for web. Configure
   `NativeDatabase.createInBackground` or `WasmDatabase.open` there.
3. At an app, session, route, or isolate composition root, open the database
   through `DriftDatabaseOwner.create(openDatabase: ...)`. Inject repositories,
   `DriftMutationTransaction`, `DriftSyncCheckpointStore`, and
   `DriftSyncRunJournal`; do not expose Drift types through feature contracts.
4. Adapt a consumer `Selectable.watch()` stream through Dartitect's existing
   `StreamReactiveSource`. Dispose observations, sync, and repositories before
   the database owner.

When Drift and ObjectBox coexist, assign different bounded contexts and a
single writer per dataset or partition. Do not dual-write, bridge schemas, or
attempt a transaction across engines.
''';

  static const _help = '''Dartitect ${CommandEnvelope.sdkVersion}

Usage: dartitect <command> [arguments]

Read-only commands:
  scan [--json|--sarif] [--root PATH]
                                    Scan files and architecture boundaries.
  baseline create [--dry-run]      Record existing violations by fingerprint.
  codex sync [--dry-run] [--overwrite-managed]
                                    Install managed, focused Codex skills.
  doctor [--json] [--deep]         Validate toolchain, config, and project.
  inspect [--json]                  Emit consolidated architecture metadata.
  model check [--json]              Validate generated model freshness.
  dependencies audit [--json]      Audit direct/transitive packages offline.
  dependencies explain <package>   Explain the ledger decision/replacement.
  fleet versions <root...>         Report declared and locked SDK versions.
  fleet check <root...>            Scan explicit fleet roots without writes.
  fleet policy <root...> --bundle=PATH --sha256=DIGEST
                                    Audit with a pinned local policy bundle.
  fleet upgrade <root...> --dry-run --to=1.0.0-rc.N
                                    Preview revalidatable cohort upgrades only.

Convergent synchronizers (preview by default):
  model sync [--dry-run|--apply] [--json]
                                    Preview or converge generated models.

Mutating commands (all accept --dry-run):
  init                              Create dartitect.json without overwrite.
  create app <name> [--observability=MODE] [--adapters=a,b] [--blueprint=NAME]
                                    Create a six-platform Flutter app.
  create feature <name> [--domain] Create a feature-first vertical slice.
  create simple <name>             Create an immutable MVVM slice.
  create remote-read <name>        Add a typed remote port and mapper.
  create local-first <name>        Add local authority and pull reactivity.
  create offline-mutation <name>   Add an outbox-backed mutation lane.
  create sync-dataset <name>       Add dataset/checkpoint sync contracts.
  create viewmodel <name>           Create a native ViewModel and test.
  create repository <name>          Create a contract and fake.
  create service <name>             Create a constructor-injected service.
Exit codes: 0 success, 1 findings/conflicts, 2 usage/config, 3 internal/IO.''';
}

final class _CliArguments {
  _CliArguments(List<String> arguments) {
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument == '--root') {
        if (index + 1 >= arguments.length) {
          throw const _UsageException('--root requires a path.');
        }
        root = arguments[index + 1];
        index += 1;
      } else if (argument.startsWith('--root=')) {
        root = argument.substring('--root='.length);
      } else if (argument.startsWith('--') && argument.contains('=')) {
        final separator = argument.indexOf('=');
        final key = argument.substring(2, separator);
        final value = argument.substring(separator + 1);
        if (key.isEmpty || value.isEmpty) {
          throw _UsageException('Invalid option: $argument');
        }
        options[key] = value;
        flags.add(key);
      } else if (argument.startsWith('--')) {
        flags.add(argument.substring(2));
      } else {
        positionals.add(argument);
      }
    }
  }

  String? root;
  final Set<String> flags = <String>{};
  final Map<String, String> options = <String, String>{};
  final List<String> positionals = <String>[];

  void requireNoPositionals() {
    if (positionals.isNotEmpty) {
      throw _UsageException('Unexpected argument: ${positionals.first}');
    }
  }

  void requireOnlyFlags(Set<String> allowed) {
    final unknown = flags.difference(allowed);
    if (unknown.isNotEmpty) {
      throw _UsageException('Unknown flag: --${unknown.first}');
    }
  }
}

final class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}

extension<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : null;

  T? get firstOrNull => isEmpty ? null : first;
}
