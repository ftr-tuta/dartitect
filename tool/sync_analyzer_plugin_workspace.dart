import 'dart:io';

/// Synchronizes the local Analyzer-isolate mirrors for unpublished packages.
Future<void> main(List<String> arguments) async {
  final update = arguments.contains('--update');
  if (arguments.any((argument) => argument != '--update')) {
    stderr.writeln(
      'Usage: dart run tool/sync_analyzer_plugin_workspace.dart [--update]',
    );
    exitCode = 2;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final mappings = <({Directory source, Directory target})>[
    (
      source: Directory(
        '${root.path}/packages/dartitect_modeling_analyzer/lib',
      ),
      target: Directory(
        '${root.path}/tool/analyzer_plugin_workspace/'
        'dartitect_modeling_analyzer/lib',
      ),
    ),
    (
      source: Directory('${root.path}/packages/dartitect_lints/lib'),
      target: Directory(
        '${root.path}/tool/analyzer_plugin_workspace/dartitect_lints/lib',
      ),
    ),
  ];
  final errors = <String>[];
  var fileCount = 0;
  for (final mapping in mappings) {
    final sourceFiles = await _dartFiles(mapping.source);
    final targetFiles = await _dartFiles(mapping.target);
    final expected = <String, File>{
      for (final file in sourceFiles) _relative(mapping.source, file): file,
    };
    final actual = <String, File>{
      for (final file in targetFiles) _relative(mapping.target, file): file,
    };
    fileCount += expected.length;
    if (update) {
      for (final entry in expected.entries) {
        final target = File('${mapping.target.path}/${entry.key}');
        await target.parent.create(recursive: true);
        await entry.value.copy(target.path);
      }
      for (final entry in actual.entries) {
        if (!expected.containsKey(entry.key)) await entry.value.delete();
      }
      continue;
    }
    for (final entry in expected.entries) {
      final target = actual[entry.key];
      if (target == null) {
        errors.add('Missing analyzer-plugin mirror: ${entry.key}.');
      } else {
        final sourceBytes = await entry.value.readAsBytes();
        final targetBytes = await target.readAsBytes();
        if (!_sameBytes(sourceBytes, targetBytes)) {
          errors.add('Stale analyzer-plugin mirror: ${entry.key}.');
        }
      }
    }
    for (final path in actual.keys) {
      if (!expected.containsKey(path)) {
        errors.add('Orphan analyzer-plugin mirror: $path.');
      }
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    stderr.writeln(
      'Run dart run tool/sync_analyzer_plugin_workspace.dart --update.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    '${update ? 'Updated' : 'Verified'} $fileCount Analyzer plugin mirror files.',
  );
}

Future<List<File>> _dartFiles(Directory directory) async {
  if (!await directory.exists()) return <File>[];
  final files = await directory
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File && entity.path.endsWith('.dart'))
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

String _relative(Directory root, File file) => file.path
    .substring(root.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
