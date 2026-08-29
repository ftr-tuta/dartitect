import 'dart:convert';
import 'dart:io';

/// Verifies the static, local assembly contract for the lockstep RC cohort.
void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  final candidate = _object(
    jsonDecode(
      File('${root.path}/tool/rc_candidate_contract.json').readAsStringSync(),
    ),
  );
  final release = _object(
    jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ),
  );
  final baselineValue = release['baselineVersion'];
  final packageCountValue = release['packageCount'];
  final entrypointCountValue = release['publicEntrypointCount'];
  final candidateTagValue = release['candidateTag'];
  if (baselineValue is! String ||
      packageCountValue is! int ||
      entrypointCountValue is! int ||
      candidateTagValue is! String) {
    errors.add('The package release authority is incomplete.');
  }
  final cohort = baselineValue is String ? baselineValue : '';
  final packageCount = packageCountValue is int ? packageCountValue : -1;
  final publicEntrypointCount = entrypointCountValue is int
      ? entrypointCountValue
      : -1;
  final candidateTag = candidateTagValue is String ? candidateTagValue : '';
  if (candidate['schemaVersion'] != 1 ||
      candidate['cohortVersion'] != cohort ||
      candidate['candidateState'] != 'SOURCE_CANDIDATE_ASSEMBLED' ||
      candidate['targetChannel'] != 'UNMATERIALIZED' ||
      candidate['packageCount'] != packageCount ||
      candidate['publicEntrypointCount'] != publicEntrypointCount) {
    errors.add('RC candidate metadata is incomplete or overstates readiness.');
  }
  if (release['cohortVersion'] != cohort) {
    errors.add('The package release contract is not assembled at $cohort.');
  }

  final order = _strings(release['publicationOrder']);
  final observation = _object(candidate['nameRegistryObservation']);
  final observedNames = _strings(observation['packages']);
  if (observation['registry'] != 'https://pub.dev' ||
      observation['requestPattern'] != 'GET /api/packages/{name}' ||
      observation['expectedStatus'] != 404 ||
      DateTime.tryParse('${observation['observedAt']}')?.isUtc != true ||
      !_same(order, observedNames)) {
    errors.add(
      'The pub.dev package-name observation is invalid or incomplete.',
    );
  }
  final publisher = _object(candidate['publisherIdentity']);
  if (publisher['status'] != 'NOT_AUTHORIZED' ||
      publisher['requiredBeforePubDevMaterialization'] != true ||
      '${publisher['reason']}'.trim().isEmpty) {
    errors.add(
      'Publisher verification must fail closed before materialization.',
    );
  }
  final git = _object(candidate['gitConsumption']);
  if (git['repository'] != 'https://github.com/ftr-tuta/dartitect.git' ||
      git['tag'] != candidateTag ||
      git['materialized'] != false ||
      git['annotated'] != true ||
      git['signed'] != false ||
      git['protectedAgainstUpdateAndDeletion'] != true ||
      git['githubRelease'] != false ||
      git['pubDevPublication'] != false ||
      git['overrideGenerator'] != 'tool/git_dependency_overrides.dart' ||
      git['canaryGate'] != 'tool/run_git_canaries.dart') {
    errors.add('The Git-consumption candidate contract is invalid.');
  }

  final rootVersion = _field(
    File('${root.path}/pubspec.yaml').readAsStringSync(),
    'version',
  );
  if (rootVersion != cohort) errors.add('Workspace version is $rootVersion.');

  final packages = <String>{};
  for (final entity in Directory('${root.path}/packages').listSync()) {
    if (entity is! Directory) continue;
    final pubspec = File('${entity.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final source = pubspec.readAsStringSync();
    final name = _field(source, 'name');
    final version = _field(source, 'version');
    if (name == null) {
      errors.add('${entity.path} has no package name.');
      continue;
    }
    packages.add(name);
    if (version != cohort) errors.add('$name is $version; expected $cohort.');
    final changelog = File('${entity.path}/CHANGELOG.md');
    final firstHeading = changelog.existsSync()
        ? RegExp(
            r'^##\s+([^\s]+)',
            multiLine: true,
          ).firstMatch(changelog.readAsStringSync())?.group(1)
        : null;
    if (firstHeading != cohort) {
      errors.add('$name changelog does not begin with $cohort.');
    }
  }
  if (packages.length != packageCount || !packages.containsAll(order)) {
    errors.add(
      'The candidate does not contain the exact $packageCount-package cohort.',
    );
  }

  final snapshot = _object(
    jsonDecode(
      File('${root.path}/tool/api_surface.snapshot.json').readAsStringSync(),
    ),
  );
  if (snapshot['sdkVersion'] != cohort ||
      _object(snapshot['entrypoints']).length != publicEntrypointCount) {
    errors.add(
      'The public API snapshot is not an RC snapshot of '
      '$publicEntrypointCount entrypoints.',
    );
  }
  final inventory = _object(
    jsonDecode(File('${root.path}/tool/sdk_inventory.json').readAsStringSync()),
  );
  final inventoryPackages = inventory['packages'];
  if (inventoryPackages is! List<Object?> ||
      inventoryPackages.length != packageCount ||
      inventoryPackages.whereType<Map<String, Object?>>().any(
        (package) => package['version'] != cohort,
      )) {
    errors.add('The SDK inventory is not the exact RC cohort.');
  }

  for (final path in _strings(candidate['requiredArtifacts'])) {
    if (!File('${root.path}/$path').existsSync()) {
      errors.add('Required RC artifact is missing: $path.');
    }
  }
  for (final path in const <String>[
    '.github/ISSUE_TEMPLATE/bug_report.yml',
    'README.md',
    'docs/release/1.0-readiness.adoc',
    'docs/release/public-api-review.adoc',
    'packages/dartitect_cli/lib/src/diagnostics/models.dart',
    'packages/dartitect_cli/lib/src/generation/generation_engine.dart',
    'packages/dartitect_mcp/bin/dartitect_mcp.dart',
    'packages/dartitect_mcp/lib/src/server.dart',
  ]) {
    final source = File('${root.path}/$path').readAsStringSync();
    if (!source.contains(cohort) || source.contains('1.0.0-dev.')) {
      errors.add('$path does not identify only the current RC cohort.');
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'RC source candidate passed for $packageCount packages at $cohort; no tag, '
    'release, or publication is materialized and every external channel '
    'remains fail-closed.',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string list.');
  }
  return value.cast<String>();
}

String? _field(String source, String name) => RegExp(
  '^${RegExp.escape(name)}:\\s*([^\\s]+)',
  multiLine: true,
).firstMatch(source)?.group(1);

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((value) => value);
