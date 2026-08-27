import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../codex/codex_skill_synchronizer.dart';
import '../codex/skill_catalog.dart';
import '../config/dartitect_config.dart';
import '../diagnostics/models.dart';
import '../generation/generation_engine.dart';
import '../generation/scaffolds.dart';
import '../policy/ecosystem_policy.dart';
import '../scan/baseline.dart';
import '../scan/project_scanner.dart';

/// A filesystem change supported by the reusable Dartitect project service.
enum DartitectChangeKind {
  /// Create the initial credential-free `dartitect.json` configuration.
  init,

  /// Replace the reviewed architecture baseline.
  baseline,

  /// Synchronize the ten managed Codex skills.
  codexSync,

  /// Upgrade reviewed Dartitect dependency constraints as one cohort.
  dependencyUpgrade,
}

/// One project-relative semantic input bound to a reviewed change plan.
final class DartitectSemanticInput {
  /// Creates a semantic input entry.
  const DartitectSemanticInput({required this.path, required this.sha256});

  /// Project-relative path, or a stable virtual input name prefixed by `@`.
  final String path;

  /// Lowercase SHA-256 digest of the input bytes or missing-input marker.
  final String sha256;

  /// Stable machine-readable representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'sha256': sha256,
  };
}

/// Versioned semantic input manifest for one project change plan.
final class DartitectSemanticManifest {
  /// Creates a semantic manifest.
  const DartitectSemanticManifest({
    required this.kind,
    required this.inputs,
    required this.digest,
  });

  /// Manifest schema, versioned independently from package releases.
  static const int schemaVersion = 1;

  /// Change category whose semantic inputs are described.
  final DartitectChangeKind kind;

  /// Sorted, project-relative semantic inputs.
  final List<DartitectSemanticInput> inputs;

  /// SHA-256 digest of the canonical manifest representation.
  final String digest;

  /// Stable machine-readable representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind.name,
    'inputs': inputs.map((input) => input.toJson()).toList(),
    'digest': digest,
  };
}

/// A validated, read-only preview of one supported project change.
final class DartitectChangePlan {
  /// Creates a change plan.
  const DartitectChangePlan({
    required this.kind,
    required this.operations,
    required this.preview,
    required this.stateToken,
    required this.semanticManifest,
    this.overwriteManaged = false,
    this.targetCohort,
  });

  /// Plan JSON schema, versioned independently from package releases.
  static const int schemaVersion = 1;

  /// Change category.
  final DartitectChangeKind kind;

  /// Deterministic project-relative operations.
  final List<String> operations;

  /// Sanitized human-readable preview.
  final String preview;

  /// Opaque fingerprint used to reject stale plans.
  final String stateToken;

  /// Reviewed semantic inputs whose canonical digest is [stateToken].
  final DartitectSemanticManifest semanticManifest;

  /// Whether locally changed managed Codex skills may be replaced.
  final bool overwriteManaged;

  /// Target Dartitect release cohort for a dependency upgrade.
  final String? targetCohort;

  /// Stable representation that intentionally omits the internal state token.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind.name,
    'operations': operations,
    'preview': preview,
    'overwriteManaged': overwriteManaged,
    if (targetCohort != null) 'targetCohort': targetCohort,
    'semanticManifest': semanticManifest.toJson(),
  };
}

/// Receipt returned after a revalidated project change is committed.
final class DartitectChangeReceipt {
  /// Creates a change receipt.
  const DartitectChangeReceipt({
    required this.kind,
    required this.operations,
    required this.changed,
  });

  /// Receipt JSON schema, versioned independently from package releases.
  static const int schemaVersion = 1;

  /// Applied change category.
  final DartitectChangeKind kind;

  /// Deterministic project-relative operations.
  final List<String> operations;

  /// Whether the filesystem changed.
  final bool changed;

  /// Stable machine-readable representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind.name,
    'operations': operations,
    'changed': changed,
  };
}

/// A rejected plan or failed transactional change.
final class DartitectChangeException implements Exception {
  /// Creates a structured change failure.
  const DartitectChangeException(this.code, this.message);

  /// Stable error code such as `stale_plan`.
  final String code;

  /// Sanitized actionable description.
  final String message;

  @override
  String toString() => message;
}

/// Typed project operations shared by the Dartitect CLI and MCP server.
///
/// Read methods never mutate the project. Every write starts from a preview,
/// revalidates its state token, and commits through the existing transactional
/// generator, config migrator, or Codex synchronizer.
final class DartitectProjectService {
  /// Creates a service for one project root.
  DartitectProjectService(Directory root) : root = root.absolute;

  /// Project root used internally. Public results contain relative paths only.
  final Directory root;

  static final Set<String> _activeChangeRoots = <String>{};

  /// Returns consolidated project metadata and architecture findings.
  Future<CommandEnvelope> inspectProject() => _readOnly('inspect');

