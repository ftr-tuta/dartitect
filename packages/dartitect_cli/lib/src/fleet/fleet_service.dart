import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../config/dartitect_config.dart';
import '../generation/generation_engine.dart';
import '../generation/wiring_service.dart';
import '../model/model_generator.dart';
import '../model/primary_constructor_migration.dart';
import '../policy/ecosystem_policy.dart';
import '../project/dartitect_project_service.dart';
import '../verification/verification_service.dart';
import 'rc5_config_migration.dart';

/// Result from one closed, allowlisted fleet validation command.
final class DartitectFleetCommandResult {
  /// Creates a sanitized process result.
  const DartitectFleetCommandResult({required this.exitCode, this.output = ''});

  /// Process exit status.
  final int exitCode;

  /// Bounded output sanitized before it enters receipts.
  final String output;
}

/// Injectable boundary for the fleet's closed pub/analyze/test allowlist.
typedef DartitectFleetCommandRunner =
    Future<DartitectFleetCommandResult> Function(
      Directory root,
      String executable,
      List<String> arguments,
    );

/// One deterministic, path-sanitized result from a fleet operation.
final class DartitectFleetReport {
  /// Creates a fleet report.
  const DartitectFleetReport({
    required this.command,
    required this.projects,
    required this.exitCode,
    this.policyBundle,
  });

  /// Fleet report schema, versioned independently from package releases.
  static const int schemaVersion = 1;

  /// Read-only fleet command name.
  final String command;

  /// Results sorted by fleet-relative project root.
  final List<Map<String, Object?>> projects;

  /// Stable CLI exit code: zero when every project passed.
  final int exitCode;

  /// Verified local policy-bundle identity, when applicable.
  final Map<String, Object?>? policyBundle;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'command': command,
    if (policyBundle != null) 'policyBundle': policyBundle,
    'projects': projects,
    'exitCode': exitCode,
  };
}

/// Read-only, offline operations across explicitly selected project roots.
final class DartitectFleetService {
  /// Creates a fleet service rooted at the caller's explicit workspace.
  DartitectFleetService(
    Directory fleetRoot, {
    DartitectFleetCommandRunner? commandRunner,
  }) : fleetRoot = fleetRoot.absolute,
       _commandRunner = commandRunner ?? _runFleetCommand;

  /// Boundary within which all projects and policy files must resolve.
  final Directory fleetRoot;

  final DartitectFleetCommandRunner _commandRunner;

  /// Reports declared and locked Dartitect versions without running pub.
  Future<DartitectFleetReport> versions(Iterable<String> roots) async {
    final projects = await _projects(roots);
    final results = <Map<String, Object?>>[];
    for (final project in projects) {
      final pubspec = File(_join(project.directory.path, 'pubspec.yaml'));
      final source = await pubspec.readAsString();
      final dependencies = _declaredDartitectDependencies(source);
      final locked = await _lockedVersions(project.directory);
      final adoption = await _versionAdoptionStatus(project.directory, source);
      results.add(<String, Object?>{
        'root': project.label,
        if (_packageName(source) case final name?) 'name': name,
        'dependencies': <Object?>[
          for (final dependency in dependencies)
            <String, Object?>{
              ...dependency,
              if (locked[dependency['package']] case final version?)
                'lockedVersion': version,
            },
        ],
        ...adoption,
      });
    }
    return DartitectFleetReport(
      command: 'fleet versions',
      projects: List<Map<String, Object?>>.unmodifiable(results),
      exitCode: 0,
    );
  }

  /// Aggregates versions, paved-road profiles, providers, and matrix coverage.
  ///
  /// This report reads project declarations and test source only. It does not
  /// resolve packages, execute processes, or write to a project.
  Future<DartitectFleetReport> report(Iterable<String> roots) async {
    final projects = await _projects(roots);
    final results = <Map<String, Object?>>[];
    for (final project in projects) {
      final pubspec = File(_join(project.directory.path, 'pubspec.yaml'));
      final source = await pubspec.readAsString();
      final dependencies = _declaredDartitectDependencies(source);
      final locked = await _lockedVersions(project.directory);
      final adoption = await _versionAdoptionStatus(project.directory, source);
      final featureStatus = await _featureStatus(project.directory);
      results.add(<String, Object?>{
        'root': project.label,
        if (_packageName(source) case final name?) 'name': name,
        'dependencies': <Object?>[
          for (final dependency in dependencies)
            <String, Object?>{
              ...dependency,
              if (locked[dependency['package']] case final version?)
                'lockedVersion': version,
            },
        ],
        ...adoption,
        ...featureStatus,
      });
    }
    return DartitectFleetReport(
      command: 'fleet report',
      projects: List<Map<String, Object?>>.unmodifiable(results),
      exitCode: 0,
    );
  }

