import 'dart:convert';
import 'dart:io';

const _expectedSkills = <String>{
  'dartitect-adapters',
  'dartitect-adopt',
  'dartitect-design',
  'dartitect-mcp',
  'dartitect-modeling',
  'dartitect-observability',
  'dartitect-offline-first',
  'dartitect-reactive',
  'dartitect-runtime',
  'dartitect-testing',
  'dartitect-tooling',
};

const _expectedRouting = <String, String>{
  'greenfield': 'dartitect-design',
  'brownfield': 'dartitect-adopt',
  'simpleFlutterRuntime': 'dartitect-runtime',
  'reactiveRuntime': 'dartitect-reactive',
  'offlineOutbox': 'dartitect-offline-first',
  'providerAdapters': 'dartitect-adapters',
  'telemetry': 'dartitect-observability',
  'testing': 'dartitect-testing',
  'cliAndLints': 'dartitect-tooling',
  'localMcp': 'dartitect-mcp',
  'immutableModels': 'dartitect-modeling',
};

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final release = jsonDecode(
    await File('${root.path}/tool/package_release_contract.json')
        .readAsString(),
  );
  if (release is! Map<String, Object?> || release['cohortVersion'] is! String) {
    throw const FormatException('Invalid package release cohort.');
  }
  final cohort = release['cohortVersion']! as String;
  final manifest = jsonDecode(
    await File('${root.path}/tool/skill_coverage.json').readAsString(),
  );
  if (manifest is! Map<String, Object?> || manifest['schemaVersion'] != 1) {
    stderr.writeln('Invalid skill coverage manifest.');
    exitCode = 1;
    return;
  }
  final rawSkills = manifest['skills'];
  if (rawSkills is! Map<String, Object?>) {
    stderr.writeln('Skill coverage must contain a skills object.');
    exitCode = 1;
    return;
  }
  final skillNames = rawSkills.keys.toSet();
  if (!_sameStrings(skillNames, _expectedSkills)) {
    stderr.writeln(
      'Managed skills differ: expected ${_expectedSkills.toList()..sort()}, '
      'found ${skillNames.toList()..sort()}.',
    );
    exitCode = 1;
  }

  final routing = manifest['routingScenarios'];
  if (routing is! Map<String, Object?> ||
      !_sameStrings(routing.keys.toSet(), _expectedRouting.keys.toSet())) {
    stderr.writeln(
      'Routing scenarios must cover the eleven supported workflows.',
    );
    exitCode = 1;
  } else {
    for (final scenario in _expectedRouting.entries) {
      final targets = routing[scenario.key];
      if (targets is! List<Object?> ||
          targets.length != 1 ||
          targets.single != scenario.value) {
        stderr.writeln(
          'Invalid routing for ${scenario.key}: expected ${scenario.value}.',
        );
        exitCode = 1;
      }
    }
  }

  final covered = <String>{};
  for (final entry in rawSkills.entries) {
    final skill = Directory('${root.path}/.agents/skills/${entry.key}');
    final entrypoint = File('${skill.path}/SKILL.md');
    final metadata = File('${skill.path}/agents/openai.yaml');
    final manifestFile = File('${skill.path}/.dartitect-skill.json');
    if (!await entrypoint.exists() ||
        !await metadata.exists() ||
        !await manifestFile.exists()) {
      stderr.writeln('Incomplete managed skill: ${entry.key}');
      exitCode = 1;
      continue;
    }
    final entrypointSource = await entrypoint.readAsString();
    final metadataSource = await metadata.readAsString();
    if (!entrypointSource.startsWith(
          '---\nname: ${entry.key}\ndescription: ',
        ) ||
        !entrypointSource.contains('\n## When to use\n') ||
        !entrypointSource.contains('\n## When not to use\n') ||
        !entrypointSource.contains('\n## Invariants\n') ||
        !entrypointSource.contains('\n## Workflow\n') ||
        !entrypointSource.contains('\n## Validate\n')) {
      stderr.writeln('Invalid SKILL.md router for ${entry.key}.');
      exitCode = 1;
    }
    if (!metadataSource.contains('display_name: "Dartitect ') ||
        !metadataSource.contains('short_description: "') ||
        !metadataSource.contains('default_prompt: "Use \$${entry.key} ') ||
        !metadataSource.contains('allow_implicit_invocation: true')) {
      stderr.writeln('Invalid Codex metadata for ${entry.key}.');
      exitCode = 1;
    }
    final managedManifest = jsonDecode(await manifestFile.readAsString());
    if (managedManifest is! Map<String, Object?> ||
        managedManifest['schemaVersion'] != 1 ||
        managedManifest['sdkVersion'] != cohort ||
        managedManifest['contentHash'] is! String ||
        !RegExp(r'^[0-9a-f]{8}$')
            .hasMatch(managedManifest['contentHash']! as String)) {
      stderr.writeln('Invalid managed-skill manifest for ${entry.key}.');
      exitCode = 1;
    }
    final files = entry.value;
    if (files is! List<Object?> ||
        files.isEmpty ||
        files.any((file) => file is! String)) {
      stderr.writeln('Invalid coverage list for ${entry.key}.');
      exitCode = 1;
      continue;
    }
    covered.addAll(files.cast<String>());
  }

  final discovered = <String>{'tool/setup_objectbox_vm.dart'};
  final packages = Directory('${root.path}/packages');
  await for (final entity in packages.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final lib = Directory('${entity.path}/lib');
    if (!await lib.exists()) continue;
    await for (final file in lib.list(followLinks: false)) {
      if (file is File && file.path.endsWith('.dart')) {
        discovered.add(
          file.path
              .substring(root.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/'),
        );
      }
    }
  }
  final missing = discovered.difference(covered).toList()..sort();
  final stale = covered.difference(discovered).toList()..sort();
  if (missing.isNotEmpty || stale.isNotEmpty) {
    if (missing.isNotEmpty)
      stderr.writeln('Uncovered entrypoints: ${missing.join(', ')}');
    if (stale.isNotEmpty) stderr.writeln('Stale coverage: ${stale.join(', ')}');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Skill coverage passed: ${rawSkills.length} skills cover '
    '${discovered.length} managed entrypoints and ${_expectedRouting.length} '
    'routing scenarios.',
  );
}

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
