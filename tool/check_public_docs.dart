import 'dart:convert';
import 'dart:io';

/// Verifies English publish-facing documents, metadata, coverage, and links.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  final release = _object(
    jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ),
  );
  final expectedVersion = release['cohortVersion'];
  if (expectedVersion is! String) {
    throw const FormatException('Invalid package release cohort.');
  }

  final platforms = _object(
    jsonDecode(
      File('${root.path}/docs/mcp/package-platforms.json').readAsStringSync(),
    ),
  );
  final platformPackages = _object(platforms['packages']);
  final snapshot = _object(
    jsonDecode(
      File('${root.path}/tool/api_surface.snapshot.json').readAsStringSync(),
    ),
  );
  final entrypoints = _object(snapshot['entrypoints']).keys.toList();

  final packages = await Directory('${root.path}/packages')
      .list(followLinks: false)
      .where((entity) => entity is Directory)
      .cast<Directory>()
      .where((directory) => File('${directory.path}/pubspec.yaml').existsSync())
      .toList();
  packages.sort((left, right) => left.path.compareTo(right.path));
  if (packages.length != 24) {
    errors.add('Expected 24 publishable packages; found ${packages.length}.');
  }

  for (final package in packages) {
    final pubspec = File('${package.path}/pubspec.yaml');
    final source = await pubspec.readAsString();
    final name = _field(source, 'name');
    final version = _field(source, 'version');
    final description = _field(source, 'description');
    if (name == null || name.isEmpty) {
      errors.add('${package.path}: no name.');
      continue;
    }
    if (description == null || description.length < 40) {
      errors.add('$name: description is too short.');
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

    final readme = File('${package.path}/README.md');
    if (await readme.exists()) {
      await _checkPackageReadme(readme, name, errors);
    }
    if (!platformPackages.containsKey(name)) {
      errors.add('$name: missing platform metadata.');
    }

    final relative = package.path
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (!entrypoints.any((path) => path.startsWith('$relative/lib/'))) {
      errors.add('$name: public API snapshot has no package entrypoint.');
    }
  }
  if (platformPackages.length != packages.length) {
    errors.add(
      'Platform metadata has ${platformPackages.length} packages; '
      'expected ${packages.length}.',
    );
  }

  for (final required in const <String>[
    'README.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    'CODE_OF_CONDUCT.md',
  ]) {
    if (!File('${root.path}/$required').existsSync()) {
      errors.add('Missing English repository document: $required.');
    }
  }

  final guides = await Directory('${root.path}/docs/guides')
      .list(followLinks: false)
      .where((entity) => entity is File && entity.path.endsWith('.md'))
      .cast<File>()
      .toList();
  guides.sort((left, right) => left.path.compareTo(right.path));
  if (guides.length != 21) {
    errors.add('Expected 21 English guides; found ${guides.length}.');
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
    'Public docs passed: ${packages.length} package READMEs, '
    '${guides.length} English guides, ${markdown.length} linked Markdown files.',
  );
}

const _requiredPackageHeadings = <String>[
  '## Purpose',
  '## When to use',
  '## When not to use',
  '## Platforms and entrypoints',
  '## Mental model and data flow',
  '## Minimal workflow',
  '## Public API tour',
  '## Ownership and lifecycle',
  '## Failure, cancellation, and concurrency',
  '## Prohibited uses and limitations',
  '## Testing',
  '## Related packages and guides',
  '## Availability',
];

Future<void> _checkPackageReadme(
  File readme,
  String packageName,
  List<String> errors,
) async {
  final source = await readme.readAsString();
  final lines = source.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || lines.first != '# $packageName') {
    errors.add('$packageName: README title must be "# $packageName".');
  }
  var previous = -1;
  for (final heading in _requiredPackageHeadings) {
    final matches = <int>[
      for (var index = 0; index < lines.length; index += 1)
        if (lines[index] == heading) index,
    ];
    if (matches.length != 1) {
      errors.add(
        '$packageName: README must contain exactly one "$heading" heading.',
      );
      continue;
    }
    if (matches.single <= previous) {
      errors.add('$packageName: README heading is out of order: $heading.');
    }
    previous = matches.single;
  }

  final purpose = _section(lines, '## Purpose');
  if (purpose.length < 40) {
    errors.add('$packageName: README Purpose is too short.');
  }
}

String _section(List<String> lines, String heading) {
  final start = lines.indexOf(heading);
  if (start < 0) return '';
  final result = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ')) break;
    if (line.trim().isNotEmpty) result.add(line.trim());
  }
  return result.join(' ');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

String? _field(String source, String name) => RegExp(
  '^${RegExp.escape(name)}:\\s*(.+?)\\s*\$',
  multiLine: true,
).firstMatch(source)?.group(1);

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
      relative.startsWith('.private/') ||
      relative.startsWith('build/') ||
      relative.contains('/build/') ||
      relative.startsWith('docs/api/');
}
