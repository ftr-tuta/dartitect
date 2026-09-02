import 'dart:convert';
import 'dart:io';

import 'release_contract.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    final plan = _VersionPlan.build(options.root, options.version);
    if (plan.updates.isEmpty) {
      stdout.writeln('NO-OP: workspace cohort is already ${options.version}.');
      return;
    }
    stdout..writeln(
      '${options.apply ? 'Applying' : 'Previewing'} workspace cohort '
      '${plan.currentVersion} -> ${options.version} '
      '(${plan.channel}).',
    );
    for (final path in plan.updates.keys) {
      stdout.writeln('UPDATE $path');
    }
    if (!options.apply) {
      stdout.writeln(
        'Preview only. Re-run with --apply to update these exact sources.',
      );
      return;
    }
    await plan.apply();
    stdout.writeln(
      'Applied ${plan.updates.length} transactional source updates. Run '
      '`dart run tool/generate_release_artifacts.dart` to regenerate declared '
      'release derivatives.',
    );
  } on Object catch (error) {
    stderr.writeln('Release version update failed: $error');
    exitCode = error is FormatException || error is ArgumentError ? 64 : 1;
  }
}

final class _VersionPlan {
  const _VersionPlan({
    required this.root,
    required this.currentVersion,
    required this.channel,
    required this.updates,
  });

