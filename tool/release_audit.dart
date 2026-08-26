import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = ReleaseAuditOptions.parse(arguments);
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final stableCohort = _cohortVersion(root) == '1.0.0';
  final commands = <_Command>[
    const _Command('dart', <String>['run', 'tool/check_goal_gates.dart']),
    const _Command('dart', <String>['run', 'tool/check_package_topology.dart']),
    const _Command('dart', <String>[
      'run',
      'tool/check_package_release_contract.dart',
    ]),
    if (!stableCohort)
      const _Command('dart', <String>['run', 'tool/check_rc_candidate.dart']),
    const _Command('dart', <String>['run', 'tool/check_pub_dev_identity.dart']),
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
    if (!stableCohort)
      const _Command('dart', <String>[
        'run',
        'tool/check_rc_readiness.dart',
        '--contract-only',
      ]),
    if (!stableCohort)
      const _Command('dart', <String>[
        'run',
        'tool/check_rc_artifacts.dart',
        '--contract-only',
      ]),
    if (!stableCohort)
      const _Command('dart', <String>[
        'run',
        'tool/check_rc_validation.dart',
        '--contract-only',
      ]),
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
    'docs/release/pub-dev-identity-audit.adoc',
    'docs/release/publish-exceptions.adoc',
    'docs/release/publication-runbook.adoc',
    'tool/api_surface.snapshot.json',
    'tool/package_release_contract.json',
    'tool/rc_candidate_contract.json',
    'tool/rc_readiness_decision.json',
    'tool/rc_distribution_authorization.json',
    'tool/rc_bundle_contract.json',
    'tool/rc_validation_contract.json',
    'tool/stable_readiness_decision.json',
    'tool/stable_candidate_contract.json',
    'tool/stable_candidate_record.json',
    'tool/stable_publication_authorization.json',
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
  final publicationOrder = _packagePublicationOrder(root);
  final publicationPositions = <String, int>{
    for (var index = 0; index < publicationOrder.length; index += 1)
      publicationOrder[index]: index,
  };
  packages.sort(
    (left, right) => publicationPositions[_basename(left.path)]!.compareTo(
      publicationPositions[_basename(right.path)]!,
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
  if (options.publishDryRun) {
    for (final package in packages) {
      await _runPublishDryRun(package);
    }
  }
  stdout.writeln(
    'Local release audit passed${options.publishDryRun ? ' with publish dry-runs' : ''}.',
  );
}

String _cohortVersion(Directory root) {
  final value = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (value is! Map<String, Object?> || value['cohortVersion'] is! String) {
    throw const FormatException('Invalid package release cohort.');
  }
  return value['cohortVersion']! as String;
}

List<String> _packagePublicationOrder(Directory root) {
  final contract = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (contract is! Map<String, Object?> ||
      contract['schemaVersion'] != 1 ||
      contract['publicationOrder'] is! List<Object?>) {
    throw const FormatException('Invalid package release contract.');
  }
  final order = contract['publicationOrder']! as List<Object?>;
  if (order.any((value) => value is! String)) {
    throw const FormatException('Invalid package publication order.');
  }
  return order.cast<String>();
}

final class ReleaseAuditOptions {
  const ReleaseAuditOptions({
    required this.docs,
    required this.publishDryRun,
    required this.authorRevision,
    required this.excludeMergeCommits,
  });

  factory ReleaseAuditOptions.parse(List<String> arguments) {
    var docs = false;
    var publishDryRun = false;
    var excludeMergeCommits = false;
    String? authorRevision;
    for (final argument in arguments) {
      switch (argument) {
        case '--docs':
          if (docs) throw ArgumentError('Duplicate argument: --docs');
          docs = true;
        case '--publish-dry-run':
          if (publishDryRun) {
            throw ArgumentError('Duplicate argument: --publish-dry-run');
          }
          publishDryRun = true;
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
      publishDryRun: publishDryRun,
      authorRevision: authorRevision,
      excludeMergeCommits: excludeMergeCommits,
    );
  }

  final bool docs;
  final bool publishDryRun;
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

Future<void> _runPublishDryRun(Directory package) async {
  const command = _Command('dart', <String>['pub', 'publish', '--dry-run']);
  stdout.writeln('> ${command.executable} ${command.arguments.join(' ')}');
  final result = await Process.run(
    command.executable,
    command.arguments,
    workingDirectory: package.path,
  ).timeout(const Duration(minutes: 8));
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode == 0) return;

  final output = '${result.stdout}\n${result.stderr}';
  final issueLines = const LineSplitter()
      .convert(output)
      .where((line) => line.startsWith('* '))
      .toList(growable: false);
  final packageName = _basename(package.path);
  final approvedPluginWarning =
      packageName == 'dartitect_lints' &&
      result.exitCode == 65 &&
      issueLines.length == 1 &&
      issueLines.single.contains(
        'The name of "lib/main.dart", "main", should match the name of the package',
      ) &&
      output.contains('Package has 1 warning.');
  if (approvedPluginWarning) {
    stdout.writeln(
      'Accepted documented upstream analyzer-plugin entrypoint warning.',
    );
    return;
  }
  final approvedExperimentalMcpPin =
      packageName == 'dartitect_mcp' &&
      result.exitCode == 65 &&
      issueLines.length == 1 &&
      issueLines.single.contains(
        'dependency on "dart_mcp" should allow more than one version',
      ) &&
      output.contains('Package has 1 warning.');
  if (approvedExperimentalMcpPin) {
    stdout.writeln('Accepted documented experimental MCP pin warning.');
    return;
  }
  throw StateError(
    '${command.executable} ${command.arguments.join(' ')} '
    'failed with ${result.exitCode}.',
  );
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
