import 'dart:convert';
import 'dart:io';

/// Verifies publish-facing package files, translations, and local links.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  final release = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (release is! Map<String, Object?> || release['cohortVersion'] is! String) {
    throw const FormatException('Invalid package release cohort.');
  }
  final expectedVersion = release['cohortVersion']! as String;
  final packages = await Directory('${root.path}/packages')
      .list(followLinks: false)
      .where((entity) => entity is Directory)
      .cast<Directory>()
      .where((directory) => File('${directory.path}/pubspec.yaml').existsSync())
      .toList();
  packages.sort((left, right) => left.path.compareTo(right.path));
  if (packages.length != 16) {
    errors.add('Expected 16 publishable packages; found ${packages.length}.');
  }

  for (final package in packages) {
    final pubspec = File('${package.path}/pubspec.yaml');
    final source = await pubspec.readAsString();
    final name = _field(source, 'name');
    final version = _field(source, 'version');
    final description = _field(source, 'description');
    if (name == null || name.isEmpty) errors.add('${package.path}: no name.');
    if (description == null || description.length < 40) {
      errors.add('${name ?? package.path}: description is too short.');
    }
    if (version != expectedVersion) {
      errors.add('$name: expected version $expectedVersion, found $version.');
    }
    for (final field in const <String>['repository', 'issue_tracker']) {
      if (_field(source, field) == null) errors.add('$name: missing $field.');
    }
    final inlineTopics = RegExp(
      r'^topics:\s*\[([^\]]+)\]\s*$',
      multiLine: true,
    ).firstMatch(source);
    final topicCount = inlineTopics == null
        ? RegExp(
            r'^  - [a-z0-9-]+\s*$',
            multiLine: true,
          ).allMatches(source).length
        : inlineTopics
              .group(1)!
              .split(',')
              .where((topic) => topic.trim().isNotEmpty)
              .length;
    if (topicCount < 3) {
      errors.add('$name: at least three topics are required.');
    }
    for (final fileName in const <String>[
      'README.md',
      'README.pt-BR.md',
      'CHANGELOG.md',
      'LICENSE',
    ]) {
      if (!await File('${package.path}/$fileName').exists()) {
        errors.add('$name: missing $fileName.');
      }
    }
    final example = Directory('${package.path}/example');
    if (!await example.exists() ||
        await example.list(followLinks: false).isEmpty) {
      errors.add('$name: example/ is missing or empty.');
    }
    await _checkTranslationPair(
      File('${package.path}/README.md'),
      File('${package.path}/README.pt-BR.md'),
      errors,
    );
  }

  await _checkTranslationPair(
    File('${root.path}/README.md'),
    File('${root.path}/README.pt-BR.md'),
    errors,
  );
  final guides = await Directory('${root.path}/docs/guides')
      .list(followLinks: false)
      .where(
        (entity) =>
            entity is File &&
            entity.path.endsWith('.md') &&
            !entity.path.endsWith('.pt-BR.md'),
      )
      .cast<File>()
      .toList();
  for (final guide in guides) {
    final translated = File(
      guide.path.substring(0, guide.path.length - '.md'.length) + '.pt-BR.md',
    );
    await _checkTranslationPair(guide, translated, errors);
  }

  final markdown = await root
      .list(recursive: true, followLinks: false)
      .where(
        (entity) =>
            entity is File &&
            entity.path.endsWith('.md') &&
            !_ignored(entity.path, root.path),
      )
      .cast<File>()
      .toList();
  for (final document in markdown) {
    await _checkLocalLinks(document, errors);
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Public docs passed: ${packages.length} packages, '
    '${guides.length} translated guides, ${markdown.length} Markdown files.',
  );
}

String? _field(String source, String name) => RegExp(
  '^${RegExp.escape(name)}:\\s*(.+?)\\s*\$',
  multiLine: true,
).firstMatch(source)?.group(1);

Future<void> _checkTranslationPair(
  File canonical,
  File translated,
  List<String> errors,
) async {
  if (!await canonical.exists()) {
    errors.add('Missing canonical document: ${canonical.path}.');
    return;
  }
  if (!await translated.exists()) {
    errors.add('Missing pt-BR translation for ${canonical.path}.');
    return;
  }
  final canonicalStructure = _headingStructure(await canonical.readAsString());
  final translatedStructure = _headingStructure(
    await translated.readAsString(),
  );
  if (!_sameInts(canonicalStructure, translatedStructure)) {
    errors.add(
      'Heading structure differs: ${canonical.path} and ${translated.path}.',
    );
  }
}

List<int> _headingStructure(String source) => source
    .split(RegExp(r'\r?\n'))
    .map((line) => RegExp(r'^(#{1,6})\s+').firstMatch(line)?.group(1)?.length)
    .whereType<int>()
    .toList(growable: false);

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<void> _checkLocalLinks(File document, List<String> errors) async {
  final source = await document.readAsString();
  for (final match in RegExp(r'\[[^\]]+\]\(([^)]+)\)').allMatches(source)) {
    var target = match.group(1)!.trim();
    if (target.startsWith('<') && target.endsWith('>')) {
      target = target.substring(1, target.length - 1);
    }
    if (target.isEmpty ||
        target.startsWith('#') ||
        target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('mailto:')) {
      continue;
    }
    target = target.split('#').first;
    try {
      target = Uri.decodeComponent(target);
    } on FormatException {
      errors.add('${document.path}: invalid encoded link $target.');
      continue;
    }
    final resolved = File('${document.parent.path}/$target');
    if (!await FileSystemEntity.isFile(resolved.path) &&
        !await FileSystemEntity.isDirectory(resolved.path)) {
      errors.add('${document.path}: broken local link $target.');
    }
  }
}

bool _ignored(String path, String root) {
  final relative = path
      .substring(root.length + 1)
      .replaceAll(Platform.pathSeparator, '/');
  return relative.startsWith('.dart_tool/') ||
      relative.startsWith('build/') ||
      relative.contains('/build/') ||
      relative.startsWith('docs/api/');
}
