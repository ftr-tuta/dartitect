import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

const _sizes = <int>[100, 500];
const _commands = <String>['sync', 'check'];
const _coldRuns = 5;
const _warmRuns = 20;
const _maxRegressionPercent = 10.0;

/// Reproducible cold and warm model sync/check benchmark for 100/500 models.
///
/// `--record-phase --output=<path> --revision=<sha>` records one implementation
/// phase. Run that command from an exact baseline checkout and then use
/// `--record --baseline=<path>` from the candidate checkout to create the
/// checked comparison artifact.
Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final sampleIndex = arguments.indexOf('--sample');
  if (sampleIndex >= 0) {
    final size = int.parse(arguments[sampleIndex + 1]);
    final command = arguments[sampleIndex + 2];
    stdout.writeln(jsonEncode(await _coldSample(root, size, command)));
    return;
  }
  final warmIndex = arguments.indexOf('--warm-sample');
  if (warmIndex >= 0) {
    final size = int.parse(arguments[warmIndex + 1]);
    final command = arguments[warmIndex + 2];
    stdout.writeln(jsonEncode(await _warmSample(root, size, command)));
    return;
  }

  final revision = _option(arguments, '--revision') ?? await _head(root);
  if (arguments.contains('--record-phase')) {
    final output = _requiredOption(arguments, '--output');
    await File(output).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(await _measurePhase(root, revision))}\n',
      flush: true,
    );
    return;
  }

  if (arguments.contains('--record')) {
    final baselineFile = File(_requiredOption(arguments, '--baseline'));
    final baseline = _object(jsonDecode(await baselineFile.readAsString()));
    final candidate = await _measurePhase(root, revision);
    final artifact = <String, Object?>{
      'schemaVersion': 2,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'targetVersion': '1.0.0-rc.5',
      'policy': <String, Object?>{
        'coldRuns': _coldRuns,
        'coldStatistic': 'median',
        'warmRuns': _warmRuns,
        'warmStatistic': 'p95',
        'rssStatistic': 'peak',
        'maxRegressionPercent': _maxRegressionPercent,
        'cacheAuthority': false,
        'sameHostRequired': true,
      },
      'baseline': baseline,
      'candidate': candidate,
      'comparisons': _compare(baseline, candidate),
    };
    await File('${root.path}/tool/model_benchmark.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(artifact)}\n',
      flush: true,
    );
    return;
  }

  stdout.write(
    '${const JsonEncoder.withIndent('  ').convert(await _measurePhase(root, revision))}\n',
  );
}

Future<Map<String, Object?>> _measurePhase(
  Directory root,
  String revision,
) async {
  final rows = <Map<String, Object?>>[];
  for (final size in _sizes) {
    for (final command in _commands) {
      final coldSamples = <Map<String, Object?>>[];
      for (var run = 0; run < _coldRuns; run += 1) {
        coldSamples.add(
          await _subprocessSample(root, '--sample', size, command),
        );
      }
      final coldTimes = <int>[
        for (final sample in coldSamples) sample['elapsedMicros']! as int,
      ]..sort();
      final warm = await _subprocessSample(
        root,
        '--warm-sample',
        size,
        command,
      );
      rows.add(<String, Object?>{
        'models': size,
        'command': command,
        'cold': <String, Object?>{
          'runs': _coldRuns,
          'medianMicros': coldTimes[_coldRuns ~/ 2],
          'peakRssBytes': _maximum(coldSamples, 'peakRssBytes'),
          'samples': coldSamples,
        },
        'warm': warm,
      });
    }
  }
  return <String, Object?>{
    'revision': revision,
    'implementation':
        Directory('${root.path}/packages/dartitect_modeling').existsSync()
        ? 'modular-modeling'
        : 'legacy-core-modeling',
    'host': <String, Object?>{
      'os': Platform.operatingSystem,
      'dart': Platform.version.split(' ').first,
      'processors': Platform.numberOfProcessors,
    },
    'results': rows,
  };
}

Future<Map<String, Object?>> _subprocessSample(
  Directory root,
  String mode,
  int size,
  String command,
) async {
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'tool/benchmark_models.dart',
    mode,
    '$size',
    command,
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    throw StateError('Model benchmark failed: ${result.stderr}');
  }
  final output = result.stdout as String;
  final marker = mode == '--sample' ? '{"elapsedMicros"' : '{"runs"';
  final jsonStart = output.lastIndexOf(marker);
  if (jsonStart < 0) {
    throw StateError('Model benchmark returned no JSON sample: $output');
  }
  return _object(jsonDecode(output.substring(jsonStart).trim()));
}