  /// Scans architecture boundaries, optionally applying the reviewed baseline.
  Future<CommandEnvelope> scanArchitecture({bool useBaseline = true}) =>
      _readOnly('scan', useBaseline: useBaseline);

  /// Validates configuration, toolchain, skills, and optional analyzer state.
  Future<CommandEnvelope> doctorProject({bool deep = false}) =>
      _readOnly('doctor', deep: deep);

  /// Audits Native Strict conformance without proposing a migration workflow.
  Future<Map<String, Object?>> auditConformance() async {
    final report = await scanArchitecture(useBaseline: false);
    final policy = await EcosystemPolicy.load(root);
    final dependencies =
        (report.project['dependencies'] as List<Object?>?)
            ?.whereType<String>()
            .toSet() ??
        <String>{};
    final runtimeConflicts =
        dependencies
            .map(policy.explain)
            .where(
              (record) =>
                  record.decision == EcosystemDecision.prohibitedNativeStrict,
            )
            .map((record) => record.toJson())
            .toList()
          ..sort(
            (left, right) =>
                '${left['package']}'.compareTo('${right['package']}'),
          );
    final compliant =
        report.findings.isEmpty &&
        report.violations.isEmpty &&
        runtimeConflicts.isEmpty;
    return <String, Object?>{
      'schemaVersion': 1,
      'command': 'conformance audit',
      'profile': 'native_strict',
      'support': const <String, Object?>{
        'target': 'greenfield_only',
        'existingProjects': 'audit_only',
        'migration': false,
        'coexistence': false,
      },
      'project': report.project,
      'compliant': compliant,
      'canonicalGate': 'dartitect scan --no-baseline',
      'runtimeConflicts': runtimeConflicts,
      'findings': <Object?>[
        for (final finding in report.findings) finding.toJson(),
      ],
      'violations': <Object?>[
        for (final violation in report.violations) violation.toJson(),
      ],
      'violationCount': report.violations.length,
      'findingCount': report.findings.length,
    };
  }

  /// Produces a read-only plan for [kind].
  Future<DartitectChangePlan> previewChange(
    DartitectChangeKind kind, {
    bool overwriteManaged = false,
    String? targetCohort,
  }) async {
    if (!await root.exists()) {
      throw FileSystemException('Project root does not exist');
    }
    return switch (kind) {
      DartitectChangeKind.init => _previewInit(),
      DartitectChangeKind.baseline => _previewBaseline(),
      DartitectChangeKind.codexSync => _previewCodexSync(
        overwriteManaged: overwriteManaged,
      ),
      DartitectChangeKind.dependencyUpgrade => _previewDependencyUpgrade(
        _validatedTargetCohort(targetCohort),
      ),
    };
  }

  /// Previews a lockstep Dartitect dependency upgrade without writing files.
  Future<DartitectChangePlan> previewDependencyUpgrade(String targetCohort) =>
      previewChange(
        DartitectChangeKind.dependencyUpgrade,
        targetCohort: targetCohort,
      );

  /// Revalidates and commits a previously returned [plan].
  Future<DartitectChangeReceipt> applyChange(DartitectChangePlan plan) async {
    return _withChangeLock(() async {
      if (plan.kind == DartitectChangeKind.dependencyUpgrade) {
        await _recoverDependencyUpgradeIfNeeded();
      }
      final current = await previewChange(
        plan.kind,
        overwriteManaged: plan.overwriteManaged,
        targetCohort: plan.targetCohort,
      );
      if (current.stateToken != plan.stateToken ||
          !_sameStrings(current.operations, plan.operations)) {
        throw const DartitectChangeException(
          'stale_plan',
          'Project state changed after preview; create and review a new plan.',
        );
      }

      switch (plan.kind) {
        case DartitectChangeKind.init:
          final scan = await ProjectScanner(root).scan();
          final result = await GenerationEngine(root).apply(
            ScaffoldFactory(packageName: scan.packageName ?? 'application')
                .init(),
          );
          return DartitectChangeReceipt(
            kind: plan.kind,
            operations: plan.operations,
            changed: result.createdPaths.isNotEmpty,
          );
        case DartitectChangeKind.baseline:
          final scan = await ProjectScanner(root).scan();
          final content = DartitectBaseline.fromFindings(scan.violations)
              .encode();
          await _commitBaseline(content);
          return DartitectChangeReceipt(
            kind: plan.kind,
            operations: plan.operations,
            changed: plan.operations.any((value) => value.startsWith('UPDATE')),
          );
        case DartitectChangeKind.codexSync:
          final result = await CodexSkillSynchronizer(root)
              .sync(overwriteManaged: plan.overwriteManaged);
          return DartitectChangeReceipt(
            kind: plan.kind,
            operations: result.operations,
            changed: result.operations.any(
              (value) => !value.startsWith('NO-OP'),
            ),
          );
        case DartitectChangeKind.dependencyUpgrade:
          await _commitDependencyUpgrade(
            _renderDependencyUpgrade(
              await File(_join(root.path, 'pubspec.yaml')).readAsString(),
              _validatedTargetCohort(plan.targetCohort),
            ),
          );
          return DartitectChangeReceipt(
            kind: plan.kind,
            operations: plan.operations,
            changed: plan.operations.any((value) => value.startsWith('UPDATE')),
          );
      }
    });
  }

