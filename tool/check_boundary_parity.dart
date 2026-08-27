import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final sourceFixture = Directory('${root.path}/tool/analyzer_plugin_fixture');
  final sandbox = await Directory.systemTemp.createTemp(
    'dartitect-boundary-parity-',
  );
  final fixture = await _prepareFixture(root, sourceFixture, sandbox);
  try {
    await _check(root, fixture);
  } finally {
    await sandbox.delete(recursive: true);
  }
}

Future<void> _check(Directory root, Directory fixture) async {
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
  var modelingRuleObserved = false;
  for (final line in '${analyzed.stdout}'.split(RegExp(r'\r?\n'))) {
    final fields = line.split('|');
    if (fields.length < 8) continue;
    if (fields[2] == 'DARTITECT_DT1032') modelingRuleObserved = true;
    final code = mapping[fields[2]];
    if (code == null) continue;
    final path = boundaryParityRelativePath(fixture, fields[3]);
    plugin.putIfAbsent(path, () => <String>[]).add(code);
  }

  final errors = <String>[];
  if (!modelingRuleObserved) {
    errors.add('Analyzer plugin did not emit the shared DT1032 probe.');
  }
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

Future<Directory> _prepareFixture(
  Directory root,
  Directory sourceFixture,
  Directory sandbox,
) async {
  final fixture = Directory('${sandbox.path}/fixture');
  await _copyDirectory(sourceFixture, fixture);
  final lints = Directory(
    '${root.path}/tool/analyzer_plugin_workspace/dartitect_lints',
  );
  await File('${fixture.path}/analysis_options.yaml').writeAsString('''
plugins:
  dartitect_lints:
    path: ${_yamlPath(lints.path)}
''');
  await File('${fixture.path}/lib/modeling_probe.dart').writeAsString('''
final class DartitectValue {
  const DartitectValue();
}

@DartitectValue()
final class ModelingProbe {
  const ModelingProbe({required this.id});
  final String id;
}
''');
  return fixture;
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}

String _yamlPath(String path) => jsonEncode(path.replaceAll('\\', '/'));

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
  final file = switch (uri) {
    Uri(scheme: 'file') => File.fromUri(uri),
    _ when File(path).isAbsolute => File(path),
    _ => File.fromUri(root.absolute.uri.resolve(path.replaceAll('\\', '/'))),
  };
  final rootPath = _normalizedBoundaryPath(root.absolute.path);
  final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
  final filePath = _normalizedBoundaryPath(file.absolute.path);
  final comparedPrefix = Platform.isWindows ? prefix.toLowerCase() : prefix;
  final comparedFilePath = Platform.isWindows
      ? filePath.toLowerCase()
      : filePath;
  if (!comparedFilePath.startsWith(comparedPrefix)) {
    throw FormatException(
      'Analyzer path is outside the parity fixture: '
      'root=${root.absolute.uri}, input=${jsonEncode(path)}, '
      'resolved=${file.absolute.uri}.',
    );
  }
  return filePath.substring(prefix.length);
}

String _normalizedBoundaryPath(String path) {
  var normalized = path.replaceAll('\\', '/');
  if (Platform.isWindows &&
      (normalized.startsWith('//?/') || normalized.startsWith('//./'))) {
    normalized = normalized.substring(4);
  }
  return normalized.replaceAll(RegExp('/+'), '/');
}

bool _same(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
