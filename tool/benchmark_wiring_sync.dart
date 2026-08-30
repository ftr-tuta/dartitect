import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dartitect_cli/dartitect_cli.dart';

const _featureCount = 100;
const _warmSamples = 7;
const _maxMedianMicroseconds = 2000000;

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp(
    'dartitect-wiring-benchmark-',
  );
  try {
    await _preparePackage(root);
    await _writeFactories(root);
    final declarations = <String, DartitectFeatureDeclaration>{
      for (var index = 0; index < _featureCount; index += 1)
        'feature_${index.toString().padLeft(3, '0')}':
            DartitectFeatureDeclaration(
              profile: FeatureProfile.online,
              scope: index.isEven
                  ? FeatureScope.application
                  : FeatureScope.session,
              factorySource: DartitectFactorySourceConfig(
                source: 'lib/benchmark_factories.dart',
                declaration:
                    'Feature${index.toString().padLeft(3, '0')}Factory',
              ),
              transport: 'primary',
              pagination: FeaturePagination.none,
              diagnostics: FeatureDiagnosticsLevel.basic,
            ),
    };
    final config = DartitectConfig(
      transports: <String, DartitectTransportConfig>{
        'primary': DartitectTransportConfig(
          provider: 'dio',
          factorySource: DartitectFactorySourceConfig(
            source: 'lib/benchmark_factories.dart',
            declaration: 'PrimaryTransportFactory',
          ),
          targets: const <DartitectPlatform>[DartitectPlatform.android],
        ),
      },
      session: DartitectSessionConfig(
        factorySource: DartitectFactorySourceConfig(
          source: 'lib/benchmark_factories.dart',
          declaration: 'BenchmarkSessionFactory',
        ),
      ),
      features: DartitectFeaturesConfig(declarations: declarations),
    );
    await File('${root.path}/dartitect.json')
        .writeAsString(config.encode(), flush: true);
    final service = DartitectWiringService(root);
    final initial = await service.apply(config: config);
    if (initial.writes < _featureCount) {
      throw StateError(
        'Expected at least $_featureCount initial writes, found '
        '${initial.writes}.',
      );
    }

    final samples = <int>[];
    for (var sample = 0; sample < _warmSamples; sample += 1) {
      final stopwatch = Stopwatch()..start();
      final report = await service.inspect(config: config);
      stopwatch.stop();
      if (!report.isFresh || report.writes != 0) {
        throw StateError('Warm wiring preview was not a zero-write no-op.');
      }
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    final median = samples[samples.length ~/ 2];

    final before = await _treeDigests(root);
    final noOp = await service.apply(config: config);
    final after = await _treeDigests(root);
    final byteStable = const MapEquality<String, String>().equals(
      before,
      after,
    );
    final passed =
        median <= _maxMedianMicroseconds && noOp.writes == 0 && byteStable;
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'featureCount': _featureCount,
        'initialWrites': initial.writes,
        'warmSamples': _warmSamples,
        'warmMicroseconds': samples,
        'warmMedianMicroseconds': median,
        'maxWarmMedianMicroseconds': _maxMedianMicroseconds,
        'noOpWrites': noOp.writes,
        'byteStable': byteStable,
        'gate': passed ? 'PASS' : 'FAIL',
      }),
    );
    if (!passed) exitCode = 1;
  } finally {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _preparePackage(Directory root) async {
  await Directory('${root.path}/lib').create(recursive: true);
  await Directory('${root.path}/.dart_tool').create(recursive: true);
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: wiring_benchmark
environment:
  sdk: ^3.13.0
dependencies:
  dartitect: any
''');
  final dartitect = await Isolate.resolvePackageUri(
    Uri.parse('package:dartitect/dartitect.dart'),
  );
  if (dartitect == null) throw StateError('dartitect package is unresolved');
  await File('${root.path}/.dart_tool/package_config.json').writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'wiring_benchmark',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
        <String, Object?>{
          'name': 'dartitect',
          'rootUri': dartitect.resolve('../').toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }),
  );
}

Future<void> _writeFactories(Directory root) async {
  final source = StringBuffer()
    ..writeln("import 'package:dartitect/dartitect.dart';")
    ..writeln()
    ..writeln('final class BenchmarkTransport {}')
    ..writeln('final class BenchmarkSession {}')
    ..writeln('final class BenchmarkRepository {}')
    ..writeln('final class BenchmarkRemotePort {}')
    ..writeln('final class BenchmarkMapper {}')
    ..writeln('final class BenchmarkViewModel {}')
    ..writeln()
    ..writeln("@DartitectTransportContextFactory('primary')")
    ..writeln('final class PrimaryTransportFactory {')
    ..writeln(
      '  Future<BenchmarkTransport> open() async => BenchmarkTransport();',
    )
    ..writeln('  Future<void> dispose(BenchmarkTransport transport) async {}')
    ..writeln('}')
    ..writeln()
    ..writeln('@DartitectSessionFactory()')
    ..writeln('final class BenchmarkSessionFactory {')
    ..writeln('  BenchmarkSession create() => BenchmarkSession();')
    ..writeln('}');
  for (var index = 0; index < _featureCount; index += 1) {
    final suffix = index.toString().padLeft(3, '0');
    source
      ..writeln()
      ..writeln("@DartitectFeatureFactory('feature_$suffix')")
      ..writeln('final class Feature${suffix}Factory {')
      ..writeln(
        '  BenchmarkRepository createRepository() => BenchmarkRepository();',
      )
      ..writeln(
        '  BenchmarkRemotePort createRemotePort() => BenchmarkRemotePort();',
      )
      ..writeln('  BenchmarkMapper createMapper() => BenchmarkMapper();')
      ..writeln(
        '  BenchmarkViewModel createViewModel(BenchmarkRepository repository) '
        '=> BenchmarkViewModel();',
      )
      ..writeln('}');
  }
  await File('${root.path}/lib/benchmark_factories.dart')
      .writeAsString(source.toString());
}

Future<Map<String, String>> _treeDigests(Directory root) async {
  final files = <File>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) files.add(entity);
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return <String, String>{
    for (final file in files)
      file.path.substring(root.path.length + 1): sha256
          .convert(await file.readAsBytes())
          .toString(),
  };
}

final class MapEquality<K, V> {
  const MapEquality();

  bool equals(Map<K, V> left, Map<K, V> right) =>
      left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);
}