  factory _VersionPlan.build(Directory root, String targetVersion) {
    final contractFile = File(
      '${root.path}/tool/package_release_contract.json',
    );
    final contractSource = contractFile.readAsStringSync();
    final contract = releaseObject(
      jsonDecode(contractSource),
      'package release contract',
    );
    if (contract['schemaVersion'] != 4) {
      throw const FormatException('Unsupported package release schema.');
    }
    final target = SemanticVersion.parse(targetVersion);
    final workspace = releaseObject(
      contract['workspaceCohort'],
      'workspaceCohort',
    );
    final distributed = releaseObject(
      contract['distributedCohort'],
      'distributedCohort',
    );
    final currentVersion = workspace['version'];
    final distributedVersion = distributed['version'];
    if (currentVersion is! String || distributedVersion is! String) {
      throw const FormatException('Cohort versions must be strings.');
    }
    final stable = SemanticVersion.parse(distributedVersion);
    if (target.major != 1 || target.compareTo(stable) < 0) {
      throw ArgumentError.value(
        targetVersion,
        'version',
        'must remain in 1.x and not precede distributed $distributedVersion',
      );
    }
    final channel = target.prerelease == null ? 'stable' : 'candidate';
    final targetTag = 'v$targetVersion';
    final updates = <String, String>{};

    final packagePaths = releaseObject(
      contract['packagePaths'],
      'packagePaths',
    );
    final versionSources = releaseObject(
      contract['workspaceVersionSources'],
      'workspaceVersionSources',
    );
    final manifests = <String>{
      for (final path in packagePaths.values)
        '${_string(path, 'package path')}/pubspec.yaml',
      ..._strings(versionSources['manifests'], 'manifests'),
    }.toList()..sort();
    for (final path in manifests) {
      final source = _read(root, path);
      final updated = _replaceManifestVersions(
        source,
        currentVersion,
        targetVersion,
      );
      if (updated == source && currentVersion != targetVersion) {
        throw StateError('$path does not declare $currentVersion.');
      }
      _record(updates, path, source, updated);
    }

    for (final path in _strings(
      versionSources['nativeManifests'],
      'nativeManifests',
    )) {
      final source = _read(root, path);
      final updated = source.replaceFirstMapped(
        RegExp("(s\\.version\\s*=\\s*)'${RegExp.escape(currentVersion)}'"),
        (match) => "${match.group(1)}'$targetVersion'",
      );
      if (updated == source && currentVersion != targetVersion) {
        throw StateError('$path does not declare $currentVersion.');
      }
      _record(updates, path, source, updated);
    }

    final derivatives = _strings(
      versionSources['structuredDerivatives'],
      'structuredDerivatives',
    ).toSet();
    const apiPath = 'tool/api_surface.snapshot.json';
    if (!derivatives.remove(apiPath)) {
      throw StateError('API snapshot must be a declared derivative.');
    }
    final apiSource = _read(root, apiPath);
    final api = releaseObject(jsonDecode(apiSource), 'API snapshot');
    if (api['sdkVersion'] != currentVersion) {
      throw StateError('$apiPath does not match $currentVersion.');
    }
    _record(
      updates,
      apiPath,
      apiSource,
      apiSource.replaceFirst(
        '"sdkVersion": "$currentVersion"',
        '"sdkVersion": "$targetVersion"',
      ),
    );

    const canaryPath = 'tool/canaries/canary_contract.json';
    if (!derivatives.remove(canaryPath) || derivatives.isNotEmpty) {
      throw StateError('Unknown structured derivatives: $derivatives.');
    }
    final canarySource = _read(root, canaryPath);
    final canary = releaseObject(jsonDecode(canarySource), 'canary contract');
    if (canary['workspaceVersion'] != currentVersion) {
      throw StateError('$canaryPath does not match $currentVersion.');
    }
    releaseObject(canary['gitInstallation'], 'gitInstallation');
    final canaryUpdated =
        _replaceJsonObjectFields(
              canarySource,
              'gitInstallation',
              <String, String>{'ref': '"$targetTag"'},
            )
            .replaceFirst(
              '"workspaceVersion": "$currentVersion"',
              '"workspaceVersion": "$targetVersion"',
            )
            .replaceAll('--to=$currentVersion', '--to=$targetVersion');
    _record(updates, canaryPath, canarySource, canaryUpdated);

    workspace
      ..['version'] = targetVersion
      ..['channel'] = channel
      ..['derivedTag'] = targetTag
      ..['tagMaterialized'] = targetVersion == distributedVersion
          ? distributed['available'] == true
          : false;
    final lockstep = releaseObject(contract['lockstep'], 'lockstep')
      ..['version'] = targetVersion
      ..['derivedTag'] = targetTag;
    final dependency = releaseObject(
      contract['workspaceInternalDependency'],
      'workspaceInternalDependency',
    )..['version'] = targetVersion;
    if (lockstep['version'] != dependency['version']) {
      throw StateError('Workspace lockstep update is inconsistent.');
    }
    final packages = releaseObject(contract['packages'], 'packages');
    for (final metadata in packages.values) {
      releaseObject(metadata, 'package metadata')['version'] = targetVersion;
    }
    var updatedContract = _replaceJsonObjectFields(
      contractSource,
      'workspaceCohort',
      <String, String>{
        'version': '"$targetVersion"',
        'channel': '"$channel"',
        'derivedTag': '"$targetTag"',
        'tagMaterialized': workspace['tagMaterialized'].toString(),
      },
    );
    updatedContract = _replaceJsonObjectFields(
      updatedContract,
      'lockstep',
      <String, String>{
        'version': '"$targetVersion"',
        'derivedTag': '"$targetTag"',
      },
    );
    updatedContract = _replaceJsonObjectFields(
      updatedContract,
      'workspaceInternalDependency',
      <String, String>{'version': '"$targetVersion"'},
    );
    updatedContract = _replaceJsonObjectValues(
      updatedContract,
      'packages',
      '"version": "$currentVersion"',
      '"version": "$targetVersion"',
    );
    _record(
      updates,
      'tool/package_release_contract.json',
      contractSource,
      updatedContract,
    );

    final ordered = <String, String>{};
    final paths = updates.keys.toList()..sort();
    for (final path in paths) {
      ordered[path] = updates[path]!;
    }
    return _VersionPlan(
      root: root,
      currentVersion: currentVersion,
      channel: channel,
      updates: ordered,
    );
  }

  final Directory root;
  final String currentVersion;
  final String channel;
  final Map<String, String> updates;

  Future<void> apply() async {
    final originals = <String, String>{};
    final committed = <String>[];
    try {
      for (final entry in updates.entries) {
        final file = File('${root.path}/${entry.key}');
        originals[entry.key] = await file.readAsString();
        final staging = File('${file.path}.dartitect-version-staging');
        await staging.writeAsString(entry.value, flush: true);
        await staging.rename(file.path);
        committed.add(entry.key);
      }
    } on Object {
      for (final path in committed.reversed) {
        final file = File('${root.path}/$path');
        final staging = File('${file.path}.dartitect-version-rollback');
        await staging.writeAsString(originals[path]!, flush: true);
        await staging.rename(file.path);
      }
      rethrow;
    } finally {
      for (final path in updates.keys) {
        for (final suffix in const <String>[
          '.dartitect-version-staging',
          '.dartitect-version-rollback',
        ]) {
          final temporary = File('${root.path}/$path$suffix');
          if (await temporary.exists()) await temporary.delete();
        }
      }
    }
  }
}

