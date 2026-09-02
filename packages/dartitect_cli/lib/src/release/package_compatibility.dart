import 'dart:io';

import 'package:yaml/yaml.dart';

import 'generated_release_manifest.dart';

/// One installed Dartitect package outside the canonical Git release graph.
final class DartitectLockIncompatibility {
  /// Creates an incompatibility from one lockfile entry.
  const DartitectLockIncompatibility({
    required this.package,
    required this.version,
    required this.expectedRange,
    required this.reason,
  });

  /// Resolved package name.
  final String package;

  /// Resolved semantic version, or `missing`.
  final String version;

  /// Canonical lockfile expectation retained for stable reporting.
  final String expectedRange;

  /// Exact source invariant that failed.
  final String reason;
}

/// Validates resolved packages against the immutable GitHub release manifest.
abstract final class DartitectLockCompatibility {
  /// Returns non-canonical Dartitect entries from [lockfile].
  static Future<List<DartitectLockIncompatibility>> inspect(
    File lockfile,
  ) async {
    if (!await lockfile.exists()) {
      return const <DartitectLockIncompatibility>[];
    }
    final yaml = loadYaml(await lockfile.readAsString());
    if (yaml is! Map<Object?, Object?>) {
      return const <DartitectLockIncompatibility>[
        DartitectLockIncompatibility(
          package: 'dartitect',
          version: 'missing',
          expectedRange: 'canonical Git lockfile graph',
          reason: 'pubspec.lock is not a YAML map',
        ),
      ];
    }
    final packages = _map(yaml['packages']);
    if (packages == null) return const <DartitectLockIncompatibility>[];
    final developmentWorkspace = _isDevelopmentWorkspace(lockfile.parent);
    final graphVersions = <String>{};
    for (final entry in packages.entries) {
      if (!_isDartitectPackage(entry.key)) continue;
      final locked = _map(entry.value);
      if (developmentWorkspace && locked?['source'] == 'root') continue;
      graphVersions.add('${locked?['version'] ?? 'missing'}');
    }
    final supportedVersions = <String>{
      DartitectReleaseManifest.distributedVersion,
      DartitectReleaseManifest.workspaceVersion,
    };
    final mixedSupportedCohorts =
        graphVersions.length > 1 &&
        graphVersions.every(supportedVersions.contains);
    final expectation =
        graphVersions.length == 1 &&
            graphVersions.single == DartitectReleaseManifest.workspaceVersion
        ? const _LockExpectation.workspace()
        : const _LockExpectation.distributed();
    final findings = <DartitectLockIncompatibility>[];
    final refs = <String, String>{};
    for (final entry in packages.entries) {
      final package = entry.key;
      if (!_isDartitectPackage(package)) continue;
      final locked = _map(entry.value);
      final version = '${locked?['version'] ?? 'missing'}';
      if (developmentWorkspace && locked?['source'] == 'root') continue;
      final expectedPath = DartitectReleaseManifest.packagePaths[package];
      if (expectedPath == null) {
        findings.add(
          _finding(
            package,
            version,
            expectation,
            'package is absent from release manifest',
          ),
        );
        continue;
      }
      if (mixedSupportedCohorts) {
        findings.add(
          _finding(
            package,
            version,
            expectation,
            'versions must use one lockstep cohort',
          ),
        );
      } else if (version != expectation.version) {
        findings.add(
          _finding(
            package,
            version,
            expectation,
            'version must be ${expectation.version}',
          ),
        );
      }
      if (locked?['source'] != 'git') {
        findings.add(
          _finding(package, version, expectation, 'source must be git'),
        );
        continue;
      }
      final description = _map(locked?['description']);
      final resolvedRef = description?['resolved-ref'];
      if (description?['url'] != DartitectReleaseManifest.repository) {
        findings.add(
          _finding(package, version, expectation, 'Git URL is not canonical'),
        );
      }
      if (description?['path'] != expectedPath) {
        findings.add(
          _finding(
            package,
            version,
            expectation,
            'Git path must be $expectedPath',
          ),
        );
      }
      if (description?['tag-pattern'] != DartitectReleaseManifest.tagPattern) {
        findings.add(
          _finding(
            package,
            version,
            expectation,
            'tag-pattern must be ${DartitectReleaseManifest.tagPattern}',
          ),
        );
      }
      if (resolvedRef is! String ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(resolvedRef)) {
        findings.add(
          _finding(
            package,
            version,
            expectation,
            'resolved-ref must be a full Git SHA',
          ),
        );
      } else {
        refs[package] = resolvedRef;
      }
    }
    final uniqueRefs = refs.values.toSet();
    if (uniqueRefs.length > 1) {
      for (final entry in refs.entries) {
        findings.add(
          _finding(
            entry.key,
            expectation.version,
            expectation,
            'resolved-ref ${entry.value} differs from the lockstep graph',
          ),
        );
      }
    }
    findings.sort((left, right) {
      final package = left.package.compareTo(right.package);
      return package != 0 ? package : left.reason.compareTo(right.reason);
    });
    return findings;
  }

  static DartitectLockIncompatibility _finding(
    String package,
    String version,
    _LockExpectation expectation,
    String reason,
  ) => DartitectLockIncompatibility(
    package: package,
    version: version,
    expectedRange: expectation.description,
    reason: reason,
  );

  static bool _isDevelopmentWorkspace(Directory root) =>
      File('${root.path}/tool/distribution_policy.json').existsSync() &&
      File('${root.path}/packages/dartitect/pubspec.yaml').existsSync();
}

final class _LockExpectation {
  const _LockExpectation.distributed()
    : version = DartitectReleaseManifest.distributedVersion,
      description =
          '${DartitectReleaseManifest.distributedVersion} from '
          '${DartitectReleaseManifest.distributedTag}';

  const _LockExpectation.workspace()
    : version = DartitectReleaseManifest.workspaceVersion,
      description =
          'workspace candidate ${DartitectReleaseManifest.workspaceVersion} '
          'from derivable ${DartitectReleaseManifest.candidateTag}';

  final String version;
  final String description;
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map<Object?, Object?>) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key! as String] = entry.value;
  }
  return result;
}

bool _isDartitectPackage(String name) =>
    RegExp(r'^dartitect(?:_[a-z0-9_]+)?$').hasMatch(name);
