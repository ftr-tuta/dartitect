import 'dart:convert';

/// Compatibility impact of a public API change.
enum ApiCompatibilityKind {
  none,
  additive,
  deprecated,
  breaking;

  int get severity => switch (this) {
    none => 0,
    additive => 1,
    deprecated => 2,
    breaking => 3,
  };
}

/// One deterministic public API difference.
final class ApiDifference {
  const ApiDifference({
    required this.kind,
    required this.path,
    required this.message,
  });

  final ApiCompatibilityKind kind;
  final String path;
  final String message;
}

/// Classifies semantic snapshot changes without relying on source formatting.
List<ApiDifference> classifyApiDiff(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final differences = <ApiDifference>[];
  final oldSymbols = _flatten(before);
  final newSymbols = _flatten(after);
  final paths = <String>{...oldSymbols.keys, ...newSymbols.keys}.toList()
    ..sort();
  for (final path in paths) {
    final oldValue = oldSymbols[path];
    final newValue = newSymbols[path];
    if (oldValue == null) {
      differences.add(
        ApiDifference(
          kind: ApiCompatibilityKind.additive,
          path: path,
          message: 'Public declaration was added.',
        ),
      );
      continue;
    }
    if (newValue == null) {
      differences.add(
        ApiDifference(
          kind: ApiCompatibilityKind.breaking,
          path: path,
          message: 'Public declaration was removed.',
        ),
      );
      continue;
    }
    if (_canonical(oldValue) == _canonical(newValue)) continue;
    final oldDeprecated = oldValue['deprecated'] == true;
    final newDeprecated = newValue['deprecated'] == true;
    final kind = !oldDeprecated && newDeprecated
        ? ApiCompatibilityKind.deprecated
        : ApiCompatibilityKind.breaking;
    differences.add(
      ApiDifference(
        kind: kind,
        path: path,
        message: kind == ApiCompatibilityKind.deprecated
            ? 'Public declaration was deprecated.'
            : 'Public signature, audience, annotation, or modifier changed.',
      ),
    );
  }
  return differences;
}

/// Returns whether [nextVersion] is sufficient for [change].
bool validatesApiVersion(
  String previousVersion,
  String nextVersion,
  ApiCompatibilityKind change,
) {
  if (change == ApiCompatibilityKind.none) return true;
  final previous = _SemanticVersion.parse(previousVersion);
  final next = _SemanticVersion.parse(nextVersion);
  if (next.compareTo(previous) <= 0) return false;
  if (previous.preRelease != null || next.preRelease != null) return true;
  if (next.major > previous.major) return true;
  if (next.major != previous.major) return false;
  if (next.minor > previous.minor) {
    return change != ApiCompatibilityKind.breaking;
  }
  if (next.minor != previous.minor || next.patch <= previous.patch) {
    return false;
  }
  return change == ApiCompatibilityKind.deprecated;
}

ApiCompatibilityKind maximumApiChange(Iterable<ApiDifference> differences) {
  var result = ApiCompatibilityKind.none;
  for (final difference in differences) {
    if (difference.kind.severity > result.severity) result = difference.kind;
  }
  return result;
}

Map<String, Map<String, Object?>> _flatten(Map<String, Object?> snapshot) {
  final output = <String, Map<String, Object?>>{};
  final entrypoints = snapshot['entrypoints'];
  if (entrypoints is! Map<String, Object?>) return output;
  for (final entrypoint in entrypoints.entries) {
    final body = entrypoint.value;
    if (body is! Map<String, Object?>) continue;
    final symbols = body['symbols'];
    if (symbols is! List<Object?>) continue;
    for (final value in symbols.whereType<Map<String, Object?>>()) {
      final name = value['name'];
      if (name is! String) continue;
      final symbolPath = '${entrypoint.key}::$name';
      final symbol = Map<String, Object?>.from(value)..remove('members');
      output[symbolPath] = symbol;
      final members = value['members'];
      if (members is! List<Object?>) continue;
      for (final member in members.whereType<Map<String, Object?>>()) {
        final kind = member['kind'];
        final memberName = member['name'];
        if (kind is String && memberName is String) {
          output['$symbolPath::$kind::$memberName'] = member;
        }
      }
    }
  }
  return output;
}

String _canonical(Object? value) => jsonEncode(value);

final class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.major, this.minor, this.patch, this.preRelease);

  factory _SemanticVersion.parse(String source) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(source);
    if (match == null)
      throw FormatException('Invalid semantic version: $source');
    return _SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4),
    );
  }

  final int major;
  final int minor;
  final int patch;
  final String? preRelease;

  @override
  int compareTo(_SemanticVersion other) {
    for (final comparison in <int>[
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ]) {
      if (comparison != 0) return comparison;
    }
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease == null) return -1;
    return _comparePreRelease(preRelease ?? '', other.preRelease ?? '');
  }
}

int _comparePreRelease(String left, String right) {
  final leftParts = left.split('.');
  final rightParts = right.split('.');
  final length = leftParts.length < rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index += 1) {
    final leftNumber = int.tryParse(leftParts[index]);
    final rightNumber = int.tryParse(rightParts[index]);
    final comparison = switch ((leftNumber, rightNumber)) {
      (final int left, final int right) => left.compareTo(right),
      (final int _, null) => -1,
      (null, final int _) => 1,
      (null, null) => leftParts[index].compareTo(rightParts[index]),
    };
    if (comparison != 0) return comparison;
  }
  return leftParts.length.compareTo(rightParts.length);
}