  Future<CommandEnvelope> _readOnly(
    String command, {
    bool useBaseline = true,
    bool deep = false,
  }) async {
    final scan = await ProjectScanner(root).scan();
    final findings = <DartitectFinding>[...scan.findings];
    var violations = <DartitectFinding>[...scan.violations];
    if (command == 'scan' && useBaseline) {
      final baselineFile = File(_join(root.path, '.dartitect/baseline.json'));
      if (await baselineFile.exists()) {
        try {
          final baseline = await DartitectBaseline.load(baselineFile);
          final current = violations.map(fingerprintFinding).toSet();
          violations = violations
              .where(
                (violation) => !baseline.fingerprints.contains(
                  fingerprintFinding(violation),
                ),
              )
              .toList();
          for (final obsolete in baseline.fingerprints.difference(current)) {
            findings.add(
              DartitectFinding(
                code: 'DT2301',
                severity: FindingSeverity.warning,
                message: 'Baseline entry is obsolete.',
                path: '.dartitect/baseline.json',
                evidence: obsolete,
                remediation: 'Review and recreate the baseline.',
              ),
            );
          }
        } on FormatException catch (error) {
          findings.add(
            DartitectFinding(
              code: 'DT2300',
              severity: FindingSeverity.error,
              message: 'The architecture baseline is invalid.',
              path: '.dartitect/baseline.json',
              evidence: error.message,
              remediation: 'Recreate the baseline after reviewing violations.',
            ),
          );
        }
      }
    }

    DartitectConfig? config;
    final configFile = File(_join(root.path, 'dartitect.json'));
    if (await configFile.exists()) {
      try {
        config = await DartitectConfig.load(configFile);
        for (final key in config.unknown.keys) {
          findings.add(
            DartitectFinding(
              code: 'DT2002',
              severity: FindingSeverity.warning,
              message: 'Unknown configuration key is preserved: $key.',
              path: 'dartitect.json',
              evidence: '/$key',
              remediation: 'Check whether the key belongs to a newer SDK.',
            ),
          );
        }
      } on DartitectConfigException catch (error) {
        findings.add(
          DartitectFinding(
            code: 'DT2001',
            severity: FindingSeverity.error,
            message: error.message,
            path: 'dartitect.json',
            evidence: error.pointer,
            remediation:
                'Correct the indicated JSON value; the file was not changed.',
          ),
        );
      }
    } else if (command == 'doctor') {
      findings.add(
        const DartitectFinding(
          code: 'DT2000',
          severity: FindingSeverity.warning,
          message: 'dartitect.json was not found.',
          path: 'dartitect.json',
          remediation:
              'Run `dartitect init --dry-run`, review, then `dartitect init`.',
        ),
      );
    }

    if (command == 'doctor') {
      findings.addAll(_doctorFindings(scan, config));
      findings.addAll(await _splashFindings(scan));
      findings.addAll(await _skillFindings());
      findings.addAll(await _toolingFindings(scan, config));
      if (deep) findings.addAll(await _deepDoctor());
    }
    findings.sort(_compareFinding);
    final hasFindings =
        findings.any((finding) => finding.severity != FindingSeverity.info) ||
        violations.isNotEmpty;
    return CommandEnvelope(
      command: command,
      project: <String, Object?>{
        'root': '.',
        if (scan.packageName != null) 'name': scan.packageName,
        if (config != null) 'configVersion': config.configVersion,
        'dartFiles': scan.dartFileCount,
        'features': scan.features,
        'platforms': scan.platforms,
        'dependencies': scan.dependencies,
      },
      capabilities: scan.capabilities,
      findings: findings,
      violations: violations,
      exitCode: hasFindings ? 1 : 0,
    );
  }

  List<DartitectFinding> _doctorFindings(
    ProjectScan scan,
    DartitectConfig? config,
  ) {
    final findings = <DartitectFinding>[];
    final version = RegExp(r'^(\d+)\.(\d+)').firstMatch(Platform.version);
    final major = int.tryParse(version?.group(1) ?? '0') ?? 0;
    final minor = int.tryParse(version?.group(2) ?? '0') ?? 0;
    if (major < 3 || major == 3 && minor < 13) {
      findings.add(
        DartitectFinding(
          code: 'DT2100',
          severity: FindingSeverity.error,
          message: 'Dart 3.13 or newer is required; found ${Platform.version}.',
          remediation: 'Upgrade the Dart/Flutter SDK.',
        ),
      );
    }
    return findings;
  }

