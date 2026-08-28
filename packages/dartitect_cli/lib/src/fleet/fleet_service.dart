import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../config/dartitect_config.dart';
import '../policy/ecosystem_policy.dart';
import '../project/dartitect_project_service.dart';
import '../verification/verification_service.dart';

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
  DartitectFleetService(Directory fleetRoot) : fleetRoot = fleetRoot.absolute;

  /// Boundary within which all projects and policy files must resolve.
  final Directory fleetRoot;

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
        'ecosystem': report.project['ecosystem'],
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
      final plan = await DartitectProjectService(project.directory)
          .previewDependencyUpgrade(targetCohort);
      results.add(<String, Object?>{
        'root': project.label,
        'plan': <String, Object?>{
          ...plan.toJson(),
          'stateToken': plan.stateToken,
        },
      });
    }
    return DartitectFleetReport(
      command: 'fleet upgrade --dry-run',
      projects: List<Map<String, Object?>>.unmodifiable(results),
      exitCode: 0,
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
    final overlap =
        packages
            .where(
              (package) =>
                  EcosystemPolicy.bundled.explain(package).decision ==
                  EcosystemDecision.overlapWarning,
            )
            .toList()
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
        'overlap': overlap,
        'ownership': 'consumer_owned',
        'writerPolicy': 'single_writer_no_dual_write',
        'status': overlap.isNotEmpty
            ? 'overlap_warning'
            : providers.isNotEmpty
            ? 'bounded'
            : 'none',
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
    final declarations = config.features?.declarations;
    if (declarations == null || declarations.isEmpty) {
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
    final persistence =
        declarations.values
            .map((declaration) => declaration.persistence)
            .toSet()
            .toList()
          ..sort();
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
            'persistence': entry.value.persistence,
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
