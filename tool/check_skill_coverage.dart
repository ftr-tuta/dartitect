import 'dart:convert';
import 'dart:io';

import '../packages/dartitect_cli/lib/src/codex/skill_catalog.dart';

final Set<String> _expectedSkills = dartitectSkillCatalog
    .map((skill) => skill.name)
    .toSet();

const _expectedRouting = <String, String>{
  'greenfield': 'dartitect-design',
  'conformanceAudit': 'dartitect-audit',
  'simpleFlutterRuntime': 'dartitect-runtime',
  'reactiveRuntime': 'dartitect-reactive',
  'offlineOutbox': 'dartitect-offline-first',
  'providerAdapters': 'dartitect-adapters',
  'telemetry': 'dartitect-observability',
  'testing': 'dartitect-testing',
  'cliAndLints': 'dartitect-tooling',
  'localMcp': 'dartitect-mcp',
  'immutableModels': 'dartitect-modeling',
  'flutterPresentation': 'dartitect-ui',
  'dartRuntimeSemantics': 'dartitect-dart',
  'incrementalOperations': 'dartitect-incremental',
  'runtimePerformance': 'dartitect-performance',
};

Future<void> main(List<String> arguments) async {
  final root = _root(arguments);
  final release = jsonDecode(
    await File('${root.path}/tool/package_release_contract.json')
        .readAsString(),
  );
  if (release is! Map<String, Object?> ||
      release['workspaceCohort'] is! Map<String, Object?>) {
    throw const FormatException('Invalid package release cohort.');
  }
  final workspace = release['workspaceCohort']! as Map<String, Object?>;
  final cohort = workspace['version'];
  if (cohort is! String) {
    throw const FormatException('Invalid workspace release cohort.');
  }
  final releasePackages = release['packages'];
  if (releasePackages is! Map<String, Object?>) {
    throw const FormatException('Invalid release package inventory.');
  }
  final manifest = jsonDecode(
    await File('${root.path}/tool/skill_coverage.json').readAsString(),
  );
  if (manifest is! Map<String, Object?> || manifest['schemaVersion'] != 2) {
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
  if (_expectedSkills.length != dartitectSkillCatalog.length) {
    stderr.writeln('Canonical managed skill names must be unique.');
    exitCode = 1;
  }
  if (!_sameStrings(skillNames, _expectedSkills)) {
    stderr.writeln(
      'Managed skills differ: expected ${_expectedSkills.toList()..sort()}, '
      'found ${skillNames.toList()..sort()}.',
    );
    exitCode = 1;
  }

  final designPackages = manifest['designPackages'];
  if (designPackages is! List<Object?> ||
      designPackages.any((item) => item is! String) ||
      !_sameStrings(
        designPackages.whereType<String>().toSet(),
        releasePackages.keys.toSet(),
      )) {
    stderr.writeln('Design package matrix must cover all 25 release packages.');
    exitCode = 1;
  }

  final rawReferenceRequirements = manifest['referenceRequirements'];
  if (rawReferenceRequirements is! Map<String, Object?> ||
      !_sameStrings(rawReferenceRequirements.keys.toSet(), _expectedSkills)) {
    stderr.writeln('Reference requirements must cover all managed skills.');
    exitCode = 1;
  }

  final routing = manifest['routingScenarios'];
  if (routing is! Map<String, Object?> ||
      !_sameStrings(routing.keys.toSet(), _expectedRouting.keys.toSet())) {
    stderr.writeln(
      'Routing scenarios must cover all ${_expectedRouting.length} supported '
      'workflows.',
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

  final desiredSkills = buildDartitectManagedSkillFiles();
  final referenceRequirements = rawReferenceRequirements is Map<String, Object?>
      ? rawReferenceRequirements
      : const <String, Object?>{};
  final selectionMatrix =
      desiredSkills['dartitect-design']?['references/selection-matrix.md'] ??
      '';
  final packagesMissingFromDesign =
      releasePackages.keys
          .where((name) => !selectionMatrix.contains('`$name`'))
          .toList()
        ..sort();
  if (packagesMissingFromDesign.isNotEmpty) {
    stderr.writeln(
      'Design selection matrix omits: ${packagesMissingFromDesign.join(', ')}.',
    );
    exitCode = 1;
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
    final displayName = _quotedYamlValue(metadataSource, 'display_name');
    final shortDescription = _quotedYamlValue(
      metadataSource,
      'short_description',
    );
    final defaultPrompt = _quotedYamlValue(metadataSource, 'default_prompt');
    if (displayName == null ||
        !displayName.startsWith('Dartitect ') ||
        shortDescription == null ||
        shortDescription.length < 25 ||
        shortDescription.length > 64 ||
        defaultPrompt == null ||
        !defaultPrompt.startsWith('Use \$${entry.key} ') ||
        RegExp(
              r'^policy:\n  allow_implicit_invocation: true$',
              multiLine: true,
            ).allMatches(metadataSource).length !=
            1) {
      stderr.writeln('Invalid Codex metadata for ${entry.key}.');
      exitCode = 1;
    }
    final managedManifest = jsonDecode(await manifestFile.readAsString());
    String? recordedHash;
    if (managedManifest is! Map<String, Object?> ||
        managedManifest['schemaVersion'] != 1 ||
        managedManifest['sdkVersion'] != cohort ||
        managedManifest['contentHash'] is! String ||
        !RegExp(r'^[0-9a-f]{8}$')
            .hasMatch(managedManifest['contentHash']! as String)) {
      stderr.writeln('Invalid managed-skill manifest for ${entry.key}.');
      exitCode = 1;
    } else {
      recordedHash = managedManifest['contentHash']! as String;
    }

    final actualSkillFiles = await _skillFiles(skill);
    final desiredSkillFiles = desiredSkills[entry.key];
    if (desiredSkillFiles == null ||
        !_sameStrings(
          actualSkillFiles.keys.toSet(),
          desiredSkillFiles.keys.toSet(),
        ) ||
        desiredSkillFiles.entries.any(
          (file) => actualSkillFiles[file.key] != file.value,
        )) {
      stderr.writeln(
        'Managed skill snapshot diverges from canonical catalog: ${entry.key}.',
      );
      exitCode = 1;
    }
    final actualHash = _hashFiles(actualSkillFiles);
    if (recordedHash != null && recordedHash != actualHash) {
      stderr.writeln('Stale managed-skill content hash for ${entry.key}.');
      exitCode = 1;
    }

    final declaredReferences = referenceRequirements[entry.key];
    final declaredReferenceSet =
        declaredReferences is List<Object?> &&
            declaredReferences.every((item) => item is String)
        ? declaredReferences.cast<String>().toSet()
        : <String>{};
    final actualReferenceSet = actualSkillFiles.keys
        .where((path) => path.startsWith('references/') && path.endsWith('.md'))
        .toSet();
    final linkedReferenceSet = RegExp(
      r'\[[^\]]+\]\((references/[^)#]+\.md)(?:#[^)]+)?\)',
    ).allMatches(entrypointSource).map((match) => match.group(1)!).toSet();
    if (!_sameStrings(declaredReferenceSet, actualReferenceSet) ||
        !_sameStrings(declaredReferenceSet, linkedReferenceSet)) {
      stderr.writeln(
        'Skill references are not fully declared and linked for ${entry.key}.',
      );
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

  final localSkill = Directory(
    '${root.path}/.agents/skills/repository-contribution',
  );
  final localEntrypoint = File('${localSkill.path}/SKILL.md');
  final localMetadata = File('${localSkill.path}/agents/openai.yaml');
  final localManifest = File('${localSkill.path}/.dartitect-skill.json');
  if (!await localEntrypoint.exists() ||
      !await localMetadata.exists() ||
      await localManifest.exists() ||
      !await localEntrypoint.readAsString().then(
        (source) => source.startsWith(
          '---\nname: repository-contribution\ndescription: ',
        ),
      )) {
    stderr.writeln('Invalid consumer-owned repository-contribution skill.');
    exitCode = 1;
  }

  if (arguments.contains('--skills-only')) {
    if (exitCode == 0) {
      stdout.writeln(
        'Skill contract passed for ${rawSkills.length} managed skills plus '
        'repository-contribution (${rawSkills.length + 1} total).',
      );
    }
    return;
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
    'Skill coverage passed: ${rawSkills.length} managed skills cover '
    '${discovered.length} managed entrypoints and ${_expectedRouting.length} '
    'routing scenarios; repository-contribution brings the validated total to '
    '${rawSkills.length + 1}.',
  );
}

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

Directory _root(List<String> arguments) {
  final remaining = arguments
      .where((argument) => argument != '--skills-only')
      .toList();
  if (remaining.isEmpty) {
    return File.fromUri(Platform.script).parent.parent.absolute;
  }
  if (remaining.length == 2 && remaining.first == '--root') {
    return Directory(remaining[1]).absolute;
  }
  throw const FormatException(
    'Usage: dart run tool/check_skill_coverage.dart [--root PATH] [--skills-only]',
  );
}

String? _quotedYamlValue(String source, String field) => RegExp(
  '^  ${RegExp.escape(field)}: "([^"]*)"\$',
  multiLine: true,
).firstMatch(source)?.group(1);

Future<Map<String, String>> _skillFiles(Directory skill) async {
  final files = <String, String>{};
  await for (final entity in skill.list(recursive: true, followLinks: false)) {
    if (entity is! File || _basename(entity.path) == '.dartitect-skill.json') {
      continue;
    }
    final relative = entity.path
        .substring(skill.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    files[relative] = await entity.readAsString();
  }
  return files;
}

String _hashFiles(Map<String, String> files) {
  final keys = files.keys.toList()..sort();
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(
    keys.map((key) => '$key\u0000${files[key]}').join('\u0000'),
  )) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _basename(String path) =>
    path.split(Platform.pathSeparator).where((part) => part.isNotEmpty).last;