  Future<List<DartitectFinding>> _splashFindings(ProjectScan scan) async {
    final findings = <DartitectFinding>[];
    if (scan.platforms.contains('android')) {
      const path = 'android/app/src/main/res/drawable/launch_background.xml';
      final resource = File(_join(root.path, path));
      if (!await resource.exists() ||
          !(await resource.readAsString()).contains('<layer-list')) {
        findings.add(
          const DartitectFinding(
            code: 'DT1024',
            severity: FindingSeverity.error,
            message:
                'Android launch background resource is missing or invalid.',
            path: path,
            remediation:
                'Restore a static launch_background.xml owned by the app.',
          ),
        );
      }
    }
    if (scan.platforms.contains('ios')) {
      const storyboardPath = 'ios/Runner/Base.lproj/LaunchScreen.storyboard';
      const plistPath = 'ios/Runner/Info.plist';
      final storyboard = File(_join(root.path, storyboardPath));
      final plist = File(_join(root.path, plistPath));
      final storyboardValid =
          await storyboard.exists() &&
          (await storyboard.readAsString()).contains('<document');
      final plistValid =
          await plist.exists() &&
          (await plist.readAsString()).contains('UILaunchStoryboardName');
      if (!storyboardValid || !plistValid) {
        findings.add(
          const DartitectFinding(
            code: 'DT1025',
            severity: FindingSeverity.error,
            message:
                'iOS launch storyboard resources are missing or disconnected.',
            path: storyboardPath,
            remediation:
                'Restore LaunchScreen.storyboard and UILaunchStoryboardName.',
          ),
        );
      }
    }
    return findings;
  }

  Future<List<DartitectFinding>> _deepDoctor() async {
    try {
      final result = await Process.run('dart', <String>[
        'analyze',
      ], workingDirectory: root.path).timeout(const Duration(minutes: 2));
      if (result.exitCode == 0) return const <DartitectFinding>[];
      return <DartitectFinding>[
        DartitectFinding(
          code: 'DT2200',
          severity: FindingSeverity.error,
          message: 'Deep `dart analyze` validation failed.',
          evidence: _sanitize(_firstLine('${result.stdout}${result.stderr}')),
          remediation: 'Run `dart analyze` and resolve diagnostics.',
        ),
      ];
    } on TimeoutException {
      return const <DartitectFinding>[
        DartitectFinding(
          code: 'DT2201',
          severity: FindingSeverity.warning,
          message: 'Deep analyzer check timed out after two minutes.',
          remediation:
              'Run `dart analyze` directly and inspect analyzer performance.',
        ),
      ];
    }
  }

  Future<DartitectChangePlan> _previewInit() async {
    final scan = await ProjectScanner(root).scan();
    final plan = await GenerationEngine(root).plan(
      ScaffoldFactory(packageName: scan.packageName ?? 'application').init(),
    );
    final operations = <String>[
      for (final operation in plan.operations)
        '${operation.disposition.name.toUpperCase()} ${operation.operation.relativePath}',
    ];
    final preview = plan.operations.map((value) => value.preview).join('\n');
    final manifest = await _semanticManifest(
      DartitectChangeKind.init,
      '$operations\u0000$preview',
    );
    return DartitectChangePlan(
      kind: DartitectChangeKind.init,
      operations: List<String>.unmodifiable(operations),
      preview: preview,
      stateToken: manifest.digest,
      semanticManifest: manifest,
    );
  }

  Future<DartitectChangePlan> _previewBaseline() async {
    final scan = await ProjectScanner(root).scan();
    final content = DartitectBaseline.fromFindings(scan.violations).encode();
    final target = File(_join(root.path, '.dartitect/baseline.json'));
    final current = await target.exists() ? await target.readAsString() : null;
    final operation = current == content
        ? 'NO-OP .dartitect/baseline.json'
        : 'UPDATE .dartitect/baseline.json';
    final manifest = await _semanticManifest(
      DartitectChangeKind.baseline,
      '${current ?? '<missing>'}\u0000$content',
    );
    return DartitectChangePlan(
      kind: DartitectChangeKind.baseline,
      operations: <String>[operation],
      preview: content,
      stateToken: manifest.digest,
      semanticManifest: manifest,
    );
  }

  Future<DartitectChangePlan> _previewCodexSync({
    required bool overwriteManaged,
  }) async {
    final result = await CodexSkillSynchronizer(root)
        .preview(overwriteManaged: overwriteManaged);
    final operations = List<String>.unmodifiable(result.operations);
    final preview = '${operations.join('\n')}\n';
    final manifest = await _semanticManifest(
      DartitectChangeKind.codexSync,
      '${overwriteManaged ? 1 : 0}\u0000$preview',
    );
    return DartitectChangePlan(
      kind: DartitectChangeKind.codexSync,
      operations: operations,
      preview: preview,
      stateToken: manifest.digest,
      semanticManifest: manifest,
      overwriteManaged: overwriteManaged,
    );
  }

