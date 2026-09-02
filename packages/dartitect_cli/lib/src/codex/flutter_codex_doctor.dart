import 'dart:convert';
import 'dart:io';

import 'codex_skill_synchronizer.dart';
import 'skill_catalog.dart';

/// Status of one offline Codex/Flutter doctor check.
enum FlutterCodexCheckStatus {
  /// The check is fully evidenced.
  pass,

  /// The check has a non-blocking or unproved condition.
  warning,

  /// The check found a blocking invalid condition.
  fail,

  /// The check records external state without validating it.
  informational,
}

/// One payload-free doctor check.
final class FlutterCodexCheck {
  /// Creates a check.
  const FlutterCodexCheck({
    required this.id,
    required this.status,
    required this.evidence,
  });

  /// Stable check identifier.
  final String id;

  /// Check status.
  final FlutterCodexCheckStatus status;

  /// Local, payload-free evidence.
  final List<String> evidence;

  /// JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'status': status.name,
    'evidence': evidence,
  };
}

/// Complete result for the Flutter-specific Codex doctor.
final class FlutterCodexDoctorReport {
  /// Creates a report.
  FlutterCodexDoctorReport(this.checks)
    : overallStatus =
          checks.any((check) => check.status == FlutterCodexCheckStatus.fail)
          ? FlutterCodexCheckStatus.fail
          : checks.any(
              (check) => check.status == FlutterCodexCheckStatus.warning,
            )
          ? FlutterCodexCheckStatus.warning
          : FlutterCodexCheckStatus.pass;

  /// Ordered checks.
  final List<FlutterCodexCheck> checks;

  /// Aggregate status.
  final FlutterCodexCheckStatus overallStatus;

  /// Process status.
  int get exitCode => overallStatus == FlutterCodexCheckStatus.fail ? 1 : 0;

  /// Stable JSON document.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'command': 'codex doctor --flutter',
    'checks': checks.map((check) => check.toJson()).toList(),
    'overallStatus': overallStatus.name,
    'exitCode': exitCode,
  };
}

/// Captured local command result.
final class FlutterCodexCommandResult {
  /// Creates a result.
  const FlutterCodexCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  /// Process exit status.
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;
}

/// Injectable local command boundary.
typedef FlutterCodexCommandRunner = Future<FlutterCodexCommandResult> Function(
  String executable,
  List<String> arguments,
);

/// Offline doctor for Flutter's official Codex plugin and Dartitect skills.
final class FlutterCodexDoctor {
  /// Creates a doctor confined to [root].
  FlutterCodexDoctor(
    Directory root, {
    FlutterCodexCommandRunner? commandRunner,
    Map<String, String>? environment,
  }) : root = root.absolute,
       _commandRunner = commandRunner ?? _run,
       _environment = environment ?? Platform.environment;

  /// Consumer workspace.
  final Directory root;
  final FlutterCodexCommandRunner _commandRunner;
  final Map<String, String> _environment;

  /// Runs read-only, offline checks.
  Future<FlutterCodexDoctorReport> inspect() async {
    final checks = <FlutterCodexCheck>[
      await _toolCheck('flutter', const <String>['--version', '--machine']),
      await _toolCheck('dart', const <String>['--version']),
      await _mcpCheck(),
      await _toolCheck('codex', const <String>['--version']),
    ];
    final plugin = await _pluginEvidence();
    checks
      ..add(plugin.check)
      ..add(await _officialSkillsCheck(plugin))
      ..add(await _journalCheck())
      ..add(await _managedSkillsCheck())
      ..add(await _codexConfigCheck())
      ..add(await _vscodeCheck());
    return FlutterCodexDoctorReport(
      List<FlutterCodexCheck>.unmodifiable(checks),
    );
  }

  Future<FlutterCodexCheck> _toolCheck(
    String executable,
    List<String> arguments,
  ) async {
    final result = await _commandRunner(executable, arguments);
    return FlutterCodexCheck(
      id: executable,
      status: result.exitCode == 0
          ? FlutterCodexCheckStatus.pass
          : FlutterCodexCheckStatus.fail,
      evidence: <String>[
        result.exitCode == 0
            ? '$executable is available.'
            : '$executable is unavailable (exit ${result.exitCode}).',
      ],
    );
  }

  Future<FlutterCodexCheck> _mcpCheck() async {
    final result = await _commandRunner('dart', const <String>[
      '--suppress-analytics',
      'help',
      'mcp-server',
    ]);
    final identified =
        result.exitCode == 0 ||
        result.stdout.contains('dart mcp-server') ||
        result.stderr.contains('dart mcp-server');
    return FlutterCodexCheck(
      id: 'dartMcpServer',
      status: identified
          ? FlutterCodexCheckStatus.pass
          : FlutterCodexCheckStatus.warning,
      evidence: <String>[
        identified
            ? 'dart mcp-server is available.'
            : 'dart mcp-server availability could not be proved offline.',
      ],
    );
  }

