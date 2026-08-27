import 'dart:convert';
import 'dart:io';

const _expectedIdentity = 'ftr\u0000ftr@tuta.com';
const _expectedSubject = 'release: establish Dartitect 1.0.0-rc.2 baseline';

/// Audits the one-root Git candidate before its public tag is created.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];

  final status = await _git(root, const <String>[
    'status',
    '--porcelain=v1',
    '--untracked-files=all',
  ]);
  if (status.trim().isNotEmpty) errors.add('The candidate tree is not clean.');

  final branches = _lines(
    await _git(root, const <String>[
      'for-each-ref',
      '--format=%(refname:short)',
      'refs/heads',
    ]),
  );
  if (branches.length != 1 || branches.single != 'main') {
    errors.add('The candidate must contain only the main branch: $branches.');
  }
  final commits = (await _git(root, const <String>[
    'rev-list',
    '--all',
    '--count',
  ])).trim();
  if (commits != '1') errors.add('The candidate must contain one commit.');

  final rootLine = (await _git(root, const <String>[
    'rev-list',
    '--parents',
    '--max-count=1',
    'HEAD',
  ])).trim();
  if (rootLine.split(RegExp(r'\s+')).length != 1) {
    errors.add('HEAD is not a root commit.');
  }
  final identity = (await _git(root, const <String>[
    'show',
    '-s',
    '--format=%an%x00%ae%n%cn%x00%ce%n%s',
    'HEAD',
  ])).trimRight().split('\n');
  if (identity.length != 3 ||
      identity[0] != _expectedIdentity ||
      identity[1] != _expectedIdentity ||
      identity[2] != _expectedSubject) {
    errors.add('Root authorship, committer identity, or subject is invalid.');
  }

  final tracked = _lines(await _git(root, const <String>['ls-files']));
  for (final path in tracked) {
    final segments = path.split('/');
    if (segments.contains('.private') ||
        segments.contains('.dart_tool') ||
        segments.contains('build') ||
        path.endsWith('.pem') ||
        path.endsWith('.key')) {
      errors.add('Forbidden tracked candidate path: $path.');
    }
  }

  final narrativeFiles = <File>[
    for (final path in tracked)
      if (_isNarrative(path)) File('${root.path}/$path'),
  ];
  for (final file in narrativeFiles) {
    final source = await file.readAsString();
    final relative = file.path.substring(root.path.length + 1);
    if (source.contains('1.0.0-dev.') ||
        RegExp(
          r'https://github\.com/ftr-tuta/dartitect/(pull|actions/runs)/\d+',
        ).hasMatch(source) ||
        RegExp(r'/(home|Users)/[^/\s]+/').hasMatch(source) ||
        RegExp(r'[A-Za-z]:\\Users\\[^\\\s]+\\').hasMatch(source) ||
        RegExp(
          r'(Dartitect|this (project|repository)).{0,40}MIT License',
          caseSensitive: false,
        ).hasMatch(source)) {
      errors.add('Discarded-history or private-path reference in $relative.');
    }
  }

  final licensePaths = <String>['LICENSE'];
  final packages = <Directory>[];
  await for (final entity in Directory('${root.path}/packages').list()) {
    if (entity is Directory &&
        await File('${entity.path}/pubspec.yaml').exists()) {
      packages.add(entity);
      licensePaths.add(
        '${entity.path.substring(root.path.length + 1)}/LICENSE',
      );
    }
  }
  if (packages.length != 17) errors.add('Expected exactly 17 packages.');
  for (final path in licensePaths) {
    final license = File('${root.path}/$path');
    if (!await license.exists() ||
        !(await license.readAsString()).startsWith('BSD 3-Clause License\n')) {
      errors.add('$path is not the BSD-3-Clause project license.');
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  final sha = (await _git(root, const <String>['rev-parse', 'HEAD'])).trim();
  final tree = (await _git(root, const <String>[
    'show',
    '-s',
    '--format=%T',
    'HEAD',
  ])).trim();
  stdout.writeln(
    'Root candidate audit passed: $sha tree $tree; one main branch, one '
    'canonical root, BSD-3-Clause only, no private paths, clean tree.',
  );
}

bool _isNarrative(String path) =>
    path == 'README.md' ||
    path == 'README.pt-BR.md' ||
    path.startsWith('docs/') ||
    (path.startsWith('packages/') &&
        (path.endsWith('/README.md') ||
            path.endsWith('/README.pt-BR.md') ||
            path.endsWith('/CHANGELOG.md')));

List<String> _lines(String value) => const LineSplitter()
    .convert(value)
    .where((line) => line.trim().isNotEmpty)
    .toList(growable: false);

Future<String> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}
