import 'dart:io';

import 'generated_release_manifest.dart';

/// One installed Dartitect package outside its declared compatible range.
final class DartitectLockIncompatibility {
  /// Creates an incompatibility from one lockfile entry.
  const DartitectLockIncompatibility({
    required this.package,
    required this.version,
    required this.expectedRange,
  });

  /// Resolved package name.
  final String package;

  /// Resolved semantic version.
  final String version;

  /// Range declared by the generated compatibility manifest.
  final String expectedRange;
}

/// Validates resolved packages against the generated compatibility manifest.
abstract final class DartitectLockCompatibility {
  /// Returns incompatible Dartitect entries from [lockfile].
  static Future<List<DartitectLockIncompatibility>> inspect(
    File lockfile,
  ) async {
    if (!await lockfile.exists()) return const <DartitectLockIncompatibility>[];
    final resolved = _resolvedVersions(await lockfile.readAsString());
    final findings = <DartitectLockIncompatibility>[];
    for (final entry in resolved.entries) {
      final expected = DartitectReleaseManifest.compatibleRanges[entry.key];
      if (expected == null || !_contains(expected, entry.value)) {
        findings.add(
          DartitectLockIncompatibility(
            package: entry.key,
            version: entry.value,
            expectedRange: expected ?? 'not present in the release manifest',
          ),
        );
      }
    }
    findings.sort((left, right) => left.package.compareTo(right.package));
    return findings;
  }

  static Map<String, String> _resolvedVersions(String source) {
    final versions = <String, String>{};
    String? current;
    for (final line in source.split(RegExp(r'\r?\n'))) {
      final package = RegExp(r'^  (dartitect(?:_[A-Za-z0-9_]+)?):\s*$')
          .firstMatch(line);
      if (package != null) {
        current = package.group(1);
        continue;
      }
      if (current == null) continue;
      final version = RegExp(r'''^    version:\s*['"]?([^'"\s]+)['"]?\s*$''')
          .firstMatch(line);
      if (version != null) {
        versions[current] = version.group(1)!;
        current = null;
      } else if (line.isNotEmpty && !line.startsWith('    ')) {
        current = null;
      }
    }
    return versions;
  }

  static bool _contains(String range, String version) {
    final match = RegExp(r'^>=([^\s]+) <([^\s]+)$').firstMatch(range);
    final candidate = _Version.tryParse(version);
    final lower = _Version.tryParse(match?.group(1));
    final upper = _Version.tryParse(match?.group(2));
    return match != null &&
        candidate != null &&
        lower != null &&
        upper != null &&
        candidate.compareTo(lower) >= 0 &&
        candidate.compareTo(upper) < 0;
  }
}

final class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch, this.prerelease);

  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;

  static _Version? tryParse(String? source) {
    if (source == null) return null;
    final match = RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?$',
    ).firstMatch(source);
    if (match == null) return null;
    return _Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4)?.split('.') ?? const <String>[],
    );
  }

  @override
  int compareTo(_Version other) {
    for (final comparison in <int>[
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ]) {
      if (comparison != 0) return comparison;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      return prerelease.isEmpty == other.prerelease.isEmpty
          ? 0
          : prerelease.isEmpty
          ? 1
          : -1;
    }
    final length = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var index = 0; index < length; index += 1) {
      final left = prerelease[index];
      final right = other.prerelease[index];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      final comparison = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftNumber != null
          ? -1
          : rightNumber != null
          ? 1
          : left.compareTo(right);
      if (comparison != 0) return comparison;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}