Future<Map<String, Object?>> _coldSample(
  Directory repository,
  int size,
  String command,
) async {
  _validateSample(size, command);
  final project = await _BenchmarkProject.create(repository, size);
  try {
    if (command == 'check') await project.generator.apply();
    final stopwatch = Stopwatch()..start();
    if (command == 'sync') {
      await project.generator.apply();
    } else {
      final report = await project.generator.inspect();
      if (!report.isFresh) throw StateError('Benchmark check is not fresh.');
    }
    stopwatch.stop();
    return <String, Object?>{
      'elapsedMicros': stopwatch.elapsedMicroseconds,
      'peakRssBytes': await _peakRssBytes(),
    };
  } finally {
    await project.dispose();
  }
}

Future<Map<String, Object?>> _warmSample(
  Directory repository,
  int size,
  String command,
) async {
  _validateSample(size, command);
  final project = await _BenchmarkProject.create(repository, size);
  try {
    await project.generator.apply();
    final samples = <Map<String, Object?>>[];
    for (var run = 0; run < _warmRuns; run += 1) {
      if (command == 'sync') await project.toggleIncrementalField();
      final stopwatch = Stopwatch()..start();
      if (command == 'sync') {
        await project.generator.apply();
      } else {
        final report = await project.generator.inspect();
        if (!report.isFresh) throw StateError('Warm check is not fresh.');
      }
      stopwatch.stop();
      samples.add(<String, Object?>{
        'elapsedMicros': stopwatch.elapsedMicroseconds,
        'peakRssBytes': await _peakRssBytes(),
      });
    }
    final times = <int>[
      for (final sample in samples) sample['elapsedMicros']! as int,
    ]..sort();
    return <String, Object?>{
      'runs': _warmRuns,
      'p95Micros': times[18],
      'peakRssBytes': _maximum(samples, 'peakRssBytes'),
      'samples': samples,
    };
  } finally {
    await project.dispose();
  }
}

List<Map<String, Object?>> _compare(
  Map<String, Object?> baseline,
  Map<String, Object?> candidate,
) {
  final baselineHost = _object(baseline['host']);
  final candidateHost = _object(candidate['host']);
  if (baselineHost['os'] != candidateHost['os'] ||
      baselineHost['dart'] != candidateHost['dart'] ||
      baselineHost['processors'] != candidateHost['processors']) {
    throw StateError('Baseline and candidate must run on the same host.');
  }
  final baselineRows = _objects(baseline['results']);
  final output = <Map<String, Object?>>[];
  for (final candidateRow in _objects(candidate['results'])) {
    final baselineRow = baselineRows.singleWhere(
      (row) =>
          row['models'] == candidateRow['models'] &&
          row['command'] == candidateRow['command'],
    );
    final baselineCold = _object(baselineRow['cold']);
    final candidateCold = _object(candidateRow['cold']);
    final baselineWarm = _object(baselineRow['warm']);
    final candidateWarm = _object(candidateRow['warm']);
    final metrics = <String, double>{
      'coldMedianMicros': _delta(
        baselineCold['medianMicros']! as int,
        candidateCold['medianMicros']! as int,
      ),
      'coldPeakRssBytes': _delta(
        baselineCold['peakRssBytes']! as int,
        candidateCold['peakRssBytes']! as int,
      ),
      'warmP95Micros': _delta(
        baselineWarm['p95Micros']! as int,
        candidateWarm['p95Micros']! as int,
      ),
      'warmPeakRssBytes': _delta(
        baselineWarm['peakRssBytes']! as int,
        candidateWarm['peakRssBytes']! as int,
      ),
    };
    output.add(<String, Object?>{
      'models': candidateRow['models'],
      'command': candidateRow['command'],
      'regressionPercent': metrics,
      'status': metrics.values.every((value) => value <= _maxRegressionPercent)
          ? 'pass'
          : 'review-required',
    });
  }
  return output;
}

double _delta(int baseline, int candidate) => double.parse(
  (((candidate - baseline) / baseline) * 100).toStringAsFixed(3),
);

int _maximum(List<Map<String, Object?>> rows, String key) => rows
    .map((row) => row[key]! as int)
    .reduce((left, right) => left > right ? left : right);