  Future<DartitectChangePlan> _previewDependencyUpgrade(
    String targetCohort,
  ) async {
    final pubspec = File(_join(root.path, 'pubspec.yaml'));
    if (!await pubspec.exists()) {
      throw const DartitectChangeException(
        'missing_pubspec',
        'A project pubspec.yaml is required for a dependency upgrade.',
      );
    }
    final current = await pubspec.readAsString();
    final updated = _renderDependencyUpgrade(current, targetCohort);
    final changed = current != updated;
    final operation = changed ? 'UPDATE pubspec.yaml' : 'NO-OP pubspec.yaml';
    final manifest = await _semanticManifest(
      DartitectChangeKind.dependencyUpgrade,
      'target=$targetCohort\u0000before=${sha256.convert(utf8.encode(current))}'
      '\u0000after=${sha256.convert(utf8.encode(updated))}',
    );
    return DartitectChangePlan(
      kind: DartitectChangeKind.dependencyUpgrade,
      operations: <String>[operation],
      preview: changed
          ? 'Upgrade reviewed Dartitect constraints to $targetCohort.'
          : 'Dartitect constraints already target $targetCohort.',
      stateToken: manifest.digest,
      semanticManifest: manifest,
      targetCohort: targetCohort,
    );
  }

  static String _validatedTargetCohort(String? value) {
    if (value == null ||
        !RegExp(r'^1\.0\.0-rc\.[1-9][0-9]*$').hasMatch(value)) {
      throw const DartitectChangeException(
        'invalid_target_cohort',
        'The target cohort must be an explicit 1.0.0-rc.N version.',
      );
    }
    return value;
  }