  /// Runs architecture checks over explicit roots without baselines or writes.
  Future<DartitectFleetReport> check(Iterable<String> roots) async {
    final projects = await _projects(roots);
    final results = <Map<String, Object?>>[];
    var exitCode = 0;
    for (final project in projects) {
      final report = await DartitectVerificationService(project.directory)
          .verify();
      if (report.exitCode != 0) exitCode = 1;
      results.add(<String, Object?>{
        'root': project.label,
        if (report.project['name'] case final Object name) 'name': name,
        'capabilities': report.capabilities,
        'modelStatus': report.project['modelStatus'],
        'providerStatus': report.project['providerStatus'],
        'architectureProfile': report.project['architectureProfile'],
        'findings': <Object?>[
          for (final finding in report.findings) finding.toJson(),
        ],
        'violations': <Object?>[
          for (final finding in report.violations) finding.toJson(),
        ],
        'exitCode': report.exitCode,
      });
    }
    return DartitectFleetReport(
      command: 'fleet check',
      projects: List<Map<String, Object?>>.unmodifiable(results),
      exitCode: exitCode,
    );
  }

  /// Audits roots against an explicit local policy bundle and pinned digest.
  Future<DartitectFleetReport> policy(
    Iterable<String> roots, {
    required String bundlePath,
    required String expectedSha256,
  }) async {
    final projects = await _projects(roots);
    final bundle = await _loadPolicyBundle(bundlePath, expectedSha256);
    final results = <Map<String, Object?>>[];
    var exitCode = 0;
    for (final project in projects) {
      final report = await EcosystemDependencyAuditor(
        project.directory,
        bundle.policy,
        blockUnreviewed: bundle.blockUnreviewed,
      ).audit();
      if (!report.isClean) exitCode = 1;
      results.add(<String, Object?>{'root': project.label, ...report.toJson()});
    }
    return DartitectFleetReport(
      command: 'fleet policy',
      policyBundle: <String, Object?>{
        'bundleVersion': bundle.version,
        'sha256': expectedSha256,
        'policySha256': bundle.policySha256,
        'blockUnreviewed': bundle.blockUnreviewed,
      },
      projects: List<Map<String, Object?>>.unmodifiable(results),
      exitCode: exitCode,
    );
  }

  /// Produces revalidatable upgrade plans; this method never writes files.
  Future<DartitectFleetReport> previewUpgrade(
    Iterable<String> roots, {
    required String targetCohort,
  }) async {
    final projects = await _projects(roots);
    final results = <Map<String, Object?>>[];
    for (final project in projects) {
      final plan = await _previewUpgradeProject(project, targetCohort);
      results.add(<String, Object?>{'root': project.label, 'plan': plan});
    }
    return DartitectFleetReport(
      command: 'fleet upgrade --dry-run',
      projects: List<Map<String, Object?>>.unmodifiable(results),
      exitCode: 0,
    );
  }

