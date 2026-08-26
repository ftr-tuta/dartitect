import 'dart:convert';
import 'dart:io';

/// Rejects consumer identity and consumer-owned policy from tracked content.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = <String>[];
  final tracked = await Process.run('git', const <String>[
    'ls-files',
    '-z',
  ], workingDirectory: root.path);
  if (tracked.exitCode != 0) {
    stderr.writeln('Unable to enumerate tracked content.');
    exitCode = 1;
    return;
  }
  final paths =
      (tracked.stdout as String)
          .split('\u0000')
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort();
  const checkerPath = 'tool/check_consumer_neutrality.dart';
  if (!paths.contains(checkerPath) &&
      await File('${root.path}/$checkerPath').exists()) {
    paths.add(checkerPath);
  }
  for (final path in paths) {
    final file = File('${root.path}/$path');
    if (!await file.exists()) continue;
    String source;
    try {
      source = await file.readAsString();
    } on FileSystemException {
      continue;
    }
    for (final pattern in _forbidden) {
      if (pattern.hasMatch(source)) {
        errors.add('$path contains consumer-specific public content.');
        break;
      }
    }
  }

  final policy = jsonDecode(
    await File('${root.path}/tool/ecosystem_policy.json').readAsString(),
  );
  final exceptions = policy is Map<String, Object?>
      ? policy['exceptions']
      : null;
  if (exceptions is! List<Object?> || exceptions.isNotEmpty) {
    errors.add(
      'The global ecosystem ledger must not contain consumer exceptions.',
    );
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.toSet().join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Tracked sources, fixtures, examples, snapshots, and policy are '
    'consumer-neutral.',
  );
}

final _forbidden = <RegExp>[
  RegExp(
    r'flutter[_ -]?'
    r'ag'
    r'rox',
    caseSensitive: false,
  ),
  RegExp(
    r'\b'
    r'ag'
    r'rox'
    r'\b',
    caseSensitive: false,
  ),
  RegExp(
    '7bb3741cdc748e7c'
    'b10e9e1770feb843505e363a',
  ),
  RegExp(
    r'\b1[,.]'
    r'117 Dart files\b',
    caseSensitive: false,
  ),
  RegExp(
    r'lib/features/'
    r'productivity',
  ),
  RegExp(
    r'lib/features/'
    r'service_'
    r'orders',
  ),
  RegExp(
    r'lib/features/'
    r'pdf_'
    r'viewer',
  ),
  RegExp(
    r'lib/data/services/'
    r'utils/pdf',
  ),
  RegExp(
    r'/home/'
    r'fabricio(?:/|\b)',
  ),
  RegExp(
    r'Documentos/'
    r'Projetos',
  ),
  RegExp(
    r'[A-Za-z]:\\Users\\'
    r'fabricio',
    caseSensitive: false,
  ),
];
