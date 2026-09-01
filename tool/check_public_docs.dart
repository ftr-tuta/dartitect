import 'dart:convert';
import 'dart:io';

/// Verifies English publish-facing documents, metadata, coverage, and links.
Future<void> main(List<String> arguments) async {
  final root = _root(arguments);
  final errors = <String>[];
  final classifiedDocuments = await _checkDocumentationContract(root, errors);
  if (arguments.contains('--content-only')) {
    if (errors.isNotEmpty) {
      stderr.writeln(errors.join('\n'));
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Documentation contract passed for $classifiedDocuments files.',
    );
    return;
  }
  final release = _object(
    jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ),
  );
  final expectedPackageCount = release['packageCount'];
  final releasePackages = release['packages'];
  if (expectedPackageCount is! int ||
      releasePackages is! Map<String, Object?>) {
    throw const FormatException('Invalid package release metadata.');
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
  if (packages.length != expectedPackageCount) {
    errors.add(
      'Expected $expectedPackageCount publishable packages; '
      'found ${packages.length}.',
    );
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
    final releasePackage = releasePackages[name];
    final expectedVersion = releasePackage is Map<String, Object?>
        ? releasePackage['version']
        : null;
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
  if (guides.length != 25) {
    errors.add('Expected 25 English guides; found ${guides.length}.');
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

Directory _root(List<String> arguments) {
  final remaining = arguments
      .where((argument) => argument != '--content-only')
      .toList();
  if (remaining.isEmpty) {
    return File.fromUri(Platform.script).parent.parent.absolute;
  }
  if (remaining.length == 2 && remaining.first == '--root') {
    return Directory(remaining[1]).absolute;
  }
  throw const FormatException(
    'Usage: dart run tool/check_public_docs.dart [--root PATH] [--content-only]',
  );
}

Future<int> _checkDocumentationContract(
  Directory root,
  List<String> errors,
) async {
  final contractFile = File('${root.path}/tool/documentation_contract.json');
  if (!await contractFile.exists()) {
    errors.add('Missing tool/documentation_contract.json.');
    return 0;
  }
  final decoded = jsonDecode(await contractFile.readAsString());
  if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
    errors.add('Invalid documentation contract.');
    return 0;
  }
  final roots = decoded['roots'];
  if (roots is! List<Object?> ||
      roots.any((item) => item is! String) ||
      !_sameStrings(roots.whereType<String>().toSet(), const <String>{
        '.',
        'docs',
        'packages',
        'examples',
        '.agents/skills',
      })) {
    errors.add('Documentation contract roots are incomplete.');
  }
  final rawClassifications = decoded['classifications'];
  if (rawClassifications is! Map<String, Object?> ||
      !_sameStrings(rawClassifications.keys.toSet(), const <String>{
        'current',
        'migration-entry',
        'historical',
        'generated',
      })) {
    errors.add(
      'Documentation classifications must be current, migration-entry, '
      'historical, and generated.',
    );
    return 0;
  }
  final classifications = <String, List<String>>{};
  for (final entry in rawClassifications.entries) {
    final patterns = entry.value;
    if (patterns is! List<Object?> || patterns.any((item) => item is! String)) {
      errors.add('Invalid documentation patterns for ${entry.key}.');
      continue;
    }
    classifications[entry.key] = patterns.cast<String>();
  }
  final excluded = _contractStrings(decoded['excluded'], 'excluded', errors);
  final rcExclusions = _contractStrings(
    decoded['activeReleaseCandidateExclusions'],
    'activeReleaseCandidateExclusions',
    errors,
  );

  final documents = await _documentationFiles(root);
  final guideFormats = <String, Set<String>>{};
  for (final document in documents) {
    final relative = _relativePath(root, document.path);
    if (excluded.any((pattern) => _matchesGlob(relative, pattern))) continue;
    final matching = <String>[
      for (final entry in classifications.entries)
        if (entry.value.any((pattern) => _matchesGlob(relative, pattern)))
          entry.key,
    ];
    if (matching.isEmpty) {
      errors.add('$relative: documentation file is not classified.');
      continue;
    }
    if (matching.length > 1) {
      errors.add(
        '$relative: multiple documentation classifications: $matching.',
      );
      continue;
    }
    final classification = matching.single;
    final source = await document.readAsString();
    _checkDocumentIntegrity(document, relative, source, errors);
    await _checkLocalLinks(document, errors);
    await _checkAsciiDocTargets(document, source, errors);
    if (classification == 'current' &&
        !rcExclusions.any((pattern) => _matchesGlob(relative, pattern)) &&
        RegExp(
          r'\b(?:RC\.?3|RC10|1\.0\.0-rc\.\d+)\b',
          caseSensitive: false,
        ).hasMatch(source)) {
      errors.add(
        '$relative: obsolete release-candidate text in current documentation.',
      );
    }
    if (relative.startsWith('docs/guides/')) {
      final fileName = relative.substring('docs/guides/'.length);
      final dot = fileName.lastIndexOf('.');
      if (dot > 0) {
        guideFormats.putIfAbsent(fileName.substring(0, dot), () => <String>{})
          ..add(fileName.substring(dot + 1));
      }
    }
  }
  for (final entry in guideFormats.entries) {
    if (entry.value.length > 1) {
      errors.add(
        'docs/guides/${entry.key}: duplicate guide formats ${entry.value.toList()..sort()}.',
      );
    }
  }
  return documents.length;
}

List<String> _contractStrings(
  Object? value,
  String field,
  List<String> errors,
) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    errors.add('Documentation contract field $field must be a string list.');
    return const <String>[];
  }
  return value.cast<String>();
}