  /// Applies an exact RC5-to-RC6 cohort transaction and validates every root.
  Future<DartitectFleetReport> applyUpgrade(
    Iterable<String> roots, {
    required String targetCohort,
  }) async {
    if (targetCohort != '1.0.0-rc.6') {
      throw const FormatException(
        'Fleet apply supports only the exact RC5 to RC6 migration.',
      );
    }
    final projects = await _projects(roots);
    await _recoverFleetJournalIfNeeded();
    return _withFleetLocks(projects, () async {
      final previews = <String, Map<String, Object?>>{
        for (final project in projects)
          project.label: await _previewUpgradeProject(project, targetCohort),
      };
      final snapshot = await _FleetSnapshot.capture(projects);
      await _writeFleetJournal(snapshot);
      final receipts = <Map<String, Object?>>[];
      try {
        for (final project in projects) {
          final commandReceipts = await _applyUpgradeProject(
            project,
            targetCohort,
          );
          final preview = previews[project.label]!;
          final receipt = <String, Object?>{
            'schemaVersion': 1,
            'root': project.label,
            'targetCohort': targetCohort,
            'stateToken': preview['stateToken'],
            'operations': preview['operations'],
            'commands': commandReceipts,
            'result': 'committed',
          };
          await _writeProjectReceipt(project, receipt);
          receipts.add(receipt);
        }
        await _validateProjectDigests(projects);
        await _deleteFleetJournal();
        return DartitectFleetReport(
          command: 'fleet upgrade --apply',
          projects: List<Map<String, Object?>>.unmodifiable(receipts),
          exitCode: 0,
        );
      } catch (error, stackTrace) {
        await snapshot.restore();
        await snapshot.validate();
        await _deleteFleetJournal();
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<Map<String, Object?>> _previewUpgradeProject(
    _FleetProject project,
    String targetCohort,
  ) async {
    if (targetCohort != '1.0.0-rc.6') {
      throw const FormatException(
        'Fleet upgrade accepts only --to=1.0.0-rc.6.',
      );
    }
    final pubspec = await File(_join(project.directory.path, 'pubspec.yaml'))
        .readAsString();
    _requireExactRc5Dependencies(pubspec);
    final dependency = await DartitectProjectService(project.directory)
        .previewDependencyUpgrade(targetCohort);
    final operations = <String>[...dependency.operations];
    DartitectConfig? migratedConfig;
    final configFile = File(_join(project.directory.path, 'dartitect.json'));
    if (await configFile.exists()) {
      final migration = migrateExactRc5Config(await configFile.readAsString());
      migratedConfig = migration.config;
      operations.add(
        migration.changed ? 'UPDATE dartitect.json' : 'NO-OP dartitect.json',
      );
      final wiring = await DartitectWiringService(project.directory)
          .inspect(config: migratedConfig);
      operations.addAll(<String>[
        for (final operation in wiring.plan.operations)
          '${operation.disposition.name.toUpperCase()} ${operation.operation.relativePath}',
      ]);
    }
    final primary = await PrimaryConstructorMigration(project.directory)
        .inspect();
    if (primary.diagnostics.isNotEmpty) {
      throw const FormatException(
        'Primary-constructor policy diagnostics block fleet upgrade.',
      );
    }
    operations.addAll(<String>[
      for (final operation in primary.operations) 'UPDATE ${operation.path}',
    ]);
    final models = await DartitectModelGenerator(project.directory).inspect();
    if (models.diagnostics.isNotEmpty) {
      throw const FormatException('Model diagnostics block fleet upgrade.');
    }
    operations.addAll(<String>[
      for (final operation
          in models.plan?.operations ?? const <PlannedFileOperation>[])
        '${operation.disposition.name.toUpperCase()} ${operation.operation.relativePath}',
    ]);
    final normalized = operations.toSet().toList()..sort();
    final inputDigest = await _projectDigest(project.directory);
    final stateToken = sha256
        .convert(
          utf8.encode(
            '$targetCohort\u0000$inputDigest\u0000${normalized.join('\u0000')}',
          ),
        )
        .toString();
    return <String, Object?>{
      'schemaVersion': 1,
      'targetCohort': targetCohort,
      'stateToken': stateToken,
      'operations': normalized,
      'validationCommands': await _validationCommandLabels(project.directory),
      if (migratedConfig != null)
        'featureCount': migratedConfig.features.declarations.length,
    };
  }

  Future<List<Map<String, Object?>>> _applyUpgradeProject(
    _FleetProject project,
    String targetCohort,
  ) async {
    final pubspec = File(_join(project.directory.path, 'pubspec.yaml'));
    final upgraded = DartitectProjectService.renderDependencyUpgradeSource(
      await pubspec.readAsString(),
      targetCohort,
    );
    await _atomicWrite(pubspec, utf8.encode(upgraded));

    final configFile = File(_join(project.directory.path, 'dartitect.json'));
    DartitectConfig? config;
    if (await configFile.exists()) {
      config = migrateExactRc5Config(await configFile.readAsString()).config;
      await _atomicWrite(configFile, utf8.encode(config.encode()));
    }

    final primary = await PrimaryConstructorMigration(project.directory)
        .inspect();
    if (primary.diagnostics.isNotEmpty) {
      throw const FormatException(
        'Primary-constructor policy diagnostics block fleet apply.',
      );
    }
    if (primary.operations.isNotEmpty) {
      await PrimaryConstructorMigration(project.directory).apply();
    }
    final models = await DartitectModelGenerator(project.directory).inspect();
    if (models.diagnostics.isNotEmpty) {
      throw const FormatException('Model diagnostics block fleet apply.');
    }
    await DartitectModelGenerator(project.directory).apply();
    if (config != null) {
      await DartitectWiringService(project.directory).apply(config: config);
    }

    final commands = await _validationCommands(project.directory);
    final receipts = <Map<String, Object?>>[];
    for (final command in commands) {
      final result = await _commandRunner(
        project.directory,
        command.executable,
        command.arguments,
      );
      final receipt = <String, Object?>{
        'command': command.label,
        'exitCode': result.exitCode,
        'output': _sanitizeOutput(result.output),
      };
      receipts.add(receipt);
      if (result.exitCode != 0) {
        throw FormatException(
          'Fleet validation failed for ${project.label}: ${command.label}.',
        );
      }
    }
    return receipts;
  }

  Future<List<String>> _validationCommandLabels(Directory root) async =>
      (await _validationCommands(root))
          .map((command) => command.label)
          .toList();

  static Future<List<_FleetCommand>> _validationCommands(Directory root) async {
    final pubspec = await File(_join(root.path, 'pubspec.yaml')).readAsString();
    final flutter = RegExp(
      r'^\s+flutter:\s*$[\s\S]*?^\s+sdk:\s+flutter\s*$',
      multiLine: true,
    ).hasMatch(pubspec);
    return flutter
        ? const <_FleetCommand>[
            _FleetCommand('flutter', <String>['pub', 'get']),
            _FleetCommand('flutter', <String>['analyze']),
            _FleetCommand('flutter', <String>['test']),
          ]
        : const <_FleetCommand>[
            _FleetCommand('dart', <String>['pub', 'get']),
            _FleetCommand('dart', <String>['analyze']),
            _FleetCommand('dart', <String>['test']),
          ];
  }

  static void _requireExactRc5Dependencies(String pubspec) {
    final dependencies = _declaredDartitectDependencies(pubspec);
    if (dependencies.isEmpty) {
      throw const FormatException(
        'Fleet RC6 migration requires at least one RC5 Dartitect dependency.',
      );
    }
    for (final dependency in dependencies) {
      final constraint = dependency['declaredConstraint'];
      if (constraint is! String ||
          !const <String>{
            '1.0.0-rc.5',
            '^1.0.0-rc.5',
            '>=1.0.0-rc.5 <1.0.0',
          }.contains(constraint)) {
        throw FormatException(
          'Dependency ${dependency['package']} is not on the exact RC5 cohort.',
        );
      }
    }
  }

  Future<T> _withFleetLocks<T>(
    List<_FleetProject> projects,
    Future<T> Function() action,
  ) async {
    final locks = <RandomAccessFile>[];
    try {
      final fleetDirectory = Directory(_join(fleetRoot.path, '.dartitect'));
      await fleetDirectory.create(recursive: true);
      final paths = <String>[
        _join(fleetDirectory.path, 'fleet-upgrade.lock'),
        for (final project in projects)
          _join(project.directory.path, '.dartitect/project-change.lock'),
      ];
      for (final path in paths) {
        final file = File(path);
        await file.parent.create(recursive: true);
        final lock = await file.open(mode: FileMode.append);
        try {
          await lock.lock(FileLock.exclusive);
        } on FileSystemException {
          await lock.close();
          throw const FormatException(
            'Fleet or project upgrade lock is already held.',
          );
        }
        locks.add(lock);
      }
      return await action();
    } finally {
      for (final lock in locks.reversed) {
        try {
          await lock.unlock();
        } finally {
          await lock.close();
        }
      }
    }
  }

  File get _fleetJournal =>
      File(_join(fleetRoot.path, '.dartitect/fleet-upgrade.transaction.json'));

  Future<void> _writeFleetJournal(_FleetSnapshot snapshot) async {
    final journal = _fleetJournal;
    await journal.parent.create(recursive: true);
    final temporary = File('${journal.path}.tmp');
    await temporary.writeAsString(
      '${jsonEncode(snapshot.toJson())}\n',
      flush: true,
    );
    if (await journal.exists()) await journal.delete();
    await temporary.rename(journal.path);
  }

  Future<void> _recoverFleetJournalIfNeeded() async {
    final journal = _fleetJournal;
    if (!await journal.exists()) return;
    final decoded = jsonDecode(await journal.readAsString());
    final snapshot = _FleetSnapshot.fromJson(fleetRoot, decoded);
    await snapshot.restore();
    await snapshot.validate();
    await _deleteFleetJournal();
  }

  Future<void> _deleteFleetJournal() async {
    final journal = _fleetJournal;
    if (await journal.exists()) await journal.delete();
    final temporary = File('${journal.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }

  static Future<void> _atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.dartitect-fleet.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  static Future<void> _writeProjectReceipt(
    _FleetProject project,
    Map<String, Object?> receipt,
  ) async {
    final file = File(
      _join(project.directory.path, '.dartitect/fleet-upgrade-receipt.json'),
    );
    await _atomicWrite(
      file,
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(receipt)}\n'),
    );
  }

  static Future<void> _validateProjectDigests(
    List<_FleetProject> projects,
  ) async {
    for (final project in projects) {
      final digest = await _projectDigest(project.directory);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const FormatException('Fleet project digest validation failed.');
      }
    }
  }

  static Future<String> _projectDigest(Directory root) async {
    final files = await _fleetFiles(root);
    final bytes = BytesBuilder(copy: false);
    for (final file in files) {
      final relative = _relativeTo(root, file.path);
      bytes.add(utf8.encode(relative));
      bytes.addByte(0);
      bytes.add(await file.readAsBytes());
      bytes.addByte(0);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  static String _sanitizeOutput(String output) {
    var value = output.replaceAll(
      RegExp(
        r'(authorization|cookie|token|password|secret|dsn)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      r'$1=<redacted>',
    );
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) value = value.replaceAll(home, '~');
    value = value.trim();
    return value.length <= 2000 ? value : '${value.substring(0, 2000)}…';
  }

  static Future<DartitectFleetCommandResult> _runFleetCommand(
    Directory root,
    String executable,
    List<String> arguments,
  ) async {
    const allowed = <String>{
      'dart pub get',
      'dart analyze',
      'dart test',
      'flutter pub get',
      'flutter analyze',
      'flutter test',
    };
    final label = '$executable ${arguments.join(' ')}';
    if (!allowed.contains(label)) {
      throw const FormatException('Fleet command is outside the allowlist.');
    }
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: root.path,
    );
    return DartitectFleetCommandResult(
      exitCode: result.exitCode,
      output: '${result.stdout}\n${result.stderr}',
    );
  }

  Future<List<_FleetProject>> _projects(Iterable<String> roots) async {
    if (!await fleetRoot.exists()) {
      throw const FormatException('Fleet root does not exist.');
    }
    final boundary = await fleetRoot.resolveSymbolicLinks();
    final byLabel = <String, _FleetProject>{};
    for (final raw in roots) {
      final label = _normalizeRelative(raw, description: 'project root');
      if (byLabel.containsKey(label)) {
        throw FormatException('Duplicate fleet project root: $label.');
      }
      final directory = Directory(_join(fleetRoot.path, label));
      if (!await directory.exists()) {
        throw FormatException('Fleet project root does not exist: $label.');
      }
      final resolved = await directory.resolveSymbolicLinks();
      _requireContained(boundary, resolved, description: 'project root');
      if (!await File(_join(resolved, 'pubspec.yaml')).exists()) {
        throw FormatException('Fleet project has no pubspec.yaml: $label.');
      }
      byLabel[label] = _FleetProject(label, Directory(resolved));
    }
    if (byLabel.isEmpty) {
      throw const FormatException(
        'At least one fleet project root is required.',
      );
    }
    final result = byLabel.values.toList()
      ..sort((left, right) => left.label.compareTo(right.label));
    return result;
  }

  Future<_LoadedPolicyBundle> _loadPolicyBundle(
    String rawPath,
    String expectedSha256,
  ) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256)) {
      throw const FormatException(
        'The policy bundle requires a lowercase SHA-256 digest.',
      );
    }
    final relative = _normalizeRelative(rawPath, description: 'bundle path');
    final boundary = await fleetRoot.resolveSymbolicLinks();
    final file = File(_join(fleetRoot.path, relative));
    if (!await file.exists()) {
      throw const FormatException('The local policy bundle does not exist.');
    }
    final resolved = await file.resolveSymbolicLinks();
    _requireContained(boundary, resolved, description: 'bundle path');
    final bytes = await File(resolved).readAsBytes();
    final actual = sha256.convert(bytes).toString();
    if (actual != expectedSha256) {
      throw const FormatException('The policy bundle digest does not match.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    const keys = <String>{
      'schemaVersion',
      'bundleVersion',
      'policyPath',
      'policySha256',
      'blockUnreviewed',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['schemaVersion'] != 1 ||
        decoded['bundleVersion'] is! String ||
        decoded['policyPath'] is! String ||
        decoded['policySha256'] is! String ||
        decoded['blockUnreviewed'] is! bool) {
      throw const FormatException('Unsupported policy bundle schema.');
    }
    final policySha = decoded['policySha256']! as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(policySha)) {
      throw const FormatException('The policy digest is invalid.');
    }
    final policyRelative = _normalizeRelative(
      decoded['policyPath']! as String,
      description: 'policy path',
    );
    final policyFile = File(_join(File(resolved).parent.path, policyRelative));
    if (!await policyFile.exists()) {
      throw const FormatException('The bundled policy file does not exist.');
    }
    final resolvedPolicy = await policyFile.resolveSymbolicLinks();
    _requireContained(boundary, resolvedPolicy, description: 'policy path');
    final policyBytes = await File(resolvedPolicy).readAsBytes();
    if (sha256.convert(policyBytes).toString() != policySha) {
      throw const FormatException('The bundled policy digest does not match.');
    }
    final policyJson = jsonDecode(utf8.decode(policyBytes));
    if (policyJson is! Map<String, Object?>) {
      throw const FormatException('The bundled policy must be a JSON object.');
    }
    final policy = EcosystemPolicy.fromJson(policyJson);
    if (policy.exceptions.isNotEmpty) {
      throw const FormatException(
        'Fleet policy bundles cannot contain time-relative exceptions.',
      );
    }
    return _LoadedPolicyBundle(
      version: decoded['bundleVersion']! as String,
      policySha256: policySha,
      blockUnreviewed: decoded['blockUnreviewed']! as bool,
      policy: policy,
    );
  }

  static List<Map<String, Object?>> _declaredDartitectDependencies(
    String source,
  ) {
    const sections = <String>{
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    };
    String? section;
    final dependencies = <Map<String, Object?>>[];
    for (final line in source.split(RegExp(r'\r?\n'))) {
      final top = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*):(?:\s|$)')
          .firstMatch(line);
      if (top != null) {
        section = sections.contains(top.group(1)) ? top.group(1) : null;
        continue;
      }
      if (section == null) continue;
      final match = RegExp(
        r'^  (dartitect(?:_[a-z0-9_]+)?):\s*(.*?)\s*(?:#.*)?$',
      ).firstMatch(line);
      if (match == null) continue;
      final raw = match.group(2)!.trim();
      final scalar = raw.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      dependencies.add(<String, Object?>{
        'package': match.group(1)!,
        'section': section,
        'source': raw.isEmpty
            ? _structuredSource(source, match.group(1)!)
            : 'hosted',
        if (raw.isNotEmpty) 'declaredConstraint': scalar,
      });
    }
    dependencies.sort((left, right) {
      final package = '${left['package']}'.compareTo('${right['package']}');
      return package != 0
          ? package
          : '${left['section']}'.compareTo('${right['section']}');
    });
    return dependencies;
  }

  static Future<Map<String, Object?>> _versionAdoptionStatus(
    Directory root,
    String pubspec,
  ) async {
    DartitectConfig? config;
    final configFile = File(_join(root.path, 'dartitect.json'));
    if (await configFile.exists())
      config = await DartitectConfig.load(configFile);
    final packages = _declaredPackageNames(pubspec);
    final providers = packages.where(_providerPackages.contains).toList()
      ..sort();
    final modelingDependency =
        packages.contains('dartitect_modeling') ||
        packages.contains('dartitect_modeling_analyzer');
    return <String, Object?>{
      'modelStatus': <String, Object?>{
        'configured': config?.modeling != null,
        if (config?.modeling case final modeling?)
          'preset': modeling.preset.wireName,
        'enabled': config?.modeling != null || modelingDependency,
        'status': config?.modeling != null
            ? 'configured'
            : modelingDependency
            ? 'dependency_only'
            : 'not_adopted',
      },
      'providerStatus': <String, Object?>{
        'installed': providers,
        'ownership': 'consumer_owned',
        'writerPolicy': 'single_writer_no_dual_write',
        'status': providers.isNotEmpty ? 'bounded' : 'none',
      },
    };
  }

  static Future<Map<String, Object?>> _featureStatus(Directory root) async {
    final configFile = File(_join(root.path, 'dartitect.json'));
    if (!await configFile.exists()) {
      return const <String, Object?>{
        'profiles': <String>[],
        'providers': <String, Object?>{
          'persistence': <String>[],
          'transport': <String>[],
        },
        'contractMatrices': <String, Object?>{
          'required': <String>[],
          'detected': <String>[],
          'missing': <String>[],
          'status': 'not_declared',
        },
      };
    }
    final config = await DartitectConfig.load(configFile);
    final declarations = config.features.declarations;
    if (declarations.isEmpty) {
      return const <String, Object?>{
        'profiles': <String>[],
        'providers': <String, Object?>{
          'persistence': <String>[],
          'transport': <String>[],
        },
        'contractMatrices': <String, Object?>{
          'required': <String>[],
          'detected': <String>[],
          'missing': <String>[],
          'status': 'not_declared',
        },
      };
    }
    final profiles =
        declarations.values
            .map((declaration) => declaration.profile.wireName)
            .toSet()
            .toList()
          ..sort();
    final persistence = <String>{
      for (final declaration in declarations.values)
        declaration.persistence.native,
      for (final declaration in declarations.values)
        declaration.persistence.web,
    }.toList()..sort();
    final transport =
        declarations.values
            .map((declaration) => declaration.transport)
            .toSet()
            .toList()
          ..sort();
    final detected = await _detectedMatrices(root);
    final missing = profiles
        .where((profile) => !detected.contains(profile))
        .toList(growable: false);
    return <String, Object?>{
      'features': <Object?>[
        for (final entry
            in declarations.entries.toList()
              ..sort((left, right) => left.key.compareTo(right.key)))
          <String, Object?>{
            'name': entry.key,
            'profile': entry.value.profile.wireName,
            'persistence': entry.value.persistence.toJson(),
            'transport': entry.value.transport,
          },
      ],
      'profiles': profiles,
      'providers': <String, Object?>{
        'persistence': persistence,
        'transport': transport,
      },
      'contractMatrices': <String, Object?>{
        'required': profiles,
        'detected': detected,
        'missing': missing,
        'status': missing.isEmpty ? 'covered' : 'missing',
      },
    };
  }

  static Future<List<String>> _detectedMatrices(Directory root) async {
    const tokens = <String, String>{
      'online': 'FeatureContractMatrix.online(',
      'cache': 'FeatureContractMatrix.cache(',
      'replica': 'FeatureContractMatrix.replica(',
      'offline-full': 'FeatureContractMatrix.offlineFull(',
    };
    final detected = <String>{};
    var visited = 0;
    for (final relative in const <String>['test', 'integration_test']) {
      final directory = Directory(_join(root.path, relative));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        visited += 1;
        if (visited > 2000) {
          throw const FormatException(
            'Fleet matrix discovery exceeds the 2000-file bound.',
          );
        }
        final length = await entity.length();
        if (length > 2 * 1024 * 1024) {
          throw const FormatException(
            'Fleet matrix discovery found a Dart file above 2 MiB.',
          );
        }
        final source = await entity.readAsString();
        for (final entry in tokens.entries) {
          if (source.contains(entry.value)) detected.add(entry.key);
        }
      }
    }
    final result = detected.toList()..sort();
    return List<String>.unmodifiable(result);
  }

