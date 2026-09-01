import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = ReleaseAuditOptions.parse(arguments);
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final commands = <_Command>[
    const _Command('dart', <String>['run', 'tool/check_goal_gates.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_canaries.dart',
      '--validate-only',
    ]),
    const _Command('dart', <String>['run', 'tool/check_package_topology.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_provider_constructor_evidence.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_package_release_contract.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_distribution_policy.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/generate_release_artifacts.dart',
      '--check',
    ]),
    const _Command('dart', <String>['run', 'tool/check_ecosystem_policy.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_consumer_neutrality.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_sdk_inventory.dart',
      '--check',
    ]),
    const _Command('dart', <String>['run', 'tool/check_testing_matrices.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_benchmark_artifacts.dart',
    ]),
    const _Command('dart', <String>['run', 'tool/check_model_benchmark.dart']),
    const _Command('dart', <String>['run', 'tool/check_source_ledger.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_dependency_inventory.dart',
    ]),
    const _Command('dart', <String>['run', 'tool/check_skill_coverage.dart']),
    const _Command('dart', <String>['run', 'tool/check_public_docs.dart']),
    const _Command('dart', <String>['run', 'tool/check_ui_quality.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_stable_candidate.dart',
      '--contract-only',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/check_ci_security_policy.dart',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/generate_mcp_catalog.dart',
      '--check',
    ]),
    const _Command('dart', <String>[
      'run',
      'tool/generate_supply_chain.dart',
      '--check',
    ]),
    const _Command('dart', <String>['run', 'tool/check_api_snapshot.dart']),
  ];
  for (final command in commands) {
    await _run(root, command);
  }
  for (final path in const <String>[
    'docs/release/sbom.spdx.json',
    'docs/release/dependency-licenses.json',
    'docs/release/advisory-audit.adoc',
    'docs/release/publication-runbook.adoc',
    'docs/release/package-cohorts.adoc',
    'docs/release/rc10-handoff.adoc',
    'tool/api_surface.snapshot.json',
    'tool/package_release_contract.json',
    'tool/provider_constructor_evidence.json',
    'tool/actions_readiness_policy.json',
    'tool/create_actions_readiness.dart',
    'tool/check_release_readiness.dart',
    'tool/distribution_policy.json',
    'tool/dependency_snippets.dart',
    'tool/build_release_assets.dart',
    'tool/github_ruleset_policy.json',
    'tool/github_release_ruleset_policy.json',
    'tool/rc_validation_contract.json',
    'tool/stable_candidate_contract.json',
    'tool/ui_quality_contract.json',
    'tool/check_ui_quality.dart',
    '.github/workflows/release.yaml',
  ]) {
    if (!await File('${root.path}/$path').exists()) {
      throw StateError('Required release artifact is missing: $path');
    }
  }
  final licenses = await File(
    '${root.path}/docs/release/dependency-licenses.json',
  ).readAsString();
  if (licenses.contains('NOASSERTION')) {
    throw StateError('Dependency license inventory contains NOASSERTION.');
  }
  await verifyCanonicalAuthors(root, options);

  final packages = <Directory>[];
  await for (final entity in Directory(
    '${root.path}/packages',
  ).list(followLinks: false)) {
    if (entity is Directory &&
        await File('${entity.path}/pubspec.yaml').exists()) {
      packages.add(entity);
    }
  }
  final dependencyOrder = packageDependencyOrder(root);
  final dependencyPositions = <String, int>{
    for (var index = 0; index < dependencyOrder.length; index += 1)
      dependencyOrder[index]: index,
  };
  packages.sort(
    (left, right) => dependencyPositions[_basename(left.path)]!.compareTo(
      dependencyPositions[_basename(right.path)]!,
    ),
  );
  if (options.docs) {
    for (final package in packages) {
      final name = _basename(package.path);
      await _run(
        package,
        _Command('dart', <String>[
          'doc',
          '--output',
          '${root.path}/docs/api/$name',
        ]),
      );
    }
  }
  stdout.writeln('Local GitHub-only release audit passed.');
}

