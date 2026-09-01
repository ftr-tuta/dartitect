import 'dart:convert';
import 'dart:io';

final class ReleaseCohortContract {
  ReleaseCohortContract._(this.source)
    : workspace = ReleaseCohort.fromJson(
        _object(source['workspaceCohort'], 'workspaceCohort'),
        tagKey: 'derivedTag',
      ),
      distributed = ReleaseCohort.fromJson(
        _object(source['distributedCohort'], 'distributedCohort'),
        tagKey: 'tag',
      );

  factory ReleaseCohortContract.read(Directory root) {
    final value = jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    );
    return ReleaseCohortContract._(_object(value, 'package release contract'));
  }

  final Map<String, Object?> source;
  final ReleaseCohort workspace;
  final ReleaseCohort distributed;

  Map<String, Object?> get packages => _object(source['packages'], 'packages');

  Map<String, Object?> get packagePaths =>
      _object(source['packagePaths'], 'packagePaths');

  List<String> get dependencyOrder {
    final value = source['dependencyOrder'];
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      throw const FormatException('dependencyOrder must be a string list.');
    }
    return value.cast<String>();
  }

  Map<String, Object?> get workspaceDependency => _object(
    source['workspaceInternalDependency'],
    'workspaceInternalDependency',
  );

  Map<String, Object?> get distributedDependency => _object(
    source['distributedInternalDependency'],
    'distributedInternalDependency',
  );
}

final class ReleaseCohort {
  const ReleaseCohort({
    required this.version,
    required this.semanticVersion,
    required this.channel,
    required this.tag,
    required this.available,
    required this.tagMaterialized,
  });

  factory ReleaseCohort.fromJson(
    Map<String, Object?> source, {
    required String tagKey,
  }) {
    final version = source['version'];
    final channel = source['channel'];
    final tag = source[tagKey];
    if (version is! String || channel is! String || tag is! String) {
      throw FormatException('Invalid cohort fields for $tagKey.');
    }
    return ReleaseCohort(
      version: version,
      semanticVersion: SemanticVersion.parse(version),
      channel: channel,
      tag: tag,
      available: source['available'] == true,
      tagMaterialized: source['tagMaterialized'] == true,
    );
  }

  final String version;
  final SemanticVersion semanticVersion;
  final String channel;
  final String tag;
  final bool available;
  final bool tagMaterialized;

  bool get isPrerelease => semanticVersion.prerelease != null;
}

final class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion._(this.major, this.minor, this.patch, this.prerelease);

  factory SemanticVersion.parse(String source) {
    final match = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(source);
    if (match == null) {
      throw FormatException('Invalid semantic version: $source.');
    }
    final prerelease = match.group(4);
    if (prerelease != null &&
        prerelease
            .split('.')
            .any(
              (part) =>
                  RegExp(r'^\d+$').hasMatch(part) &&
                  part.length > 1 &&
                  part.startsWith('0'),
            )) {
      throw FormatException(
        'Numeric prerelease identifiers cannot have leading zeroes: $source.',
      );
    }
    return SemanticVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      prerelease,
    );
  }

  final int major;
  final int minor;
  final int patch;
  final String? prerelease;

  @override
  int compareTo(SemanticVersion other) {
    for (final comparison in <int>[
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ]) {
      if (comparison != 0) return comparison;
    }
    if (prerelease == null && other.prerelease == null) return 0;
    if (prerelease == null) return 1;
    if (other.prerelease == null) return -1;
    final left = prerelease!.split('.');
    final right = other.prerelease!.split('.');
    for (var index = 0; index < left.length && index < right.length; index++) {
      final leftNumber = int.tryParse(left[index]);
      final rightNumber = int.tryParse(right[index]);
      final comparison = switch ((leftNumber, rightNumber)) {
        (final int leftValue, final int rightValue) => leftValue.compareTo(
          rightValue,
        ),
        (final int _, null) => -1,
        (null, final int _) => 1,
        _ => left[index].compareTo(right[index]),
      };
      if (comparison != 0) return comparison;
    }
    return left.length.compareTo(right.length);
  }
}

Map<String, Object?> releaseObject(Object? value, String label) =>
    _object(value, label);

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must be a JSON object.');
  }
  return value;
}