  Future<_PluginEvidence> _pluginEvidence() async {
    final structured = await _commandRunner('codex', const <String>[
      'plugin',
      'list',
      '--json',
    ]);
    if (structured.exitCode == 0) {
      try {
        final decoded = jsonDecode(structured.stdout);
        final tokens = _flattenStrings(decoded).toSet();
        final installed =
            tokens.contains('dart-flutter@dart-flutter') ||
            (tokens.contains('dart-flutter') &&
                _installedCollectionContains(decoded, 'dart-flutter'));
        return _PluginEvidence(
          installed: installed,
          tokens: tokens,
          check: FlutterCodexCheck(
            id: 'officialPlugin',
            status: installed
                ? FlutterCodexCheckStatus.pass
                : FlutterCodexCheckStatus.warning,
            evidence: <String>[
              installed
                  ? 'Installed plugin dart-flutter@dart-flutter was identified structurally.'
                  : 'Plugin dart-flutter@dart-flutter is absent; run codex plugin add dart-flutter@dart-flutter manually.',
            ],
          ),
        );
      } on FormatException {
        // Fall through to the exact text compatibility path.
      }
    }
    final text = await _commandRunner('codex', const <String>[
      'plugin',
      'list',
    ]);
    final installed =
        text.exitCode == 0 &&
        text.stdout
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .contains('dart-flutter@dart-flutter');
    return _PluginEvidence(
      installed: installed,
      tokens: const <String>{},
      check: FlutterCodexCheck(
        id: 'officialPlugin',
        status: FlutterCodexCheckStatus.warning,
        evidence: <String>[
          installed
              ? 'Plugin dart-flutter@dart-flutter was identified by an exact legacy text line; structured proof is unavailable.'
              : 'Structured plugin output is unsupported and exact legacy text did not prove dart-flutter@dart-flutter; run codex plugin add dart-flutter@dart-flutter manually if absent.',
        ],
      ),
    );
  }

  Future<FlutterCodexCheck> _officialSkillsCheck(_PluginEvidence plugin) async {
    final found = <String>{
      for (final skill in officialFlutterQualitySkills)
        if (plugin.tokens.contains(skill)) skill,
    };
    if (found.length != officialFlutterQualitySkills.length &&
        plugin.installed) {
      found.addAll(await _skillsOnDisk());
    }
    final missing = officialFlutterQualitySkills
        .where((skill) => !found.contains(skill))
        .toList();
    return FlutterCodexCheck(
      id: 'officialSkills',
      status: missing.isEmpty
          ? FlutterCodexCheckStatus.pass
          : FlutterCodexCheckStatus.warning,
      evidence: <String>[
        '${found.length}/${officialFlutterQualitySkills.length} official Flutter quality skills proved.',
        if (missing.isNotEmpty) 'Not proved: ${missing.join(', ')}.',
      ],
    );
  }

  Future<Set<String>> _skillsOnDisk() async {
    final codexHome =
        _environment['CODEX_HOME'] ??
        (_environment['HOME'] == null
            ? null
            : _join(_environment['HOME']!, '.codex'));
    if (codexHome == null) return const <String>{};
    final plugins = Directory(_join(codexHome, 'plugins'));
    if (!await plugins.exists()) return const <String>{};
    final found = <String>{};
    var inspected = 0;
    await for (final entity in plugins.list(
      recursive: true,
      followLinks: false,
    )) {
      if (++inspected > 10000) break;
      if (entity is! Directory) continue;
      final name = _basename(entity.path);
      if (officialFlutterQualitySkills.contains(name)) found.add(name);
    }
    return found;
  }

  Future<FlutterCodexCheck> _managedSkillsCheck() async {
    final journal = File(_join(root.path, '.dartitect-codex-sync.json'));
    final backup = Directory(_join(root.path, '.dartitect-codex-backup'));
    if (await journal.exists() || await backup.exists()) {
      return const FlutterCodexCheck(
        id: 'dartitectSkills',
        status: FlutterCodexCheckStatus.warning,
        evidence: <String>[
          'Managed skill hashes are deferred until the interrupted transaction is recovered.',
        ],
      );
    }
    try {
      final preview = await CodexSkillSynchronizer(root).preview();
      final noOps = preview.operations
          .where((operation) => operation.startsWith('NO-OP '))
          .length;
      return FlutterCodexCheck(
        id: 'dartitectSkills',
        status: noOps == dartitectSkillCatalog.length
            ? FlutterCodexCheckStatus.pass
            : FlutterCodexCheckStatus.warning,
        evidence: <String>[
          '$noOps/${dartitectSkillCatalog.length} managed Dartitect skills match manifests and hashes.',
        ],
      );
    } on Object catch (error) {
      return FlutterCodexCheck(
        id: 'dartitectSkills',
        status: FlutterCodexCheckStatus.fail,
        evidence: <String>[
          'Managed skill validation failed: ${_safeError(error)}.',
        ],
      );
    }
  }

