import 'dart:io';

import '../config/dartitect_config.dart';
import '../diagnostics/models.dart';
import '../model/model_generator.dart';
import '../policy/ecosystem_policy.dart';
import '../project/dartitect_project_service.dart';

/// Read-only RC8 verification shared by the public CLI, fleet, and MCP server.
final class DartitectVerificationService {
  /// Creates a verifier for one package or workspace root.
  DartitectVerificationService(Directory root) : root = root.absolute;

  /// Root inspected by this service. Reports never expose its absolute path.
  final Directory root;

  /// Verifies architecture, opt-in modeling, and ecosystem/provider status.
  ///
  /// This method never recovers journals, creates manifests, formats sources,
  /// or invokes a mutating generator path.
  Future<CommandEnvelope> verify() async {
    final architecture = await DartitectProjectService(root)
        .scanArchitecture(useBaseline: false);
    final findings = <DartitectFinding>[...architecture.findings];
    final violations = <DartitectFinding>[...architecture.violations];

    final config = await _config();
    final modelingEnabled =
        config?.modeling != null || await _declaresModelingDependency();
    ModelGenerationReport? modelReport;
    if (modelingEnabled) {
      modelReport = await DartitectModelGenerator(root).inspect();
      for (final diagnostic in modelReport.findings) {
        findings.add(
          DartitectFinding(
            code: diagnostic.code,
            severity: switch (diagnostic.severity.name) {
              'info' => FindingSeverity.info,
              'warning' => FindingSeverity.warning,
              _ => FindingSeverity.error,
            },
            message: diagnostic.message,
            path: diagnostic.path,
            line: diagnostic.line,
            remediation: diagnostic.fixId == null
                ? null
                : 'Apply reviewed semantic fix ${diagnostic.fixId}.',
          ),
        );
      }
    }

    final ecosystem = await EcosystemDependencyAuditor(
      root,
      await EcosystemPolicy.load(root),
    ).audit();
    findings.sort(_compareFinding);
    violations.sort(_compareFinding);
    final providerStatus = _providerStatus(ecosystem, violations);
    final featureStatus = _featureStatus(config);
    final project = <String, Object?>{
      ...architecture.project,
      'modelStatus': <String, Object?>{
        'configured': config?.modeling != null,
        if (config?.modeling case final modeling?)
          'preset': modeling.preset.wireName,
        'enabled': modelingEnabled,
        'status': !modelingEnabled
            ? 'not_adopted'
            : modelReport!.isFresh
            ? 'fresh'
            : 'findings',
        'fresh': modelReport?.isFresh ?? true,
        'pendingRecovery': modelReport?.plan?.pendingRecovery ?? false,
        'operationCount': modelReport?.plan?.operations.length ?? 0,
        'diagnosticCount': modelReport?.findings.length ?? 0,
      },
      'providerStatus': providerStatus,
      'featureStatus': featureStatus,
      'architectureProfile': nativeStrictProfile,
    };
    final hasConcerns = <DartitectFinding>[
      ...findings,
      ...violations,
    ].any((finding) => finding.severity != FindingSeverity.info);
    return CommandEnvelope(
      command: 'verify',
      project: project,
      capabilities: <String>{
        ...architecture.capabilities,
        if (modelingEnabled) 'modeling',
        for (final provider in providerStatus['installed']! as List<Object?>)
          'provider:$provider',
        for (final profile in featureStatus['profiles']! as List<Object?>)
          'profile:$profile',
      }.toList()..sort(),
      findings: List<DartitectFinding>.unmodifiable(findings),
      violations: List<DartitectFinding>.unmodifiable(violations),
      exitCode: hasConcerns ? 1 : 0,
    );
  }

  Future<DartitectConfig?> _config() async {
    final file = File(_join(root.path, 'dartitect.json'));
    return file.existsSync() ? DartitectConfig.load(file) : null;
  }

  Future<bool> _declaresModelingDependency() async {
    final pubspec = File(_join(root.path, 'pubspec.yaml'));
    if (!await pubspec.exists()) return false;
    return RegExp(
      r'^\s{2}(dartitect_modeling|dartitect_modeling_analyzer):\s*',
      multiLine: true,
    ).hasMatch(await pubspec.readAsString());
  }

  static Map<String, Object?> _providerStatus(
    EcosystemAuditReport report,
    List<DartitectFinding> violations,
  ) {
    final installed = <String>[];
    final prohibitedArchitectures = <String>[];
    for (final package in report.packages) {
      final name = package['package'];
      if (name is! String) continue;
      if (_providerPackages.contains(name)) installed.add(name);
      if (package['decision'] == 'prohibited_native_strict') {
        prohibitedArchitectures.add(name);
      }
    }
    installed.sort();
    prohibitedArchitectures.sort();
    final boundaryErrors =
        violations
            .where((finding) => _providerBoundaryRules.contains(finding.code))
            .map((finding) => finding.code)
            .toSet()
            .toList()
          ..sort();
    return <String, Object?>{
      'installed': installed,
      'prohibitedArchitectures': prohibitedArchitectures,
      'ownership': 'consumer_owned',
      'writerPolicy': 'single_writer_no_dual_write',
      'boundaryErrors': boundaryErrors,
      'status': boundaryErrors.isNotEmpty || prohibitedArchitectures.isNotEmpty
          ? 'error'
          : installed.isNotEmpty
          ? 'bounded'
          : 'none',
    };
  }

  static Map<String, Object?> _featureStatus(DartitectConfig? config) {
    final declarations =
        config?.features.declarations ??
        const <String, DartitectFeatureDeclaration>{};
    final profiles =
        declarations.values
            .map((declaration) => declaration.profile.wireName)
            .toSet()
            .toList()
          ..sort();
    final persistence =
        config?.storageContexts.values
            .map((context) => context.provider)
            .toSet()
            .toList() ??
        <String>[];
    persistence.sort();
    final transport =
        config?.transports.values
            .map((binding) => binding.provider)
            .toSet()
            .toList() ??
        <String>[];
    transport.sort();
    return <String, Object?>{
      'configured': config != null,
      'declarationCount': declarations.length,
      'profiles': profiles,
      'persistenceProviders': persistence,
      'transportProviders': transport,
      'headlessSyncCount': declarations.values
          .where((declaration) => declaration.headlessTargets.isNotEmpty)
          .length,
      'status': config == null
          ? 'not_configured'
          : declarations.isEmpty
          ? 'ready'
          : 'compatible',
      'behavioralGuarantees': 'contract_harness_required',
    };
  }

  static int _compareFinding(DartitectFinding left, DartitectFinding right) {
    final path = (left.path ?? '').compareTo(right.path ?? '');
    if (path != 0) return path;
    final line = (left.line ?? 0).compareTo(right.line ?? 0);
    if (line != 0) return line;
    return left.code.compareTo(right.code);
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

  static const Set<String> _providerBoundaryRules = <String>{
    'DT1005',
    'DT1006',
    'DT1009',
    'DT1011',
    'DT1012',
    'DT1013',
  };

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';
}