  static String _renderDependencyUpgrade(String source, String target) {
    const sections = <String>{
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    };
    String? section;
    final lineEnding = source.contains('\r\n') ? '\r\n' : '\n';
    final lines = source.split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      final topLevel = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*):(?:\s|$)')
          .firstMatch(line);
      if (topLevel != null) {
        section = sections.contains(topLevel.group(1))
            ? topLevel.group(1)
            : null;
        continue;
      }
      if (section == null) continue;
      final declaration = RegExp(r'^(  )([a-z][a-z0-9_]*):\s*(.*?)\s*(#.*)?$')
          .firstMatch(line);
      if (declaration == null) continue;
      final package = declaration.group(2)!;
      if (!_dartitectPackages.contains(package)) continue;
      final raw = declaration.group(3)!.trim();
      if (raw.isEmpty) {
        throw DartitectChangeException(
          'unsupported_dependency_source',
          'Dependency $package uses a structured source and cannot be upgraded automatically.',
        );
      }
      final quote = raw.startsWith("'") && raw.endsWith("'")
          ? "'"
          : raw.startsWith('"') && raw.endsWith('"')
          ? '"'
          : '';
      final constraint = quote.isEmpty ? raw : raw.substring(1, raw.length - 1);
      final replacement = switch (constraint) {
        final value when RegExp(r'^\^1\.0\.0-rc\.\d+$').hasMatch(value) =>
          '^$target',
        final value when RegExp(r'^1\.0\.0-rc\.\d+$').hasMatch(value) => target,
        final value
            when RegExp(r'^>=1\.0\.0-rc\.\d+\s+<1\.0\.0$').hasMatch(value) =>
          '>=$target <1.0.0',
        _ => throw DartitectChangeException(
          'unsupported_dependency_constraint',
          'Dependency $package has a constraint that requires manual review.',
        ),
      };
      lines[index] =
          '${declaration.group(1)}$package: '
          '$quote$replacement$quote${declaration.group(4) == null ? '' : ' ${declaration.group(4)}'}';
    }
    return lines.join(lineEnding);
  }

  Future<void> _commitDependencyUpgrade(String content) async {
    final directory = Directory(_join(root.path, '.dartitect'));
    await directory.create(recursive: true);
    final target = File(_join(root.path, 'pubspec.yaml'));
    final stage = File(
      _join(directory.path, 'dependency-upgrade.pubspec.stage'),
    );
    final backup = File(
      _join(directory.path, 'dependency-upgrade.pubspec.backup'),
    );
    final journal = File(
      _join(directory.path, 'dependency-upgrade.transaction.json'),
    );
    await _recoverDependencyUpgradeIfNeeded();
    if (await target.readAsString() == content) return;
    final digest = sha256.convert(utf8.encode(content)).toString();
    await stage.writeAsString(content, flush: true);
    await _writeDependencyJournal(journal, 'staged', digest);
    try {
      await target.rename(backup.path);
      await _writeDependencyJournal(journal, 'backedUp', digest);
      try {
        await stage.rename(target.path);
      } on FileSystemException {
        await stage.copy(target.path);
        await stage.delete();
      }
      final committed = await sha256.bind(target.openRead()).first;
      if (committed.toString() != digest) {
        throw const DartitectChangeException(
          'dependency_upgrade_verification_failed',
          'The upgraded pubspec failed its post-write digest check.',
        );
      }
      await _writeDependencyJournal(journal, 'committed', digest);
      await _cleanupDependencyUpgrade(stage, backup, journal);
    } on Object {
      await _recoverDependencyUpgradeIfNeeded();
      rethrow;
    }
  }

  Future<void> _recoverDependencyUpgradeIfNeeded() async {
    final directory = Directory(_join(root.path, '.dartitect'));
    final target = File(_join(root.path, 'pubspec.yaml'));
    final stage = File(
      _join(directory.path, 'dependency-upgrade.pubspec.stage'),
    );
    final backup = File(
      _join(directory.path, 'dependency-upgrade.pubspec.backup'),
    );
    final journal = File(
      _join(directory.path, 'dependency-upgrade.transaction.json'),
    );
    if (!await journal.exists()) {
      if (await stage.exists() || await backup.exists()) {
        throw const DartitectChangeException(
          'dependency_upgrade_recovery_required',
          'Unjournaled dependency-upgrade artifacts require manual review.',
        );
      }
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(await journal.readAsString());
    } on FormatException {
      throw const DartitectChangeException(
        'dependency_upgrade_recovery_required',
        'The dependency-upgrade journal is invalid and requires manual review.',
      );
    }
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 1 ||
        decoded['phase'] is! String ||
        decoded['targetSha256'] is! String) {
      throw const DartitectChangeException(
        'dependency_upgrade_recovery_required',
        'The dependency-upgrade journal is invalid and requires manual review.',
      );
    }
    if (decoded['phase'] == 'committed' && await target.exists()) {
      final digest = await sha256.bind(target.openRead()).first;
      if (digest.toString() == decoded['targetSha256']) {
        await _cleanupDependencyUpgrade(stage, backup, journal);
        return;
      }
    }
    if (await backup.exists()) {
      if (await target.exists()) await target.delete();
      await backup.rename(target.path);
    }
    if (await stage.exists()) await stage.delete();
    if (await journal.exists()) await journal.delete();
  }

  static Future<void> _writeDependencyJournal(
    File journal,
    String phase,
    String digest,
  ) => journal.writeAsString(
    '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'phase': phase, 'targetSha256': digest})}\n',
    flush: true,
  );

  static Future<void> _cleanupDependencyUpgrade(
    File stage,
    File backup,
    File journal,
  ) async {
    if (await stage.exists()) await stage.delete();
    if (await backup.exists()) await backup.delete();
    if (await journal.exists()) await journal.delete();
  }

  Future<void> _commitBaseline(String content) async {
    final directory = Directory(_join(root.path, '.dartitect'));
    await directory.create(recursive: true);
    final target = File(_join(directory.path, 'baseline.json'));
    final stage = File(_join(directory.path, 'baseline.json.stage'));
    final backup = File(_join(directory.path, 'baseline.json.backup'));
    final journal = File(_join(directory.path, 'baseline.transaction.json'));
    if (await journal.exists()) {
      await _recoverBaseline(target, stage, backup, journal);
    }
    if (await target.exists() && await target.readAsString() == content) return;
    await stage.writeAsString(content, flush: true);
    await journal.writeAsString(
      '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'phase': 'staged'})}\n',
      flush: true,
    );
    try {
      if (await target.exists()) await target.rename(backup.path);
      await journal.writeAsString(
        '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'phase': 'backedUp'})}\n',
        flush: true,
      );
      try {
        await stage.rename(target.path);
      } on FileSystemException {
        await stage.copy(target.path);
        await stage.delete();
      }
      await DartitectBaseline.load(target);
      if (await backup.exists()) await backup.delete();
      await journal.delete();
    } on Object {
      await _recoverBaseline(target, stage, backup, journal);
      rethrow;
    }
  }

  Future<void> _recoverBaseline(
    File target,
    File stage,
    File backup,
    File journal,
  ) async {
    if (await backup.exists()) {
      if (await target.exists()) await target.delete();
      await backup.rename(target.path);
    }
    if (await stage.exists()) await stage.delete();
    if (await journal.exists()) await journal.delete();
  }

  Future<List<DartitectFinding>> _skillFindings() async {
    final skills = Directory(_join(root.path, '.agents/skills'));
    if (!await skills.exists()) {
      return const <DartitectFinding>[
        DartitectFinding(
          code: 'DT2400',
          severity: FindingSeverity.warning,
          message: 'Dartitect Codex skills are not installed.',
          path: '.agents/skills',
          remediation: 'Run `dartitect codex sync --dry-run`, then sync.',
        ),
      ];
    }
    final findings = <DartitectFinding>[];
    for (final template in dartitectSkillCatalog) {
      final name = template.name;
      final manifest = File(_join(skills.path, '$name/.dartitect-skill.json'));
      if (!await manifest.exists()) {
        findings.add(
          DartitectFinding(
            code: 'DT2401',
            severity: FindingSeverity.warning,
            message: 'Dartitect skill is missing its management manifest.',
            path: '.agents/skills/$name',
            remediation: 'Review the directory before running codex sync.',
          ),
        );
      }
    }
    return findings;
  }

  Future<List<DartitectFinding>> _toolingFindings(
    ProjectScan scan,
    DartitectConfig? config,
  ) async {
    final findings = <DartitectFinding>[];
    final analysisOptions = await _nearestAnalysisOptions();
    final pluginEnabled =
        analysisOptions != null &&
        await analysisOptions.readAsString().then(
          (source) => source.contains('dartitect_lints:'),
        );
    if (config != null && !pluginEnabled) {
      findings.add(
        const DartitectFinding(
          code: 'DT2501',
          severity: FindingSeverity.warning,
          message: 'The official Dartitect analyzer plugin is not enabled.',
          path: 'analysis_options.yaml',
          remediation:
              'Enable dartitect_lints in the top-level plugins section.',
        ),
      );
    }
    for (final path in const <String>[
      '.dartitect-generation.json',
      '.dartitect-codex-sync.json',
      '.dartitect/baseline.json.stage',
      '.dartitect/baseline.json.backup',
      '.dartitect/baseline.transaction.json',
      '.dartitect/dependency-upgrade.pubspec.stage',
      '.dartitect/dependency-upgrade.pubspec.backup',
      '.dartitect/dependency-upgrade.transaction.json',
    ]) {
      if (await File(_join(root.path, path)).exists()) {
        findings.add(
          DartitectFinding(
            code: 'DT2502',
            severity: FindingSeverity.error,
            message: 'A stale transactional artifact requires recovery.',
            path: path,
            remediation: 'Re-run the originating command to recover safely.',
          ),
        );
      }
    }
    return findings;
  }

  Future<File?> _nearestAnalysisOptions() async {
    var directory = root;
    while (true) {
      final candidate = File(_join(directory.path, 'analysis_options.yaml'));
      if (await candidate.exists()) return candidate;
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  String _sanitize(String value) {
    var result = value.replaceAll(root.path, '.');
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) result = result.replaceAll(home, '~');
    return result;
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static int _compareFinding(DartitectFinding left, DartitectFinding right) {
    final code = left.code.compareTo(right.code);
    if (code != 0) return code;
    return (left.path ?? '').compareTo(right.path ?? '');
  }

  static String _firstLine(String output) =>
      output.trim().split(RegExp(r'\r?\n')).firstOrNull ?? '';

  Future<T> _withChangeLock<T>(Future<T> Function() action) async {
    final rootPath = root.absolute.path;
    if (!_activeChangeRoots.add(rootPath)) {
      throw const DartitectChangeException(
        'change_locked',
        'Another Dartitect project change is active; retry from a new plan.',
      );
    }
    RandomAccessFile? lock;
    try {
      final directory = Directory(_join(root.path, '.dartitect'));
      await directory.create(recursive: true);
      lock = await File(_join(directory.path, 'project-change.lock'))
          .open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const DartitectChangeException(
          'change_locked',
          'Another Dartitect project change is active; retry from a new plan.',
        );
      }
      return await action();
    } finally {
      if (lock != null) {
        // Closing the descriptor releases the OS lock even when commit failed.
        await lock.close();
      }
      _activeChangeRoots.remove(rootPath);
    }
  }

  Future<DartitectSemanticManifest> _semanticManifest(
    DartitectChangeKind kind,
    String semanticState,
  ) async {
    final files = switch (kind) {
      DartitectChangeKind.init => await _initSemanticInputs(),
      DartitectChangeKind.baseline => await _baselineSemanticInputs(),
      DartitectChangeKind.codexSync => await _codexSemanticInputs(),
      DartitectChangeKind.dependencyUpgrade =>
        await _dependencyUpgradeSemanticInputs(),
    };
    final inputs = <DartitectSemanticInput>[
      DartitectSemanticInput(
        path: '@plan',
        sha256: sha256.convert(utf8.encode(semanticState)).toString(),
      ),
    ];
    final paths = files.toList()..sort();
    for (final path in paths) {
      final file = File(_join(root.path, path));
      final digest = await file.exists()
          ? (await sha256.bind(file.openRead()).first).toString()
          : sha256.convert(utf8.encode('<missing>')).toString();
      inputs.add(DartitectSemanticInput(path: path, sha256: digest));
    }
    inputs.sort((left, right) => left.path.compareTo(right.path));
    final canonical = StringBuffer('schema=1\u0000kind=${kind.name}\u0000');
    for (final input in inputs) {
      canonical
        ..write(input.path)
        ..write('\u0000')
        ..write(input.sha256)
        ..write('\u0000');
    }
    final digest = sha256.convert(utf8.encode(canonical.toString())).toString();
    return DartitectSemanticManifest(
      kind: kind,
      inputs: List<DartitectSemanticInput>.unmodifiable(inputs),
      digest: digest,
    );
  }

  Future<Set<String>> _initSemanticInputs() async => <String>{
    'pubspec.yaml',
    'dartitect.json',
    'AGENTS.md',
    '.dartitect-model-outputs.json',
    '.dartitect-generation.json',
  };

  Future<Set<String>> _baselineSemanticInputs() async {
    final inputs = <String>{
      'pubspec.yaml',
      'pubspec.lock',
      'dartitect.json',
      '.dartitect/ecosystem-policy.json',
      '.dartitect/baseline.json',
      '.dartitect/baseline.json.stage',
      '.dartitect/baseline.json.backup',
      '.dartitect/baseline.transaction.json',
    };
    for (final package in await _workspacePackages()) {
      final packagePath = _relativePath(package.path);
      inputs.add(
        packagePath == '.' ? 'pubspec.yaml' : '$packagePath/pubspec.yaml',
      );
      inputs.add(
        packagePath == '.' ? 'dartitect.json' : '$packagePath/dartitect.json',
      );
      for (final directoryName in const <String>[
        'lib',
        'bin',
        'test',
        'integration_test',
        'tool',
      ]) {
        final directory = Directory(_join(package.path, directoryName));
        await _collectDartInputs(directory, inputs);
      }
    }
    return inputs;
  }

  Future<Set<String>> _codexSemanticInputs() async {
    final inputs = <String>{
      '.dartitect-codex-sync.json',
      '.dartitect-codex-backup',
    };
    final skills = Directory(_join(root.path, '.agents/skills'));
    if (await skills.exists()) {
      await for (final entity in skills.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = _relativePath(entity.path);
        final segments = relative.split('/');
        if (segments.length >= 3 && segments[2].startsWith('dartitect-')) {
          inputs.add(relative);
        }
      }
    }
    final backup = Directory(_join(root.path, '.dartitect-codex-backup'));
    if (await backup.exists()) {
      await for (final entity in backup.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) inputs.add(_relativePath(entity.path));
      }
    }
    return inputs;
  }

  Future<Set<String>> _dependencyUpgradeSemanticInputs() async => <String>{
    'pubspec.yaml',
    'pubspec.lock',
    '.dartitect/dependency-upgrade.pubspec.stage',
    '.dartitect/dependency-upgrade.pubspec.backup',
    '.dartitect/dependency-upgrade.transaction.json',
  };

  static const Set<String> _dartitectPackages = <String>{
    'dartitect',
    'dartitect_cli',
    'dartitect_dio',
    'dartitect_drift',
    'dartitect_flutter',
    'dartitect_geometry',
    'dartitect_isolates',
    'dartitect_lints',
    'dartitect_locale_br',
    'dartitect_mcp',
    'dartitect_media',
    'dartitect_objectbox',
    'dartitect_observability',
    'dartitect_privacy',
    'dartitect_sentry',
    'dartitect_sync',
    'dartitect_testing',
  };

  Future<List<Directory>> _workspacePackages() async {
    final packages = <String, Directory>{root.path: root};
    final pubspec = File(_join(root.path, 'pubspec.yaml'));
    if (!await pubspec.exists()) return packages.values.toList();
    var inWorkspace = false;
    for (final line in await pubspec.readAsLines()) {
      if (line.trim() == 'workspace:') {
        inWorkspace = true;
        continue;
      }
      if (inWorkspace && line.isNotEmpty && !line.startsWith(' ')) break;
      final match = inWorkspace
          ? RegExp(r'^\s*-\s+([^#]+?)\s*$').firstMatch(line)
          : null;
      final pattern = match
          ?.group(1)
          ?.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      if (pattern == null) continue;
      if (pattern.endsWith('/*')) {
        final parent = Directory(
          _join(root.path, pattern.substring(0, pattern.length - 2)),
        );
        if (!await parent.exists()) continue;
        await for (final child in parent.list(followLinks: false)) {
          if (child is Directory &&
              await File(_join(child.path, 'pubspec.yaml')).exists()) {
            packages[child.absolute.path] = child.absolute;
          }
        }
      } else {
        final package = Directory(_join(root.path, pattern));
        if (await File(_join(package.path, 'pubspec.yaml')).exists()) {
          packages[package.absolute.path] = package.absolute;
        }
      }
    }
    final result = packages.values.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    return result;
  }

  Future<void> _collectDartInputs(
    Directory directory,
    Set<String> inputs,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        inputs.add(_relativePath(entity.path));
      } else if (entity is Directory) {
        final name = entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        if (const <String>{
          '.dart_tool',
          '.git',
          '.symlinks',
          'build',
          'ephemeral',
          'Pods',
        }.contains(name)) {
          continue;
        }
        if (await File(_join(entity.path, 'pubspec.yaml')).exists()) continue;
        await _collectDartInputs(entity, inputs);
      }
    }
  }

  String _relativePath(String path) {
    final absolute = File(path).absolute.path;
    if (absolute == root.path) return '.';
    return absolute
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
