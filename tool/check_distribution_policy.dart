import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'release_contract.dart';

/// Enforces the GitHub-only lockstep distribution policy fail-closed.
void main(List<String> arguments) {
  try {
    final root = _root(arguments);
    final policy = _object(
      jsonDecode(
        File('${root.path}/tool/distribution_policy.json').readAsStringSync(),
      ),
    );
    final cohorts = ReleaseCohortContract.read(root);
    final release = _object(policy['release']);
    final dependency = _object(policy['internalDependency']);
    final errors = <String>[];
    if (policy['schemaVersion'] != 1 ||
        policy['releaseVersion'] != cohorts.distributed.version ||
        policy['releaseTag'] != cohorts.distributed.tag ||
        policy['repository'] != 'https://github.com/ftr-tuta/dartitect.git' ||
        policy['packageCount'] != 25 ||
        policy['lockstep'] != true ||
        policy['publishTo'] != 'none') {
      errors.add('Distribution policy identity is incomplete.');
    }
    if (dependency['url'] != policy['repository'] ||
        dependency['pathPrefix'] != 'packages/' ||
        dependency['tagPattern'] != 'v{{version}}' ||
        dependency['version'] != policy['releaseVersion']) {
      errors.add('Canonical internal Git descriptor is incomplete.');
    }
    if (release['workflow'] != '.github/workflows/release.yaml' ||
        release['annotatedTag'] != true ||
        release['signedTag'] != false ||
        release['immutable'] != true ||
        release['administrativePreflight'] != true ||
        release['releaseTagRulesetId'] != 21525640 ||
        release['postPublicationVerification'] != true ||
        release['registryPublication'] != false) {
      errors.add('GitHub Release policy is incomplete.');
    }

    final packages =
        Directory('${root.path}/packages')
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where(
              (directory) =>
                  File('${directory.path}/pubspec.yaml').existsSync(),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    if (packages.length != policy['packageCount']) {
      errors.add(
        'Found ${packages.length} packages; expected ${policy['packageCount']}.',
      );
    }
    for (final package in packages) {
      _checkPackage(
        root,
        package,
        cohorts.workspace.version,
        cohorts.workspaceDependency,
        errors,
      );
    }
    _checkRootMetadata(root, cohorts.workspace.version, errors);
    _checkWorkflows(root, release['workflow']! as String, errors);
    _checkForbiddenMechanisms(root, errors);
    _checkGeneratedConsumer(root, cohorts, errors);
    _checkActiveDocuments(root, policy, errors);

    if (errors.isNotEmpty) {
      stderr.writeln(errors.toSet().join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Distribution policy passed for ${packages.length} lockstep packages at '
      '${cohorts.workspace.version}; public consumption remains '
      '${policy['releaseTag']}.',
    );
  } on Object catch (error) {
    stderr.writeln('Distribution policy could not be checked: $error');
    exitCode = 1;
  }
}

void _checkPackage(
  Directory root,
  Directory directory,
  String version,
  Map<String, Object?> policy,
  List<String> errors,
) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  final yaml = _yamlObject(loadYaml(pubspec.readAsStringSync()));
  final name = yaml['name'];
  final relative = _relative(root, pubspec);
  if (name is! String || !_isDartitectPackage(name)) {
    errors.add('$relative has an invalid Dartitect package name.');
    return;
  }
  if (yaml['version'] != version) {
    errors.add('$name must use the lockstep version $version.');
  }
  if (yaml['publish_to'] != 'none') {
    errors.add('$name must declare publish_to: none.');
  }
  if (yaml['resolution'] != 'workspace') {
    errors.add('$name must retain workspace resolution for local development.');
  }
  if (yaml.containsKey('dependency_overrides')) {
    errors.add('$name must not contain dependency_overrides.');
  }

  for (final sectionName in const <String>[
    'dependencies',
    'dev_dependencies',
  ]) {
    final section = _yamlObjectOrNull(yaml[sectionName]);
    if (section == null) continue;
    for (final entry in section.entries.where(
      (entry) => _isDartitectPackage(entry.key),
    )) {
      final descriptor = _yamlObjectOrNull(entry.value);
      final git = _yamlObjectOrNull(descriptor?['git']);
      final expectedPath = '${policy['pathPrefix']}${entry.key}';
      if (descriptor == null ||
          descriptor.keys.toSet().difference(const <String>{
            'git',
            'version',
          }).isNotEmpty ||
          descriptor['version'] != version ||
          git == null ||
          git.keys.toSet().difference(const <String>{
            'url',
            'path',
            'tag_pattern',
          }).isNotEmpty ||
          git['url'] != policy['url'] ||
          git['path'] != expectedPath ||
          git['tag_pattern'] != policy['tagPattern']) {
        errors.add(
          '$name -> ${entry.key} does not use the canonical Git descriptor.',
        );
      }
    }
  }
}

void _checkRootMetadata(Directory root, String version, List<String> errors) {
  for (final path in const <String>[
    'pubspec.yaml',
    'tool/dartitect_devtools_extension/pubspec.yaml',
  ]) {
    final yaml = _yamlObject(
      loadYaml(File('${root.path}/$path').readAsStringSync()),
    );
    if (yaml['version'] != version || yaml['publish_to'] != 'none') {
      errors.add('$path must declare version $version and publish_to: none.');
    }
  }
  for (final path in const <String>[
    'packages/dartitect_media/ios/dartitect_media.podspec',
    'packages/dartitect_privacy/ios/dartitect_privacy.podspec',
  ]) {
    final source = File('${root.path}/$path').readAsStringSync();
    if (!RegExp("s\\.version\\s+= '$version'").hasMatch(source)) {
      errors.add('$path must declare pod version $version.');
    }
  }
}

void _checkWorkflows(
  Directory root,
  String releaseWorkflow,
  List<String> errors,
) {
  final workflows = Directory('${root.path}/.github/workflows')
      .listSync(followLinks: false)
      .whereType<File>()
      .where(
        (file) => file.path.endsWith('.yaml') || file.path.endsWith('.yml'),
      )
      .toList();
  final expected = <String>{
    'ci.yaml',
    'flutter_quality_evals.yml',
    'security.yaml',
    'release.yaml',
  };
  final actual = workflows.map((file) => portableBasename(file.path)).toSet();
  if (actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    errors.add(
      'Workflows must be exactly CI, Flutter Quality Evals, Security, and '
      'Release.',
    );
  }
  for (final workflow in workflows) {
    final name = portableBasename(workflow.path);
    final source = workflow.readAsStringSync();
    final write = RegExp(
      r'^\s*contents:\s*write\s*$',
      multiLine: true,
    ).hasMatch(source);
    final read = RegExp(
      r'^\s*contents:\s*read\s*$',
      multiLine: true,
    ).hasMatch(source);
    if (name == portableBasename(releaseWorkflow)) {
      if (!write || !source.startsWith('name: Release\n')) {
        errors.add('Release must be the sole contents: write workflow.');
      }
      final contractGate = source.indexOf(
        'Load stable release contract and reject prereleases',
      );
      final toolchainInstall = source.indexOf('name: Install Flutter');
      if (contractGate < 0 ||
          toolchainInstall < 0 ||
          contractGate > toolchainInstall ||
          !source.contains('Release refuses workspace cohort') ||
          source.contains('RELEASE_TAG: v1.0.0')) {
        errors.add(
          'Release must derive its tag from the contract and reject '
          'prereleases before release preparation.',
        );
      }
      if (!source.contains(
            'https://api.github.com/repos/\${GITHUB_REPOSITORY}/rulesets/21525640',
          ) ||
          !source.contains(
            'Verify public release policy and referenced main CI',
          )) {
        errors.add('Release must revalidate the public release-tag ruleset.');
      }
      if (source.contains('/immutable-releases') ||
          source.contains('.bypass_actors')) {
        errors.add(
          'Release must not call Repository Administration endpoints with '
          'GITHUB_TOKEN.',
        );
      }
      if (!source.contains(
            'Verify immutable Release, assets, and attestation',
          ) ||
          RegExp(r'\.immutable\s*==\s*true').allMatches(source).length < 2 ||
          !source.contains('gh release verify "\$RELEASE_TAG"')) {
        errors.add(
          'Release must verify immutability and attestation after publication.',
        );
      }
    } else if (write || !read) {
      errors.add('$name must explicitly use contents: read.');
    }
  }
}

void _checkForbiddenMechanisms(Directory root, List<String> errors) {
  final checked = <File>[
    ...Directory('${root.path}/.github/workflows')
        .listSync(followLinks: false)
        .whereType<File>(),
    for (final path in const <String>[
      'tool/verify.dart',
      'tool/release_audit.dart',
      'tool/check_ci_security_policy.dart',
      'tool/actions_readiness_policy.json',
    ])
      File('${root.path}/$path'),
  ];
  final forbidden = <RegExp>[
    RegExp(r'dart\s+pub\s+publish'),
    RegExp(r'pub\s+token\s+add'),
    RegExp(r'PUB_DEV_TOKEN'),
    RegExp(r'pub-dev-(?:stable|prerelease)'),
    RegExp(r'--publish-dry-run'),
    RegExp(r'check_pub_dev_identity'),
  ];
  for (final file in checked.where((file) => file.existsSync())) {
    final source = file.readAsStringSync();
    for (final pattern in forbidden) {
      if (pattern.hasMatch(source)) {
        errors.add(
          '${_relative(root, file)} contains a forbidden registry mechanism.',
        );
      }
    }
  }
  for (final removed in const <String>[
    '.github/workflows/publish.yaml',
    'tool/check_pub_dev_identity.dart',
    'tool/check_rc_candidate.dart',
    'tool/rc_candidate_contract.json',
    'docs/release/pub-dev-identity-audit.adoc',
  ]) {
    if (File('${root.path}/$removed').existsSync()) {
      errors.add('$removed must be removed from the active release surface.');
    }
  }
}

void _checkGeneratedConsumer(
  Directory root,
  ReleaseCohortContract cohorts,
  List<String> errors,
) {
  final file = File('${root.path}/tool/generated_project_matrix.dart');
  if (!file.existsSync()) {
    errors.add('Generated-project matrix is missing.');
    return;
  }
  final source = file.readAsStringSync();
  for (final required in <String>[
    'url: ${cohorts.workspaceDependency['url']}',
    r'path: packages/$package',
    "tag_pattern: 'v{{version}}'",
    "final cohort = contract['workspaceCohort']!",
    "final version = cohort['version']! as String;",
    r'version: $version',
  ]) {
    if (!source.contains(required)) {
      errors.add('Generated-project matrix lacks canonical Git descriptors.');
      break;
    }
  }
  if (source.contains('dependency_overrides:') ||
      source.contains('_addLocalSdkDependencies')) {
    errors.add('Generated-project matrix must not create Dartitect overrides.');
  }
}

void _checkActiveDocuments(
  Directory root,
  Map<String, Object?> policy,
  List<String> errors,
) {
  final active = _strings(policy['activeDocuments']);
  final historical = _strings(policy['historicalDocuments']).toSet();
  if (active.toSet().intersection(historical).isNotEmpty) {
    errors.add('Active and historical documentation sets overlap.');
  }
  for (final path in active) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      errors.add('Active distribution document is missing: $path.');
      continue;
    }
    final source = file.readAsStringSync();
    for (final forbidden in const <String>[
      '1.0.0-rc.',
      'git_dependency_overrides',
      'pub-dev-stable',
      'pub-dev-prerelease',
    ]) {
      if (source.contains(forbidden)) {
        errors.add('$path contains obsolete distribution text: $forbidden.');
      }
    }
  }
  for (final path in const <String>[
    'README.md',
    'docs/guides/getting-started.md',
    'docs/guides/git-release-consumption.md',
  ]) {
    final source = File('${root.path}/$path').readAsStringSync();
    for (final required in <String>[
      policy['repository']! as String,
      "tag_pattern: 'v{{version}}'",
      'version: ${policy['releaseVersion']}',
    ]) {
      if (!source.contains(required)) {
        errors.add('$path is missing canonical Git consumption text.');
      }
    }
  }
}

Directory _root(List<String> arguments) {
  if (arguments.isEmpty) {
    return File.fromUri(Platform.script).parent.parent.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments[1]).absolute;
  }
  throw const FormatException(
    'Usage: dart run tool/check_distribution_policy.dart [--root PATH]',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

Map<String, Object?> _yamlObject(Object? value) {
  final result = _yamlObjectOrNull(value);
  if (result == null) throw const FormatException('Expected a YAML map.');
  return result;
}

Map<String, Object?>? _yamlObjectOrNull(Object? value) {
  if (value is! Map<Object?, Object?>) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return value.cast<String>();
}

bool _isDartitectPackage(String name) =>
    RegExp(r'^dartitect(?:_[a-z0-9_]+)?$').hasMatch(name);

String _relative(Directory root, File file) => file.path
    .substring(root.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

/// Returns the final path component for either POSIX or Windows input.
String portableBasename(String path) =>
    path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).last;
