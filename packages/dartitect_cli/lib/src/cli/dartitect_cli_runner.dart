import 'dart:convert';
import 'dart:io';

import 'package:dartitect/dartitect.dart' show FeatureProfile;

import '../config/dartitect_config.dart';
import '../diagnostics/models.dart';
import '../diagnostics/sarif.dart';
import '../fleet/fleet_service.dart';
import '../generation/generation_engine.dart';
import '../generation/scaffolds.dart';
import '../generation/wiring_service.dart';
import '../model/model_generator.dart';
import '../model/primary_constructor_migration.dart';
import '../policy/ecosystem_policy.dart';
import '../project/dartitect_project_service.dart';
import '../scan/project_scanner.dart';
import '../verification/verification_service.dart';

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
       _currentDirectory = Directory(
         (currentDirectory ?? Directory.current).resolveSymbolicLinksSync(),
       );

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
          : Directory(
              Directory(_absolute(parsed.root!)).resolveSymbolicLinksSync(),
            );
      return switch (command) {
        'scan' => await _readOnly('scan', root, parsed),
        'doctor' => await _readOnly('doctor', root, parsed),
        'inspect' => await _readOnly('inspect', root, parsed),
        'verify' => await _readOnly('verify', root, parsed),
        'init' => await _init(root, parsed),
        'create' => await _create(root, parsed),
        'baseline' => await _baseline(root, parsed),
        'codex' => await _codex(root, parsed),
        'model' => await _model(root, parsed),
        'wiring' => await _wiring(root, parsed),
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
    } on PrimaryConstructorMigrationException catch (error) {
      _stderr.writeln(error.message);
      return DartitectExitCode.internal.code;
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
      if (command == 'scan' || command == 'verify') 'sarif',
      'deep',
      if (command == 'doctor') 'release',
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
        release: arguments.flags.contains('release'),
      ),
      'verify' => await DartitectVerificationService(root).verify(),
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
        'Usage: dartitect create <app|feature|viewmodel|repository|service> <name>.',
      );
    }
    final kind = arguments.positionals[0];
    final name = arguments.positionals[1];
    if (arguments.positionals.length > 2) {
      throw _UsageException('Unexpected argument: ${arguments.positionals[2]}');
    }
    arguments.requireOnlyFlags(<String>{
      'dry-run',
      'verbose',
      'targets',
      'example',
      'profile',
      'scope',
      'storage-context',
      'transport',
      'pagination',
      'headless-targets',
      'diagnostics',
      'capabilities',
    });
    if (kind == 'app') {
      _rejectFeatureOptions(arguments);
      return _createApp(
        root,
        name,
        dryRun: arguments.flags.contains('dry-run'),
        targets: _parsePlatformsOption(
          arguments.options['targets'],
          option: '--targets',
          required: true,
        ),
        example: arguments.options['example'],
      );
    }
    if (arguments.options['example'] != null) {
      throw const _UsageException('--example is valid only for create app.');
    }

    final scan = await ProjectScanner(root).scan();
    final scaffold = ScaffoldFactory(
      packageName: scan.packageName ?? 'application',
    );
    final profileName = arguments.options['profile'];
    final hasFeatureOptions =
        profileName != null ||
        arguments.options['scope'] != null ||
        arguments.options['storage-context'] != null ||
        arguments.options['transport'] != null ||
        arguments.options['targets'] != null ||
        arguments.options['pagination'] != null ||
        arguments.options['diagnostics'] != null ||
        arguments.options['capabilities'] != null ||
        arguments.options['headless-targets'] != null;
    if (kind != 'feature' && hasFeatureOptions) {
      throw const _UsageException(
        'Feature profile options are valid only for create feature.',
      );
    }
    if (kind == 'feature' && profileName == null) {
      throw const _UsageException('--profile is required for create feature.');
    }
    final pagination = arguments.options['pagination'] ?? 'none';
    if (!const <String>{'none', 'cursor'}.contains(pagination)) {
      throw _UsageException('Unsupported pagination mode "$pagination".');
    }
    final featureOptions = kind == 'feature'
        ? FeatureScaffoldOptions(
            profile: FeatureProfile.parse(profileName!),
            scope: FeatureScope.parse(
              arguments.options['scope'] ?? 'application',
            ),
            storageContext: arguments.options['storage-context'],
            transport: arguments.options['transport'],
            targets: _parsePlatformsOption(arguments.options['targets']),
            pagination: FeaturePagination.parse(pagination),
            headlessTargets: _parsePlatformsOption(
              arguments.options['headless-targets'],
            ),
            diagnostics: FeatureDiagnosticsLevel.parse(
              arguments.options['diagnostics'] ?? 'basic',
            ),
            capabilities: _parseCapabilities(arguments.options['capabilities']),
          )
        : null;
    final operations = switch (kind) {
      'feature' => scaffold.profile(featureOptions!, name),
      'viewmodel' => scaffold.viewModel(name),
      'repository' => scaffold.repository(name),
      'service' => scaffold.service(name),
      _ => throw _UsageException('Unknown create target "$kind".'),
    };
    if (featureOptions != null) {
      return _createFeature(
        root,
        name,
        featureOptions,
        operations,
        dryRun: arguments.flags.contains('dry-run'),
      );
    }
    final result = await GenerationEngine(
      root,
      namespace: GenerationNamespace.scaffolding,
    ).apply(operations, dryRun: arguments.flags.contains('dry-run'));
    _writeGeneration(result);
    return DartitectExitCode.success.code;
  }

  Future<int> _createFeature(
    Directory root,
    String input,
    FeatureScaffoldOptions options,
    List<FileGenerationOperation> seams, {
    required bool dryRun,
  }) async {
    final name = ScaffoldName(input);
    final configFile = File(_join(root.path, 'dartitect.json'));
    final priorSource = await configFile.exists()
        ? await configFile.readAsString()
        : null;
    final prior = priorSource == null
        ? DartitectConfig()
        : DartitectConfig.parse(priorSource);
    final declaration = DartitectFeatureDeclaration(
      profile: options.profile,
      scope: options.scope,
      storageContext: options.storageContext,
      dataset: options.storageContext == null
          ? null
          : options.dataset ??
                DartitectStorageDatasetConfig.forFeature(name.snake),
      transport: options.transport,
      targets: options.targets,
      pagination: options.pagination,
      diagnostics: options.diagnostics,
      headlessTargets: options.headlessTargets,
      capabilities: options.capabilities,
    );
    final existing = prior.features.declarations[name.snake];
    if (existing != null &&
        jsonEncode(existing.toJson()) != jsonEncode(declaration.toJson())) {
      throw DartitectConfigException(
        '/features/declarations/${name.snake}',
        'feature already exists with a different declaration',
      );
    }
    final declarations = <String, DartitectFeatureDeclaration>{
      ...prior.features.declarations,
      name.snake: declaration,
    };
    final next = DartitectConfig(
      configVersion: prior.configVersion,
      profile: prior.profile,
      layers: prior.layers,
      compositionRoots: prior.compositionRoots,
      generatedInfrastructure: prior.generatedInfrastructure,
      generatedSuffixes: prior.generatedSuffixes,
      suppressions: prior.suppressions,
      modeling: prior.modeling,
      features: DartitectFeaturesConfig(declarations: declarations),
      targets: prior.targets,
      storageContexts: prior.storageContexts,
      transports: prior.transports,
      observability: prior.observability,
      scheduler: prior.scheduler,
      extensionSources: prior.extensionSources,
    );
    final seamEngine = GenerationEngine(
      root,
      namespace: GenerationNamespace.scaffolding,
    );
    final seamPreview = await seamEngine.plan(seams);
    if (seamPreview.hasConflicts) {
      throw GenerationException(
        'Consumer-owned feature seams conflict with existing files.',
      );
    }
    final wiring = DartitectWiringService(root);
    final wiringPreview = await wiring.inspect(config: next);
    if (wiringPreview.plan.hasConflicts) {
      throw GenerationException(
        'Managed feature wiring conflicts with consumer bytes.',
      );
    }
    if (dryRun) {
      _stdout.writeln('UPDATE dartitect.json');
      _writeGeneration(
        GenerationResult(
          plan: seamPreview,
          dryRun: true,
          createdPaths: const <String>[],
        ),
      );
      for (final operation in wiringPreview.plan.operations) {
        _stdout.writeln(
          '${operation.disposition.name.toUpperCase()} '
          '${operation.operation.relativePath}',
        );
      }
      return DartitectExitCode.success.code;
    }

    GenerationResult? seamResult;
    try {
      seamResult = await seamEngine.apply(seams);
      await _replaceConfig(configFile, next.encode());
      final wiringResult = await wiring.apply(config: next);
      _writeGeneration(seamResult);
      for (final operation in wiringResult.plan.operations) {
        _stdout.writeln(
          '${operation.disposition.name.toUpperCase()} '
          '${operation.operation.relativePath}',
        );
      }
      return DartitectExitCode.success.code;
    } catch (_) {
      if (priorSource == null) {
        if (await configFile.exists()) await configFile.delete();
      } else {
        await _replaceConfig(configFile, priorSource);
      }
      for (final path
          in seamResult?.createdPaths.reversed ?? const <String>[]) {
        final created = File(_join(root.path, path));
        if (await created.exists()) await created.delete();
      }
      rethrow;
    }
  }

  static Future<void> _replaceConfig(File target, String source) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.dartitect.tmp');
    final backup = File('${target.path}.dartitect.bak');
    await temporary.writeAsString(source, flush: true);
    final hadTarget = await target.exists();
    if (hadTarget) await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  }

  Future<int> _createApp(
    Directory parent,
    String input, {
    required bool dryRun,
    required Set<DartitectPlatform> targets,
    required String? example,
  }) async {
    if (example != null && example != 'tasks') {
      throw _UsageException('Unsupported example "$example".');
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
      _stdout.writeln(
        'TARGETS ${targets.map((target) => target.wireName).join(',')}',
      );
      if (example != null) _stdout.writeln('EXAMPLE $example');
      return DartitectExitCode.success.code;
    }

    await parent.create(recursive: true);
    final localSdk = _findLocalSdkRoot();
    final workspaceMember =
        localSdk != null &&
        _isWithinDirectory(parent.absolute.path, localSdk.absolute.path);
    final temporary = await parent.createTemp('.${name.snake}.dartitect-app-');
    var moved = false;
    try {
      final result = await Process.run('flutter', <String>[
        'create',
        '--project-name',
        name.snake,
        '--platforms',
        targets.map((target) => target.wireName).join(','),
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
        targets: targets,
        example: example,
        workspaceMember: workspaceMember,
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
    required Set<DartitectPlatform> targets,
    required String? example,
    required bool workspaceMember,
  }) async {
    final pubspec = File(_join(project.path, 'pubspec.yaml'));
    var source = await pubspec.readAsString();
    final localSdk = _findLocalSdkRoot();
    final sdkPackages = <String>{'dartitect', 'dartitect_flutter'}.toList()
      ..sort();
    final localOverridePackages = _localSdkPackageClosure(sdkPackages);
    final dependencyBlock = localSdk == null || workspaceMember
        ? sdkPackages.map((package) => '  $package: ^1.0.0-rc.6\n').join()
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
    if (workspaceMember) {
      source = source.replaceFirst(
        'environment:\n',
        'resolution: workspace\n\nenvironment:\n',
      );
    } else if (localSdk != null) {
      source =
          '$source\ndependency_overrides:\n${localOverridePackages.map((package) => '  $package:\n'
              '    path: ${_yamlQuote(_join(localSdk.path, 'packages/$package'))}\n').join()}';
    }
    await pubspec.writeAsString(source, flush: true);

    final widgetTest = File(_join(project.path, 'test/widget_test.dart'));
    if (await widgetTest.exists()) await widgetTest.delete();
    final mainFile = File(_join(project.path, 'lib/main.dart'));
    await mainFile.writeAsString(
      '''${example == 'tasks' ? "import 'package:dartitect/dartitect.dart';\n" : ''}import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import 'composition/application_module.wiring.dartitect.g.dart';
${example == 'tasks' ? "import 'features/tasks/domain/tasks_repository.dart';\nimport 'features/tasks/presentation/tasks_view.dart';" : ''}

void main() => runDartitectApplication<ApplicationGraph<Never, Never>>(
  create: ApplicationModule.create<Never, Never>,
  application: (_) => const MaterialApp(
    title: '${name.pascal}',
    home: ${example == 'tasks' ? 'TasksPage(repository: _ExampleTasksRepository())' : 'SizedBox.shrink()'},
  ),
);
${example == 'tasks' ? '''
final class _ExampleTasksRepository implements TasksRepository {
  const _ExampleTasksRepository();

  @override
  Future<Result<List<String>, TasksFailure>> load() async =>
      const Ok<List<String>>(<String>['Example task']);
}
''' : ''}
''',
      flush: true,
    );

    final scaffold = ScaffoldFactory(packageName: name.snake);
    final featureOptions = FeatureScaffoldOptions(
      profile: FeatureProfile.local,
      scope: FeatureScope.application,
    );
    final declarations = example == 'tasks'
        ? <String, DartitectFeatureDeclaration>{
            'tasks': DartitectFeatureDeclaration(
              profile: FeatureProfile.local,
              scope: FeatureScope.application,
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.basic,
            ),
          }
        : const <String, DartitectFeatureDeclaration>{};
    await GenerationEngine(
      project,
      namespace: GenerationNamespace.scaffolding,
    ).apply(<FileGenerationOperation>[
      ...scaffold.init(
        config: DartitectConfig(
          targets: DartitectTargetsConfig(targets),
          features: DartitectFeaturesConfig(declarations: declarations),
        ),
      ),
      ...scaffold.agents(),
      if (example == 'tasks') ...scaffold.profile(featureOptions, 'tasks'),
    ]);
    final format = await Process.run('dart', <String>[
      'format',
      'lib',
      'test',
    ], workingDirectory: project.path);
    if (format.exitCode != 0) {
      throw GenerationException('Generated app formatting failed.');
    }
    await DartitectWiringService(project).apply();
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
    if (arguments.positionals.length == 2 &&
        arguments.positionals[0] == 'migrate' &&
        arguments.positionals[1] == 'primary') {
      return _modelMigratePrimary(root, arguments);
    }
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

  Future<int> _wiring(Directory root, _CliArguments arguments) async {
    if (arguments.positionals.length != 1 ||
        arguments.positionals.single != 'sync') {
      throw const _UsageException(
        'Usage: dartitect wiring sync [--dry-run|--apply] [--json].',
      );
    }
    arguments.requireOnlyFlags(<String>{'json', 'verbose', 'dry-run', 'apply'});
    if (arguments.flags.contains('dry-run') &&
        arguments.flags.contains('apply')) {
      throw const _UsageException(
        '--dry-run and --apply are mutually exclusive.',
      );
    }
    final service = DartitectWiringService(root);
    final report = arguments.flags.contains('apply')
        ? await service.apply()
        : await service.inspect();
    if (arguments.flags.contains('json')) {
      _stdout.writeln(jsonEncode(report.toJson()));
    } else {
      for (final operation in report.plan.operations) {
        _stdout.writeln(
          '${operation.disposition.name.toUpperCase()} '
          '${operation.operation.relativePath}',
        );
      }
      if (report.applied) {
        _stdout.writeln('APPLIED ${report.writes} managed write(s).');
      } else {
        _stdout.writeln(
          'PREVIEW no files written. Use --apply to synchronize.',
        );
      }
    }
    return report.isFresh
        ? DartitectExitCode.success.code
        : DartitectExitCode.findings.code;
  }

  Future<int> _modelMigratePrimary(
    Directory root,
    _CliArguments arguments,
  ) async {
    arguments.requireOnlyFlags(<String>{'json', 'verbose', 'dry-run', 'apply'});
    if (arguments.flags.contains('dry-run') &&
        arguments.flags.contains('apply')) {
      throw const _UsageException(
        '--dry-run and --apply are mutually exclusive.',
      );
    }
    final migration = PrimaryConstructorMigration(root);
    final preview = await migration.inspect();
    if (!arguments.flags.contains('apply') || preview.diagnostics.isNotEmpty) {
      _writePrimaryMigrationReport(
        preview,
        json: arguments.flags.contains('json'),
      );
      return preview.diagnostics.isEmpty &&
              preview.operations.isEmpty &&
              !preview.pendingRecovery
          ? DartitectExitCode.success.code
          : DartitectExitCode.findings.code;
    }
    final applied = await migration.apply();
    _writePrimaryMigrationReport(
      applied,
      json: arguments.flags.contains('json'),
    );
    return DartitectExitCode.success.code;
  }

  void _writePrimaryMigrationReport(
    PrimaryConstructorMigrationReport report, {
    required bool json,
  }) {
    if (json) {
      _stdout.writeln(jsonEncode(report.toJson()));
      return;
    }
    for (final diagnostic in report.diagnostics) {
      final line = diagnostic.line == null ? '' : ':${diagnostic.line}';
      _stdout.writeln(
        '${diagnostic.rule} ${diagnostic.path}$line ${diagnostic.message}',
      );
    }
    for (final operation in report.operations) {
      _stdout.writeln('MIGRATE ${operation.path} (${operation.modelCount})');
    }
    if (report.pendingRecovery) {
      _stdout.writeln(
        'RECOVERY .dartitect/generation/model-primary-migration/source-journal.json',
      );
    }
    if (report.applied) {
      _stdout.writeln('APPLIED ${report.modelCount} model(s).');
    } else {
      _stdout.writeln(
        'PREVIEW no files written. Use --apply to migrate primary '
        'constructors.',
      );
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
        'Usage: dartitect fleet <report|versions|check|policy|upgrade> '
        '<project-root...>.',
      );
    }
    final command = arguments.positionals.first;
    final roots = arguments.positionals.skip(1).toList();
    final service = DartitectFleetService(root);
    late final DartitectFleetReport report;
    switch (command) {
      case 'report':
        arguments.requireOnlyFlags(<String>{'json', 'verbose'});
        report = await service.report(roots);
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
          'apply',
          'to',
        });
        if (arguments.flags.contains('dry-run') &&
            arguments.flags.contains('apply')) {
          throw const _UsageException(
            '--dry-run and --apply are mutually exclusive.',
          );
        }
        if (arguments.options['to'] == null) {
          throw const _UsageException(
            'fleet upgrade requires --to=1.0.0-rc.6.',
          );
        }
        report = arguments.flags.contains('apply')
            ? await service.applyUpgrade(
                roots,
                targetCohort: arguments.options['to']!,
              )
            : await service.previewUpgrade(
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
        _stdout.writeln(
          arguments.flags.contains('apply')
              ? 'COMMITTED all fleet projects.'
              : 'DRY-RUN no files written.',
        );
      }
    }
    return report.exitCode;
  }

  static String _fleetProjectSummary(Map<String, Object?> project) {
    if (project['plan'] case final Map<String, Object?> plan) {
      return (plan['operations']! as List<Object?>).join(', ');
    }
    if (project['dependencies'] case final List<Object?> dependencies) {
      final profiles = project['profiles'] as List<Object?>?;
      return profiles == null
          ? '${dependencies.length} Dartitect dependencies'
          : '${dependencies.length} Dartitect dependencies, '
                '${profiles.length} profiles';
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

  static Set<DartitectCapability> _parseCapabilities(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const <DartitectCapability>{};
    }
    return value
        .split(',')
        .map((capability) => capability.trim())
        .where((capability) => capability.isNotEmpty)
        .map(DartitectCapability.parse)
        .toSet();
  }

  static Set<DartitectPlatform> _parsePlatformsOption(
    String? value, {
    String option = '--targets',
    bool required = false,
  }) {
    if (value == null || value.trim().isEmpty) {
      if (required) throw _UsageException('$option is required.');
      return const <DartitectPlatform>{};
    }
    return value
        .split(',')
        .map((target) => target.trim())
        .where((target) => target.isNotEmpty)
        .map(DartitectPlatform.parse)
        .toSet();
  }

  static void _rejectFeatureOptions(_CliArguments arguments) {
    const optionNames = <String>{
      'profile',
      'scope',
      'storage-context',
      'transport',
      'pagination',
      'headless-targets',
      'diagnostics',
      'capabilities',
    };
    final used = arguments.flags.intersection(optionNames);
    if (used.isNotEmpty) {
      throw _UsageException(
        '--${used.first} is valid only for create feature.',
      );
    }
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

  static bool _isWithinDirectory(String candidate, String parent) {
    final normalizedCandidate = candidate.endsWith(Platform.pathSeparator)
        ? candidate.substring(0, candidate.length - 1)
        : candidate;
    final normalizedParent = parent.endsWith(Platform.pathSeparator)
        ? parent.substring(0, parent.length - 1)
        : parent;
    return normalizedCandidate == normalizedParent ||
        normalizedCandidate.startsWith(
          '$normalizedParent${Platform.pathSeparator}',
        );
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
    const dependencies = <String, Set<String>>{
      'dartitect_flutter': {'dartitect'},
      'dartitect_observability': {'dartitect'},
      'dartitect_jobs': {'dartitect'},
      'dartitect_resilience': {'dartitect'},
      'dartitect_transfer': {'dartitect'},
      'dartitect_sync': {'dartitect', 'dartitect_jobs', 'dartitect_resilience'},
      'dartitect_dio': {
        'dartitect',
        'dartitect_observability',
        'dartitect_transfer',
      },
      'dartitect_drift': {
        'dartitect',
        'dartitect_observability',
        'dartitect_sync',
      },
      'dartitect_objectbox': {
        'dartitect',
        'dartitect_flutter',
        'dartitect_observability',
        'dartitect_sync',
      },
      'dartitect_sentry': {'dartitect_observability'},
      'dartitect_workmanager': {'dartitect', 'dartitect_jobs'},
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final package in closure.toList(growable: false)) {
        for (final dependency in dependencies[package] ?? const <String>{}) {
          changed = closure.add(dependency) || changed;
        }
      }
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

  static const _help = '''Dartitect ${CommandEnvelope.sdkVersion}

Usage: dartitect <command> [arguments]

Read-only commands:
  scan [--json|--sarif] [--root PATH]
                                    Scan files and architecture boundaries.
  baseline create [--dry-run]      Record existing violations by fingerprint.
  codex sync [--dry-run] [--overwrite-managed]
                                    Install managed, focused Codex skills.
  doctor [--json] [--deep] [--release]
                                    Validate toolchain, config, and project.
  inspect [--json]                  Emit consolidated architecture metadata.
  verify [--json|--sarif]           Verify architecture, models, and providers.
  model check [--json]              Validate generated model freshness.
  model migrate primary [--dry-run|--apply] [--json]
                                    Preview or apply semantic constructor edits.
  dependencies audit [--json]      Audit direct/transitive packages offline.
  dependencies explain <package>   Explain the ledger decision/replacement.
  fleet versions <root...>         Report declared and locked SDK versions.
  fleet check <root...>            Scan explicit fleet roots without writes.
  fleet policy <root...> --bundle=PATH --sha256=DIGEST
                                    Audit with a pinned local policy bundle.
  fleet upgrade <root...> --to=1.0.0-rc.6 --apply [--json]
                                    Upgrade a cohort transactionally.

Convergent synchronizers (preview by default):
  model sync [--dry-run|--apply] [--json]
                                    Preview or converge generated models.
  wiring sync [--dry-run|--apply] [--json]
                                    Preview or converge direct feature wiring.

Mutating commands (all accept --dry-run):
  init                              Create dartitect.json without overwrite.
  create app <name> --targets=android,web [--example=tasks]
                                    Create an empty target-aware Flutter shell.
  create feature <name> --profile=PROFILE [--scope=application|session]
                       [--targets=android,web]
                       [--storage-context=NAME] [--transport=NAME]
                       [--pagination=cursor]
                       [--headless-targets=android,ios]
                       [--diagnostics=off|basic|full]
                       [--capabilities=credentials,attachments,forms,queries]
                                    Create local/online/cache/replica/offline-full wiring.
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
