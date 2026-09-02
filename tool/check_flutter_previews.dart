import 'dart:convert';
import 'dart:io';

const _expectedPreviews = <String>[
  'pavedRoadQualityPreview',
  'referenceTasksPreview',
  'thinConsumerTasksPreview',
  'dartitectPreviewFixture',
];

/// Compiles and discovers every reviewed preview from a disposable HEAD copy.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/check_flutter_previews.dart');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final temporary = await Directory.systemTemp.createTemp(
    'dartitect-widget-previews-',
  );
  try {
    final source = Directory('${temporary.path}/source');
    await source.create();
    final archive = File('${temporary.path}/source.tar');
    await _run('git', <String>[
      'archive',
      '--format=tar',
      '--output=${archive.path}',
      'HEAD',
    ], root.path);
    await _run('tar', <String>[
      '-xf',
      archive.path,
      '-C',
      source.path,
    ], root.path);
    await _run('flutter', const <String>['pub', 'get'], source.path);
    final preview = await _run('flutter', const <String>[
      'widget-preview',
      'start',
      '--no-launch-previewer',
      '--no-devtools',
      '--no-web-server',
      '--machine',
    ], source.path);
    if (!preview.contains('Done loading previews.')) {
      throw StateError('Widget Previewer did not report completed loading.');
    }

    final manifest = File(
      '${source.path}/.widget_preview/preview_manifest.json',
    );
    final generated = File(
      '${source.path}/.widget_preview/lib/src/generated_preview.dart',
    );
    if (!manifest.existsSync() || !generated.existsSync()) {
      throw StateError('Widget Previewer did not generate its evidence files.');
    }
    final manifestValue = jsonDecode(await manifest.readAsString());
    if (manifestValue is! Map<String, Object?> ||
        manifestValue['version'] is! String ||
        manifestValue['pubspec-hashes'] is! Map<String, Object?>) {
      throw StateError('Unexpected Widget Previewer manifest schema.');
    }
    final generatedSource = await generated.readAsString();
    for (final function in _expectedPreviews) {
      if (!generatedSource.contains('$function()')) {
        throw StateError('Widget Previewer did not discover $function.');
      }
    }
    stdout.writeln(
      'Flutter widget previews passed: ${_expectedPreviews.length} functions '
      'were discovered and compiled from a disposable HEAD copy.',
    );
  } on Object catch (error) {
    stderr.writeln('Flutter widget preview validation failed: $error');
    exitCode = 1;
  } finally {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  }
}

Future<String> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final process = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: <String, String>{
      ...Platform.environment,
      'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    },
    runInShell: Platform.isWindows && executable == 'flutter',
  );
  final output = '${process.stdout}${process.stderr}';
  if (process.exitCode != 0) {
    throw ProcessException(executable, arguments, output, process.exitCode);
  }
  return output;
}
