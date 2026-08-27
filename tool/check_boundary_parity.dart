import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final fixture = Directory('${root.path}/tool/analyzer_plugin_fixture');
  final corpus = _object(
    jsonDecode(
      await File('${root.path}/tool/boundary_parity_corpus.json')
          .readAsString(),
    ),
  );
  if (corpus['schemaVersion'] != 1) {
    throw const FormatException('Unsupported boundary parity corpus schema.');
  }
  final mapping = _object(corpus['diagnosticMap']).cast<String, String>();
  final cases = _list(corpus['cases']).map(_object).toList();
  final budget = _object(corpus['performanceBudget']);
  final scannerWatch = Stopwatch()..start();
  final scan = await ProjectScanner(fixture).scan();
  scannerWatch.stop();
  final scanner = <String, List<String>>{};
  final sharedCodes = mapping.values.toSet();
  for (final violation in scan.violations) {
    if (!sharedCodes.contains(violation.code) || violation.path == null)
      continue;
    scanner.putIfAbsent(violation.path!, () => <String>[]).add(violation.code);
  }

  final analyzerWatch = Stopwatch()..start();
  final analyzed = await Process.run(
    Platform.resolvedExecutable,
    const <String>['analyze', '--format', 'machine'],
    workingDirectory: fixture.path,
  );
  analyzerWatch.stop();
  if (analyzed.exitCode != 0) {
    stderr
      ..write(analyzed.stdout)
      ..write(analyzed.stderr);
    throw StateError('Analyzer parity fixture did not complete cleanly.');
  }
  final plugin = <String, List<String>>{};
  for (final line in '${analyzed.stdout}'.split(RegExp(r'\r?\n'))) {
    final fields = line.split('|');
    if (fields.length < 8) continue;
    final code = mapping[fields[2]];
    if (code == null) continue;
    final path = boundaryParityRelativePath(fixture, fields[3]);
    plugin.putIfAbsent(path, () => <String>[]).add(code);
  }

  final errors = <String>[];
  final casePaths = <String>{};
  for (final testCase in cases) {
    final path = testCase['path'];
    final expected = _list(testCase['expected']).cast<String>()..sort();
    if (path is! String || !path.startsWith('lib/') || !casePaths.add(path)) {
      errors.add('Invalid or duplicate parity case path: $path.');
      continue;
    }
    final scannerCodes = <String>[...?scanner[path]]..sort();
    final pluginCodes = <String>[...?plugin[path]]..sort();
    if (!_same(expected, scannerCodes)) {
      errors.add('$path scanner: expected $expected, found $scannerCodes.');
    }
    if (!_same(expected, pluginCodes)) {
      errors.add('$path plugin: expected $expected, found $pluginCodes.');
    }
  }
  for (final path in <String>{
    ...scanner.keys,
    ...plugin.keys,
  }.difference(casePaths)) {
    errors.add('Unregistered shared diagnostic path: $path.');
  }
  final scannerLimit = budget['scannerMilliseconds'];
  final analyzerLimit = budget['analyzerMilliseconds'];
  if (scannerLimit is! int || scannerWatch.elapsedMilliseconds > scannerLimit) {
    errors.add(
      'Scanner budget exceeded: ${scannerWatch.elapsedMilliseconds} ms / '
      '$scannerLimit ms.',
    );
  }
  if (analyzerLimit is! int ||
      analyzerWatch.elapsedMilliseconds > analyzerLimit) {
    errors.add(
      'Analyzer budget exceeded: ${analyzerWatch.elapsedMilliseconds} ms / '
      '$analyzerLimit ms.',
    );
  }
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Boundary parity passed ${cases.length} cases; scanner '
    '${scannerWatch.elapsedMilliseconds} ms, analyzer '
    '${analyzerWatch.elapsedMilliseconds} ms.',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON array.');
  }
  return value;
}

/// Normalizes analyzer machine-format paths relative to [root].
///
/// The analyzer may emit a native absolute path or a `file:` URI. Handling
/// both forms avoids interpreting the URI text as a relative Windows path.
String boundaryParityRelativePath(Directory root, String path) {
  final uri = Uri.tryParse(path);
  final file = uri != null && uri.scheme == 'file'
      ? File.fromUri(uri)
      : File(path);
  final rootPath = root.absolute.path;
  final prefix = rootPath.endsWith(Platform.pathSeparator)
      ? rootPath
      : '$rootPath${Platform.pathSeparator}';
  final filePath = file.absolute.path;
  final comparedPrefix = Platform.isWindows ? prefix.toLowerCase() : prefix;
  final comparedFilePath = Platform.isWindows
      ? filePath.toLowerCase()
      : filePath;
  if (!comparedFilePath.startsWith(comparedPrefix)) {
    throw FormatException('Analyzer path is outside the parity fixture.');
  }
  return filePath.substring(prefix.length).replaceAll('\\', '/');
}

bool _same(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
