import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../codex/codex_skill_synchronizer.dart';
import '../codex/skill_catalog.dart';
import '../config/dartitect_config.dart';
import '../diagnostics/models.dart';
import '../generation/generation_engine.dart';
import '../generation/scaffolds.dart';
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
}

/// A validated, read-only preview of one supported project change.
final class DartitectChangePlan {
  /// Creates a change plan.
  const DartitectChangePlan({
    required this.kind,
    required this.operations,
    required this.preview,
    required this.stateToken,
    this.overwriteManaged = false,
  });

  /// Change category.
  final DartitectChangeKind kind;

  /// Deterministic project-relative operations.
  final List<String> operations;

  /// Sanitized human-readable preview.
  final String preview;

  /// Opaque fingerprint used to reject stale plans.
  final String stateToken;

  /// Whether locally changed managed Codex skills may be replaced.
  final bool overwriteManaged;

  /// Stable representation that intentionally omits the internal state token.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'operations': operations,
    'preview': preview,
    'overwriteManaged': overwriteManaged,
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

  /// Applied change category.
  final DartitectChangeKind kind;

  /// Deterministic project-relative operations.
  final List<String> operations;

  /// Whether the filesystem changed.
  final bool changed;

  /// Stable machine-readable representation.
  Map<String, Object?> toJson() => <String, Object?>{
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

  /// Returns consolidated project metadata and architecture findings.
  Future<CommandEnvelope> inspectProject() => _readOnly('inspect');

  /// Scans architecture boundaries, optionally applying the reviewed baseline.
  Future<CommandEnvelope> scanArchitecture({bool useBaseline = true}) =>
      _readOnly('scan', useBaseline: useBaseline);

  /// Validates configuration, toolchain, skills, and optional analyzer state.
  Future<CommandEnvelope> doctorProject({bool deep = false}) =>
      _readOnly('doctor', deep: deep);

  /// Builds an incremental, non-mutating adoption recommendation.
  Future<Map<String, Object?>> planAdoption() async {
    final report = await scanArchitecture(useBaseline: false);
    final dependencies =
        (report.project['dependencies'] as List<Object?>?)
            ?.whereType<String>()
            .toSet() ??
        <String>{};
    final capabilities = report.capabilities.toSet();
    final steps = <Map<String, Object?>>[
      if (!dependencies.contains('dartitect'))
        const <String, Object?>{
          'order': 1,
          'action': 'add_core',
          'summary': 'Add dartitect and introduce typed Result boundaries.',
        },
      if (!capabilities.contains('explicit_composition'))
        const <String, Object?>{
          'order': 2,
          'action': 'map_ownership',
          'summary':
              'Create an explicit composition root and record owned resources.',
        },
      if (!dependencies.contains('dartitect_observability'))
        const <String, Object?>{
          'order': 3,
          'action': 'add_observability',
          'summary': 'Add local-first, sanitized observability before provider adapters.',
        },
      const <String, Object?>{
        'order': 4,
        'action': 'review_findings',
        'summary': 'Resolve new findings and baseline only reviewed pre-existing debt.',
      },
    ];
    return <String, Object?>{
      'schemaVersion': 1,
      'project': report.project,
      'steps': steps,
      'violationCount': report.violations.length,
      'findingCount': report.findings.length,
    };
  }

  /// Produces a read-only plan for [kind].
  Future<DartitectChangePlan> previewChange(
    DartitectChangeKind kind, {
    bool overwriteManaged = false,
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
    };
  }

  /// Revalidates and commits a previously returned [plan].
  Future<DartitectChangeReceipt> applyChange(DartitectChangePlan plan) async {
    final current = await previewChange(
      plan.kind,
      overwriteManaged: plan.overwriteManaged,
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
          changed: result.operations.any((value) => !value.startsWith('NO-OP')),
        );
    }
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
    return DartitectChangePlan(
      kind: DartitectChangeKind.init,
      operations: List<String>.unmodifiable(operations),
      preview: preview,
      stateToken: await _stateToken('$operations\u0000$preview'),
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
    return DartitectChangePlan(
      kind: DartitectChangeKind.baseline,
      operations: <String>[operation],
      preview: content,
      stateToken: await _stateToken('${current ?? '<missing>'}\u0000$content'),
    );
  }

  Future<DartitectChangePlan> _previewCodexSync({
    required bool overwriteManaged,
  }) async {
    final result = await CodexSkillSynchronizer(root)
        .preview(overwriteManaged: overwriteManaged);
    final operations = List<String>.unmodifiable(result.operations);
    final preview = '${operations.join('\n')}\n';
    return DartitectChangePlan(
      kind: DartitectChangeKind.codexSync,
      operations: operations,
      preview: preview,
      stateToken: await _stateToken(preview),
      overwriteManaged: overwriteManaged,
    );
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

  Future<String> _stateToken(String semanticState) async {
    final entries = await root
        .list(recursive: true, followLinks: false)
        .where((entity) => !_ignoredStatePath(entity.path))
        .toList();
    entries.sort((left, right) => left.path.compareTo(right.path));
    var hash = _hashBytes(utf8.encode(semanticState));
    for (final entity in entries) {
      final relative = entity.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      if (entity is File) {
        hash = _hashBytes(utf8.encode('F\u0000$relative\u0000'), seed: hash);
        await for (final bytes in entity.openRead()) {
          hash = _hashBytes(bytes, seed: hash);
        }
      } else if (entity is Link) {
        final target = await entity.target();
        hash = _hashBytes(
          utf8.encode('L\u0000$relative\u0000$target\u0000'),
          seed: hash,
        );
      }
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  bool _ignoredStatePath(String path) {
    final relative = path
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    return relative == '.dartitect/mcp.lock' ||
        relative == '.dartitect-generation.json' ||
        relative == '.dartitect-codex-sync.json' ||
        relative.startsWith('.git/') ||
        relative.startsWith('.dart_tool/') ||
        relative.startsWith('build/') ||
        relative.startsWith('docs/api/');
  }

  static int _hashBytes(List<int> bytes, {int seed = 0x811c9dc5}) {
    var hash = seed;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