List<String> packageDependencyOrder(Directory root) {
  final contract = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (contract is! Map<String, Object?> ||
      contract['schemaVersion'] != 3 ||
      contract['dependencyOrder'] is! List<Object?>) {
    throw const FormatException('Invalid package release contract.');
  }
  final order = contract['dependencyOrder']! as List<Object?>;
  if (order.any((value) => value is! String)) {
    throw const FormatException('Invalid package dependency order.');
  }
  return order.cast<String>();
}

final class ReleaseAuditOptions {
  const ReleaseAuditOptions({
    required this.docs,
    required this.authorRevision,
    required this.excludeMergeCommits,
  });

  factory ReleaseAuditOptions.parse(List<String> arguments) {
    var docs = false;
    var excludeMergeCommits = false;
    String? authorRevision;
    for (final argument in arguments) {
      switch (argument) {
        case '--docs':
          if (docs) throw ArgumentError('Duplicate argument: --docs');
          docs = true;
        case '--exclude-merge-commits':
          if (excludeMergeCommits) {
            throw ArgumentError('Duplicate argument: --exclude-merge-commits');
          }
          excludeMergeCommits = true;
        default:
          const prefix = '--author-revision=';
          if (!argument.startsWith(prefix)) {
            throw ArgumentError('Unknown argument: $argument');
          }
          if (authorRevision != null) {
            throw ArgumentError('Duplicate argument: --author-revision');
          }
          final revision = argument.substring(prefix.length);
          if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(revision)) {
            throw ArgumentError.value(
              revision,
              '--author-revision',
              'must be a full 40-character hexadecimal commit SHA',
            );
          }
          authorRevision = revision;
      }
    }
    return ReleaseAuditOptions(
      docs: docs,
      authorRevision: authorRevision,
      excludeMergeCommits: excludeMergeCommits,
    );
  }

  final bool docs;
  final String? authorRevision;
  final bool excludeMergeCommits;
}

Future<void> verifyCanonicalAuthors(
  Directory root,
  ReleaseAuditOptions options,
) async {
  final requestedRevision = options.authorRevision ?? 'HEAD';
  final resolvedRevision = await Process.run('git', <String>[
    'rev-parse',
    '--verify',
    '$requestedRevision^{commit}',
  ], workingDirectory: root.path);
  if (resolvedRevision.exitCode != 0) {
    throw StateError('Invalid author audit revision: $requestedRevision.');
  }
  final revision = (resolvedRevision.stdout as String).trim();
  if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(revision)) {
    throw StateError('Git returned an invalid commit for $requestedRevision.');
  }
  final result = await Process.run('git', <String>[
    'log',
    revision,
    if (options.excludeMergeCommits) '--no-merges',
    '--use-mailmap',
    '--format=%H%x09%aN%x09%aE',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    throw StateError('Could not audit authors reachable from $revision.');
  }
  final invalid = const LineSplitter()
      .convert(result.stdout as String)
      .where((line) {
        final fields = line.split('\t');
        return fields.length != 3 ||
            fields[1] != 'ftr' ||
            fields[2] != 'ftr@tuta.com';
      })
      .toList(growable: false);
  if (invalid.isNotEmpty) {
    throw StateError(
      'Every author reachable from $requestedRevision must be '
      'ftr <ftr@tuta.com>; '
      'invalid commits: ${invalid.join(', ')}',
    );
  }
}

Future<void> _run(Directory directory, _Command command) async {
  stdout.writeln('> ${command.executable} ${command.arguments.join(' ')}');
  final result = await Process.run(
    command.executable,
    command.arguments,
    workingDirectory: directory.path,
  ).timeout(const Duration(minutes: 8));
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw StateError(
      '${command.executable} ${command.arguments.join(' ')} '
      'failed with ${result.exitCode}.',
    );
  }
}

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;

final class _Command {
  const _Command(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