  static Set<String> _declaredPackageNames(String source) {
    const sections = <String>{'dependencies', 'dev_dependencies'};
    String? section;
    final result = <String>{};
    for (final line in source.split(RegExp(r'\r?\n'))) {
      final top = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*):(?:\s|$)')
          .firstMatch(line);
      if (top != null) {
        section = sections.contains(top.group(1)) ? top.group(1) : null;
        continue;
      }
      if (section == null) continue;
      final package = RegExp(r'^  ([a-z_][a-z0-9_]*):').firstMatch(line);
      if (package != null) result.add(package.group(1)!);
    }
    return result;
  }

  static const Set<String> _providerPackages = <String>{
    'dartitect_drift',
    'dartitect_objectbox',
    'drift',
    'drift_dev',
    'objectbox',
    'objectbox_flutter_libs',
    'objectbox_generator',
  };

  static String _structuredSource(String source, String package) {
    final lines = source.split(RegExp(r'\r?\n'));
    final start = lines.indexWhere(
      (line) =>
          RegExp('^  ${RegExp.escape(package)}:\\s*(?:#.*)?\$').hasMatch(line),
    );
    if (start < 0) return 'structured';
    for (var index = start + 1; index < lines.length; index += 1) {
      if (RegExp(r'^  [a-z]').hasMatch(lines[index]) ||
          RegExp(r'^[a-z]').hasMatch(lines[index])) {
        break;
      }
      final key = RegExp(r'^    (path|git|sdk|hosted):')
          .firstMatch(lines[index]);
      if (key != null) return key.group(1)!;
    }
    return 'structured';
  }

  static Future<Map<String, String>> _lockedVersions(Directory root) async {
    final lock = File(_join(root.path, 'pubspec.lock'));
    if (!await lock.exists()) return const <String, String>{};
    final result = <String, String>{};
    String? package;
    for (final line in await lock.readAsLines()) {
      final declaration = RegExp(r'^  (dartitect(?:_[a-z0-9_]+)?):$')
          .firstMatch(line);
      if (declaration != null) {
        package = declaration.group(1)!;
        continue;
      }
      if (package == null) continue;
      final version = RegExp(r'^    version:\s*["\x27]?([^"\x27\s]+)')
          .firstMatch(line);
      if (version != null) {
        result[package] = version.group(1)!;
        package = null;
      } else if (RegExp(r'^  [a-z]').hasMatch(line)) {
        package = null;
      }
    }
    return result;
  }

  static String? _packageName(String source) {
    final match = RegExp(
      r'^name:\s*([a-z][a-z0-9_]*)\s*$',
      multiLine: true,
    ).firstMatch(source);
    return match?.group(1);
  }

  static String _normalizeRelative(String raw, {required String description}) {
    final value = raw.replaceAll('\\', '/');
    if (value.isEmpty ||
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(value)) {
      throw FormatException('The $description must be relative.');
    }
    final segments = value.split('/');
    if (segments.any((segment) => segment.isEmpty || segment == '..')) {
      throw FormatException('The $description escapes its fleet boundary.');
    }
    final normalized = segments.where((segment) => segment != '.').join('/');
    return normalized.isEmpty ? '.' : normalized;
  }

  static void _requireContained(
    String boundary,
    String candidate, {
    required String description,
  }) {
    if (candidate != boundary &&
        !candidate.startsWith('$boundary${Platform.pathSeparator}')) {
      throw FormatException('The $description escapes its fleet boundary.');
    }
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

final class _FleetProject {
  const _FleetProject(this.label, this.directory);

  final String label;
  final Directory directory;
}

final class _LoadedPolicyBundle {
  const _LoadedPolicyBundle({
    required this.version,
    required this.policySha256,
    required this.blockUnreviewed,
    required this.policy,
  });

  final String version;
  final String policySha256;
  final bool blockUnreviewed;
  final EcosystemPolicy policy;
}

final class _FleetCommand {
  const _FleetCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get label => '$executable ${arguments.join(' ')}';
}

final class _FleetSnapshot {
  const _FleetSnapshot(this.projects);

  factory _FleetSnapshot.fromJson(Directory fleetRoot, Object? value) {
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != 1 ||
        value['projects'] is! List<Object?>) {
      throw const FormatException('Invalid fleet recovery journal.');
    }
    final projects = <_FleetSnapshotProject>[];
    for (final raw in value['projects']! as List<Object?>) {
      if (raw is! Map<String, Object?> ||
          raw['root'] is! String ||
          raw['digest'] is! String ||
          raw['files'] is! Map<String, Object?>) {
        throw const FormatException('Invalid fleet recovery journal.');
      }
      final label = raw['root']! as String;
      if (!_safeRelative(label)) {
        throw const FormatException('Invalid fleet journal project root.');
      }
      final files = <String, Uint8List>{};
      for (final entry in (raw['files']! as Map<String, Object?>).entries) {
        if (!_safeRelative(entry.key) || entry.value is! String) {
          throw const FormatException('Invalid fleet journal file path.');
        }
        try {
          files[entry.key] = base64Decode(entry.value! as String);
        } on FormatException {
          throw const FormatException('Invalid fleet journal bytes.');
        }
      }
      projects.add(
        _FleetSnapshotProject(
          label: label,
          directory: Directory(_fleetJoin(fleetRoot.path, label)),
          files: files,
          digest: raw['digest']! as String,
        ),
      );
    }
    return _FleetSnapshot(List<_FleetSnapshotProject>.unmodifiable(projects));
  }

  final List<_FleetSnapshotProject> projects;

  static Future<_FleetSnapshot> capture(List<_FleetProject> projects) async {
    var totalFiles = 0;
    var totalBytes = 0;
    final snapshots = <_FleetSnapshotProject>[];
    for (final project in projects) {
      final files = <String, Uint8List>{};
      for (final file in await _fleetFiles(project.directory)) {
        totalFiles += 1;
        final bytes = await file.readAsBytes();
        totalBytes += bytes.length;
        if (totalFiles > 10000 || totalBytes > 128 * 1024 * 1024) {
          throw const FormatException(
            'Fleet journal exceeds its 10000-file or 128 MiB bound.',
          );
        }
        files[_relativeTo(project.directory, file.path)] = bytes;
      }
      snapshots.add(
        _FleetSnapshotProject(
          label: project.label,
          directory: project.directory,
          files: files,
          digest: await DartitectFleetService._projectDigest(project.directory),
        ),
      );
    }
    return _FleetSnapshot(List<_FleetSnapshotProject>.unmodifiable(snapshots));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'phase': 'prepared',
    'projects': <Object?>[
      for (final project in projects)
        <String, Object?>{
          'root': project.label,
          'digest': project.digest,
          'files': <String, Object?>{
            for (final entry in project.files.entries)
              entry.key: base64Encode(entry.value),
          },
        },
    ],
  };

  Future<void> restore() async {
    for (final project in projects) {
      final current = await _fleetFiles(project.directory);
      for (final file in current) {
        final relative = _relativeTo(project.directory, file.path);
        if (!project.files.containsKey(relative)) await file.delete();
      }
      for (final entry in project.files.entries) {
        final file = File(_fleetJoin(project.directory.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
    }
  }

  Future<void> validate() async {
    for (final project in projects) {
      final actual = await DartitectFleetService._projectDigest(
        project.directory,
      );
      if (actual != project.digest) {
        throw const FormatException('Fleet rollback digest validation failed.');
      }
    }
  }
}

final class _FleetSnapshotProject {
  const _FleetSnapshotProject({
    required this.label,
    required this.directory,
    required this.files,
    required this.digest,
  });

  final String label;
  final Directory directory;
  final Map<String, Uint8List> files;
  final String digest;
}

Future<List<File>> _fleetFiles(Directory root) async {
  final files = <File>[];
  if (!await root.exists()) return files;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = _relativeTo(root, entity.path);
    final segments = relative.split('/');
    if (segments.any(
          (segment) =>
              segment == '.git' ||
              segment == '.dart_tool' ||
              segment == 'build',
        ) ||
        relative == '.dartitect/fleet-upgrade.transaction.json' ||
        relative == '.dartitect/fleet-upgrade.transaction.json.tmp' ||
        relative == '.dartitect/fleet-upgrade.lock' ||
        relative == '.dartitect/project-change.lock') {
      continue;
    }
    files.add(entity);
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

String _relativeTo(Directory root, String path) => path
    .substring(root.absolute.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

String _fleetJoin(String left, String right) =>
    '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

bool _safeRelative(String value) =>
    value.isNotEmpty &&
    !value.startsWith('/') &&
    !RegExp(r'^[A-Za-z]:').hasMatch(value) &&
    !value.split('/').any((segment) => segment.isEmpty || segment == '..');
