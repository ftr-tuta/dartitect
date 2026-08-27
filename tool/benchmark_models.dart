import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

/// Reproducible cold model sync/check benchmark for 100 and 500 models.
Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final sampleIndex = arguments.indexOf('--sample');
  if (sampleIndex >= 0) {
    final size = int.parse(arguments[sampleIndex + 1]);
    final command = arguments[sampleIndex + 2];
    final result = await _sample(root, size, command);
    stdout.writeln(jsonEncode(result));
    return;
  }

  final rows = <Map<String, Object?>>[];
  for (final size in const <int>[100, 500]) {
    for (final command in const <String>['sync', 'check']) {
      final samples = <Map<String, Object?>>[];
      for (var run = 0; run < 5; run += 1) {
        final result = await Process.run(Platform.resolvedExecutable, <String>[
          'run',
          'tool/benchmark_models.dart',
          '--sample',
          '$size',
          command,
        ], workingDirectory: root.path);
        if (result.exitCode != 0) {
          throw StateError('Model benchmark failed: ${result.stderr}');
        }
        samples.add(
          jsonDecode((result.stdout as String).trim()) as Map<String, Object?>,
        );
      }
      final times =
          samples.map((sample) => sample['elapsedMicros']! as int).toList()
            ..sort();
      final rss = samples
          .map((sample) => sample['peakRssBytes']! as int)
          .reduce((left, right) => left > right ? left : right);
      rows.add(<String, Object?>{
        'models': size,
        'command': command,
        'runs': 5,
        'medianMicros': times[2],
        'peakRssBytes': rss,
        'samples': samples,
      });
    }
  }
  final artifact = <String, Object?>{
    'schemaVersion': 1,
    'recordedAt': '2026-08-25',
    'generatorVersion': '1.0.0-rc.3',
    'host': <String, Object?>{
      'os': Platform.operatingSystem,
      'dart': Platform.version.split(' ').first,
      'processors': Platform.numberOfProcessors,
    },
    'results': rows,
  };
  final encoded = '${const JsonEncoder.withIndent('  ').convert(artifact)}\n';
  if (arguments.contains('--record')) {
    await File('${root.path}/tool/model_benchmark.json')
        .writeAsString(encoded, flush: true);
  } else {
    stdout.write(encoded);
  }
}

Future<Map<String, Object?>> _sample(
  Directory repository,
  int size,
  String command,
) async {
  if (!const <int>{100, 500}.contains(size) ||
      !const <String>{'sync', 'check'}.contains(command)) {
    throw const FormatException('Unsupported model benchmark sample.');
  }
  final root = await Directory.systemTemp.createTemp('dartitect-model-bench-');
  try {
    await Directory('${root.path}/lib/models').create(recursive: true);
    await Directory('${root.path}/.dart_tool').create();
    await File('${root.path}/pubspec.yaml').writeAsString('''
name: dartitect_model_benchmark
environment:
  sdk: ^3.13.0
dependencies:
  dartitect_modeling: any
''');
    final coreUri = Directory('${repository.path}/packages/dartitect')
        .absolute
        .uri;
    final modelingUri = Directory(
      '${repository.path}/packages/dartitect_modeling',
    ).absolute.uri;
    await File('${root.path}/.dart_tool/package_config.json').writeAsString(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'dartitect_model_benchmark',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
          <String, Object?>{
            'name': 'dartitect',
            'rootUri': coreUri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
          <String, Object?>{
            'name': 'dartitect_modeling',
            'rootUri': modelingUri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.13',
          },
        ],
      }),
    );
    for (var index = 0; index < size; index += 1) {
      final padded = index.toString().padLeft(4, '0');
      await File('${root.path}/lib/models/model_$padded.dart').writeAsString('''
import 'package:dartitect_modeling/dartitect_modeling.dart';
part 'model_$padded.dartitect.g.dart';

@DartitectValue()
final class Model$padded extends ValueEquality with _\$Model${padded}Dartitect {
  const Model$padded({required this.id, required this.label});
  final int id;
  final String? label;
}
''');
    }
    final generator = DartitectModelGenerator(root);
    if (command == 'check') await generator.apply();
    final stopwatch = Stopwatch()..start();
    if (command == 'sync') {
      await generator.apply();
    } else {
      final report = await generator.inspect();
      if (!report.isFresh) throw StateError('Benchmark check is not fresh.');
    }
    stopwatch.stop();
    return <String, Object?>{
      'elapsedMicros': stopwatch.elapsedMicroseconds,
      'peakRssBytes': await _peakRssBytes(),
    };
  } finally {
    await root.delete(recursive: true);
  }
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