  Future<FlutterCodexCheck> _journalCheck() async {
    final journal = File(_join(root.path, '.dartitect-codex-sync.json'));
    final backup = Directory(_join(root.path, '.dartitect-codex-backup'));
    if (!await journal.exists() && !await backup.exists()) {
      return const FlutterCodexCheck(
        id: 'transactionJournal',
        status: FlutterCodexCheckStatus.pass,
        evidence: <String>[
          'No interrupted Dartitect skill transaction exists.',
        ],
      );
    }
    if (!await journal.exists() || !await backup.exists()) {
      return const FlutterCodexCheck(
        id: 'transactionJournal',
        status: FlutterCodexCheckStatus.fail,
        evidence: <String>['The transaction journal or backup is orphaned.'],
      );
    }
    try {
      final value = jsonDecode(await journal.readAsString());
      final valid =
          value is Map<String, Object?> &&
          value['schemaVersion'] == 1 &&
          value['phase'] == 'staged' &&
          value['skills'] is List<Object?> &&
          (value['skills']! as List<Object?>).every(
            (name) => name is String && dartitectSkillNames.contains(name),
          );
      return FlutterCodexCheck(
        id: 'transactionJournal',
        status: valid
            ? FlutterCodexCheckStatus.warning
            : FlutterCodexCheckStatus.fail,
        evidence: <String>[
          valid
              ? 'A recoverable interrupted Dartitect skill transaction exists.'
              : 'The interrupted transaction journal is invalid.',
        ],
      );
    } on FormatException {
      return const FlutterCodexCheck(
        id: 'transactionJournal',
        status: FlutterCodexCheckStatus.fail,
        evidence: <String>[
          'The interrupted transaction journal is invalid JSON.',
        ],
      );
    }
  }

  Future<FlutterCodexCheck> _codexConfigCheck() async {
    final config = File(_join(root.path, '.codex/config.toml'));
    if (!await config.exists()) {
      return const FlutterCodexCheck(
        id: 'workspaceCodexConfig',
        status: FlutterCodexCheckStatus.pass,
        evidence: <String>['No optional workspace .codex/config.toml exists.'],
      );
    }
    final source = await config.readAsString();
    final valid =
        source.trim().isNotEmpty &&
        !source.contains('\u0000') &&
        source
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .every(
              (line) =>
                  (line.startsWith('[') && line.endsWith(']')) ||
                  line.contains('='),
            );
    return FlutterCodexCheck(
      id: 'workspaceCodexConfig',
      status: valid
          ? FlutterCodexCheckStatus.pass
          : FlutterCodexCheckStatus.fail,
      evidence: <String>[
        valid
            ? 'Workspace .codex/config.toml has a valid structural shape.'
            : 'Workspace .codex/config.toml is structurally invalid.',
      ],
    );
  }

  Future<FlutterCodexCheck> _vscodeCheck() async {
    final exists = await File(_join(root.path, '.vscode/mcp.json')).exists();
    return FlutterCodexCheck(
      id: 'externalEditorMcp',
      status: FlutterCodexCheckStatus.informational,
      evidence: <String>[
        exists
            ? '.vscode/mcp.json exists as external editor configuration; it was not validated or modified.'
            : 'No external .vscode/mcp.json was observed.',
      ],
    );
  }

  static Future<FlutterCodexCommandResult> _run(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(executable, arguments);
      return FlutterCodexCommandResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    } on ProcessException catch (error) {
      return FlutterCodexCommandResult(exitCode: 127, stderr: error.message);
    }
  }

  static bool _installedCollectionContains(Object? value, String name) {
    if (value is! Map<Object?, Object?> ||
        value['installed'] is! List<Object?>) {
      return false;
    }
    return (value['installed']! as List<Object?>).any(
      (entry) => _flattenStrings(entry).contains(name),
    );
  }

  static Iterable<String> _flattenStrings(Object? value) sync* {
    if (value is String) {
      yield value;
    } else if (value is List<Object?>) {
      for (final item in value) {
        yield* _flattenStrings(item);
      }
    } else if (value is Map<Object?, Object?>) {
      for (final item in value.values) {
        yield* _flattenStrings(item);
      }
    }
  }

  static String _safeError(Object error) {
    final message = error is FileSystemException ? error.message : '$error';
    return message.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}

final class _PluginEvidence {
  const _PluginEvidence({
    required this.installed,
    required this.tokens,
    required this.check,
  });

  final bool installed;
  final Set<String> tokens;
  final FlutterCodexCheck check;
}

/// Official Flutter skills orchestrated by Dartitect without copied content.
const officialFlutterQualitySkills = <String>[
  'flutter-add-integration-test',
  'flutter-add-widget-preview',
  'flutter-add-widget-test',
  'flutter-apply-architecture-best-practices',
  'flutter-build-responsive-layout',
  'flutter-fix-layout-issues',
];

/// Expected managed skill names.
final Set<String> dartitectSkillNames = dartitectSkillCatalog
    .map((skill) => skill.name)
    .toSet();