Future<List<File>> _documentationFiles(Directory root) async {
  final files = <File>[];
  await for (final entity in root.list(followLinks: false)) {
    if (entity is File && _isDocumentationFile(entity.path)) files.add(entity);
  }
  for (final relative in const <String>[
    'docs',
    'packages',
    'examples',
    '.agents/skills',
  ]) {
    final directory = Directory('${root.path}/$relative');
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          _isDocumentationFile(entity.path) &&
          !_ignored(entity.path, root.path)) {
        files.add(entity);
      }
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

bool _isDocumentationFile(String path) =>
    path.endsWith('.md') || path.endsWith('.adoc');

String _relativePath(Directory root, String path) => path
    .substring(root.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

bool _matchesGlob(String path, String pattern) {
  final expression = RegExp.escape(pattern).replaceAll(r'\*', r'[^/]*');
  return RegExp('^$expression\$').hasMatch(path);
}

void _checkDocumentIntegrity(
  File file,
  String relative,
  String source,
  List<String> errors,
) {
  if (RegExp(
        r'\b(?:TODO|TBD|FIXME|PLACEHOLDER|CONTENT OMITTED)\b',
        caseSensitive: false,
      ).hasMatch(source) ||
      RegExp(
        r'^(?:\.\.\.|…|\[truncated\]|<!--\s*truncated\s*-->)\s*$',
        multiLine: true,
        caseSensitive: false,
      ).hasMatch(source)) {
    errors.add('$relative: unfinished placeholder or truncation marker.');
  }
  final lines = source.split(RegExp(r'\r?\n'));
  if (file.path.endsWith('.md')) {
    _checkMarkdownFences(lines, relative, errors);
    _checkEmptySections(
      lines,
      relative,
      RegExp(r'^(#{1,6})\s+\S'),
      errors,
      ignoredLines: _markdownFenceLines(lines),
    );
  } else {
    for (final delimiter in const <String>[
      '----',
      '....',
      '====',
      '|===',
      '____',
    ]) {
      if (lines.where((line) => line.trimRight() == delimiter).length.isOdd) {
        errors.add('$relative: unbalanced AsciiDoc block $delimiter.');
      }
    }
    _checkEmptySections(lines, relative, RegExp(r'^(={1,6})\s+\S'), errors);
  }
}

void _checkMarkdownFences(
  List<String> lines,
  String relative,
  List<String> errors,
) {
  String? marker;
  var length = 0;
  for (final line in lines) {
    final match = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
    if (match == null) continue;
    final candidate = match.group(1)!;
    if (marker == null) {
      marker = candidate[0];
      length = candidate.length;
    } else if (candidate[0] == marker && candidate.length >= length) {
      marker = null;
      length = 0;
    }
  }
  if (marker != null) errors.add('$relative: unbalanced Markdown code fence.');
}

void _checkEmptySections(
  List<String> lines,
  String relative,
  RegExp headingPattern,
  List<String> errors, {
  Set<int> ignoredLines = const <int>{},
}) {
  for (var index = 0; index < lines.length; index += 1) {
    if (ignoredLines.contains(index)) continue;
    final heading = headingPattern.firstMatch(lines[index]);
    if (heading == null) continue;
    final level = heading.group(1)!.length;
    var hasContent = false;
    for (var cursor = index + 1; cursor < lines.length; cursor += 1) {
      if (ignoredLines.contains(cursor)) {
        hasContent = true;
        continue;
      }
      final nextHeading = headingPattern.firstMatch(lines[cursor]);
      if (nextHeading != null && nextHeading.group(1)!.length <= level) break;
      if (nextHeading == null && lines[cursor].trim().isNotEmpty) {
        hasContent = true;
        break;
      }
    }
    if (!hasContent) {
      errors.add('$relative: empty section "${lines[index].trim()}".');
    }
  }
}

Set<int> _markdownFenceLines(List<String> lines) {
  final ignored = <int>{};
  String? marker;
  var length = 0;
  for (var index = 0; index < lines.length; index += 1) {
    final match = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(lines[index]);
    if (marker != null) ignored.add(index);
    if (match == null) continue;
    final candidate = match.group(1)!;
    if (marker == null) {
      marker = candidate[0];
      length = candidate.length;
      ignored.add(index);
    } else if (candidate[0] == marker && candidate.length >= length) {
      marker = null;
      length = 0;
    }
  }
  return ignored;
}

Future<void> _checkAsciiDocTargets(
  File document,
  String source,
  List<String> errors,
) async {
  if (!document.path.endsWith('.adoc')) return;
  final targets = <String>[];
  for (final pattern in <RegExp>[
    RegExp(r'include::([^\[]+)\['),
    RegExp(r'(?<![A-Za-z])link:([^\[]+)\['),
    RegExp(r'xref:([^\[]+)\['),
  ]) {
    targets.addAll(pattern.allMatches(source).map((match) => match.group(1)!));
  }
  for (var target in targets) {
    target = target.trim().split('#').first;
    if (target.isEmpty ||
        target.contains('{') ||
        target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('mailto:')) {
      continue;
    }
    final resolved = File('${document.parent.path}/$target');
    if (!await FileSystemEntity.isFile(resolved.path) &&
        !await FileSystemEntity.isDirectory(resolved.path)) {
      errors.add('${document.path}: broken AsciiDoc link/include $target.');
    }
  }
}

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