void _validateSample(int size, String command) {
  if (!_sizes.contains(size) || !_commands.contains(command)) {
    throw const FormatException('Unsupported model benchmark sample.');
  }
}

String? _option(List<String> arguments, String name) {
  final prefix = '$name=';
  return arguments
      .where((argument) => argument.startsWith(prefix))
      .firstOrNull
      ?.substring(prefix.length);
}

String _requiredOption(List<String> arguments, String name) =>
    _option(arguments, name) ??
    (throw FormatException('Missing required option $name=<value>.'));

Future<String> _head(Directory root) async {
  final result = await Process.run('git', const <String>[
    'rev-parse',
    'HEAD',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) throw StateError('Cannot resolve benchmark HEAD.');
  return (result.stdout as String).trim();
}

Future<int> _peakRssBytes() async {
  if (Platform.isLinux) {
    final status = await File('/proc/self/status').readAsLines();
    final line = status.where((line) => line.startsWith('VmHWM:')).firstOrNull;
    final kib = line == null
        ? null
        : int.tryParse(RegExp(r'\d+').firstMatch(line)?.group(0) ?? '');
    if (kib != null) return kib * 1024;
  }
  return ProcessInfo.currentRss;
}

Map<String, Object?> _object(Object? value) =>
    (value as Map<Object?, Object?>).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value as List<Object?>).map(_object).toList();

final class _BenchmarkProject {
  _BenchmarkProject({
    required this.root,
    required this.generator,
    required this.incrementalSource,
    required this.modular,
  });

  final Directory root;
  final DartitectModelGenerator generator;
  final File incrementalSource;
  final bool modular;

  static Future<_BenchmarkProject> create(
    Directory repository,
    int size,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-model-bench-',
    );
    final modular = Directory('${repository.path}/packages/dartitect_modeling')
        .existsSync();
    await Directory('${root.path}/lib/models').create(recursive: true);
    await Directory('${root.path}/.dart_tool').create();
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: dartitect_model_benchmark
environment:
  sdk: ^3.13.0
dependencies:
  ${modular ? 'dartitect_modeling' : 'dartitect'}: any
''');
    final packages = <Object?>[
      <String, Object?>{
        'name': 'dartitect_model_benchmark',
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      },
      for (final name in <String>[
        'dartitect',
        if (modular) 'dartitect_modeling',
      ])
        <String, Object?>{
          'name': name,
          'rootUri': Directory('${repository.path}/packages/$name').absolute.uri
              .toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
    ];
    await File('${root.path}/.dart_tool/package_config.json').writeAsString(
      jsonEncode(<String, Object?>{'configVersion': 2, 'packages': packages}),
    );
    late File first;
    for (var index = 0; index < size; index += 1) {
      final padded = index.toString().padLeft(4, '0');
      final file = File('${root.path}/lib/models/model_$padded.dart');
      if (index == 0) first = file;
      await file.writeAsString(
        modular ? _modularModel(padded) : _legacyModel(padded),
      );
    }
    return _BenchmarkProject(
      root: root,
      generator: DartitectModelGenerator(root),
      incrementalSource: first,
      modular: modular,
    );
  }

  Future<void> toggleIncrementalField() async {
    final source = await incrementalSource.readAsString();
    final nullable = modular
        ? 'required final String? label,'
        : 'final String? label;';
    final nonNullable = modular
        ? 'required final String label,'
        : 'final String label;';
    if (source.contains(nullable)) {
      await incrementalSource.writeAsString(
        source.replaceFirst(nullable, nonNullable),
      );
    } else if (source.contains(nonNullable)) {
      await incrementalSource.writeAsString(
        source.replaceFirst(nonNullable, nullable),
      );
    } else {
      throw StateError('Incremental benchmark field marker is absent.');
    }
  }

  Future<void> dispose() => root.delete(recursive: true);
}

String _modularModel(String padded) =>
    '''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'model_$padded.dartitect.g.dart';

@DartitectValue()
final class const Model$padded({
  required final int id,
  required final String? label,
}) extends ValueEquality with _\$Model${padded}Dartitect;
''';

String _legacyModel(String padded) =>
    '''
import 'package:dartitect/dartitect.dart';
part 'model_$padded.dartitect.g.dart';

@DartitectValue()
final class Model$padded extends ValueEquality with _\$Model${padded}Dartitect {
  const Model$padded({required this.id, required this.label});
  final int id;
  final String? label;
}
''';

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