final class _Options {
  const _Options({
    required this.root,
    required this.version,
    required this.apply,
  });

  factory _Options.parse(List<String> arguments) {
    var apply = false;
    String? rootPath;
    String? version;
    for (final argument in arguments) {
      if (argument == '--apply') {
        if (apply) throw const FormatException('Duplicate --apply.');
        apply = true;
      } else if (argument.startsWith('--root=')) {
        if (rootPath != null) throw const FormatException('Duplicate --root.');
        rootPath = argument.substring('--root='.length);
      } else if (!argument.startsWith('--') && version == null) {
        version = argument;
      } else {
        throw FormatException('Unknown or duplicate argument: $argument');
      }
    }
    if (version == null) {
      throw const FormatException(
        'Usage: dart run tool/set_release_version.dart VERSION [--apply]',
      );
    }
    return _Options(
      root: rootPath == null
          ? File.fromUri(Platform.script).parent.parent.absolute
          : Directory(rootPath).absolute,
      version: version,
      apply: apply,
    );
  }

  final Directory root;
  final String version;
  final bool apply;
}

String _replaceManifestVersions(String source, String current, String target) {
  final version = RegExp.escape(current);
  return source
      .replaceAllMapped(
        RegExp('^(\\s*version:\\s*)$version(\\s*)\$', multiLine: true),
        (match) => '${match.group(1)}$target${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(
          '^(\\s+dartitect(?:_[a-z0-9_]+)?:\\s*)$version(\\s*)\$',
          multiLine: true,
        ),
        (match) => '${match.group(1)}$target${match.group(2)}',
      );
}

String _read(Directory root, String path) {
  if (path.startsWith('/') || path.split('/').contains('..')) {
    throw FormatException('Version source is not confined: $path.');
  }
  final file = File('${root.path}/$path');
  if (!file.existsSync()) throw StateError('Missing version source: $path.');
  return file.readAsStringSync();
}

String _replaceJsonObjectFields(
  String source,
  String objectName,
  Map<String, String> replacements,
) {
  final range = _jsonObjectRange(source, objectName);
  var object = source.substring(range.$1, range.$2);
  for (final entry in replacements.entries) {
    final pattern = RegExp(
      '^(\\s*"${RegExp.escape(entry.key)}":\\s*)[^,\\n]+(,?)\$',
      multiLine: true,
    );
    if (!pattern.hasMatch(object)) {
      throw StateError('$objectName lacks JSON field ${entry.key}.');
    }
    object = object.replaceFirstMapped(
      pattern,
      (match) => '${match.group(1)}${entry.value}${match.group(2)}',
    );
  }
  return source.replaceRange(range.$1, range.$2, object);
}

String _replaceJsonObjectValues(
  String source,
  String objectName,
  String before,
  String after,
) {
  final range = _jsonObjectRange(source, objectName);
  final object = source.substring(range.$1, range.$2);
  if (!object.contains(before)) {
    throw StateError('$objectName does not contain $before.');
  }
  return source.replaceRange(
    range.$1,
    range.$2,
    object.replaceAll(before, after),
  );
}

(int, int) _jsonObjectRange(String source, String objectName) {
  final marker = '"$objectName": {';
  final markerIndex = source.indexOf(marker);
  if (markerIndex < 0) throw StateError('Missing JSON object $objectName.');
  final start = source.indexOf('{', markerIndex);
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < source.length; index += 1) {
    final unit = source.codeUnitAt(index);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        inString = false;
      }
      continue;
    }
    if (unit == 0x22) {
      inString = true;
    } else if (unit == 0x7b) {
      depth += 1;
    } else if (unit == 0x7d) {
      depth -= 1;
      if (depth == 0) return (start, index + 1);
    }
  }
  throw StateError('Unterminated JSON object $objectName.');
}

void _record(
  Map<String, String> updates,
  String path,
  String before,
  String after,
) {
  if (before != after) updates[path] = after;
}

List<String> _strings(Object? value, String label) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$label must be a string list.');
  }
  return value.cast<String>();
}

String _string(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be a string.');
  return value;
}
