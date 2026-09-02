import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test(
    'local shell has minimal capability closure and stable budgets',
    () async {
      final root = await _project(
        dependencies: const <String>['dartitect'],
        source: '''
import 'package:dartitect/dartitect.dart';

Result<int, StateError> load() => const Ok<int>(1);
''',
      );
      addTearDown(() => root.delete(recursive: true));

      final report = await ConsumerTaxInspector(root).inspect();

      expect(report.profile, 'local');
      expect(report.isCompliant, isTrue);
      expect(report.metrics['manualPlumbing'], 0);
      expect(report.metrics['generatedOnceStructuralFiles'], 0);
      expect(report.metrics, contains('analysisMillis'));
      expect(report.metrics, contains('buildMillis'));
      expect(report.capabilityOptIns, <String, bool>{
        'observability': false,
        'transport': false,
        'storage': false,
        'sync': false,
        'scheduler': false,
      });
      expect(report.requiredSymbols, containsAll(<String>['Result', 'Ok']));
    },
  );

  test('Sentry opt-in expands only its direct dependency budget', () async {
    final root = await _project(
      dependencies: const <String>[
        'dartitect',
        'dartitect_observability',
        'dartitect_sentry',
        'sentry',
      ],
      source: '''
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sentry/dartitect_sentry.dart';
import 'package:sentry/sentry.dart';

Object? use(Result<int, StateError> result, ObservabilityRuntime runtime,
        SentryLogSink sink, Hub hub) => result;
''',
      config: DartitectConfig(
        features: DartitectFeaturesConfig(),
        observability: DartitectObservabilityConfig(provider: 'sentry'),
      ),
    );
    addTearDown(() => root.delete(recursive: true));

    final report = await ConsumerTaxInspector(root).inspect();

    expect(report.isCompliant, isTrue);
    final axes = report.generatedTax['axes']! as Map<String, int>;
    expect(axes['observability'], greaterThan(0));
    expect(report.productCode['blocking'], isFalse);
    expect(report.capabilityOptIns['observability'], isTrue);
  });

  test(
    'transitive adapter dependencies do not imply capability opt-in',
    () async {
      final root = await _project(
        dependencies: const <String>['dartitect', 'dartitect_observability'],
        source: '''
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_observability/dartitect_observability.dart';

Object? use(Result<int, StateError> result, ObservabilityRuntime runtime) =>
    result;
''',
        config: DartitectConfig(
          features: DartitectFeaturesConfig(),
          observability: DartitectObservabilityConfig(provider: 'developer'),
        ),
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/pubspec.lock').writeAsString('''
packages:
  dartitect:
    dependency: "direct main"
  dartitect_observability:
    dependency: "direct main"
  dartitect_sync:
    dependency: transitive
''');

      final report = await ConsumerTaxInspector(root).inspect();

      expect(report.isCompliant, isTrue);
      expect(report.capabilityOptIns['observability'], isTrue);
      expect(report.capabilityOptIns['sync'], isFalse);
      expect(
        report.findings.map((finding) => finding.code),
        isNot(contains('DT4006')),
      );
    },
  );

  test(
    'structural plumbing and unselected dependencies fail ratchets',
    () async {
      final root = await _project(
        dependencies: const <String>[
          'dartitect',
          'dartitect_dio',
          'dartitect_sync',
        ],
        source: '''
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

Object? transport;
final owner = DioOwner.create();
final engine = SyncEngine(null);
''',
      );
      addTearDown(() => root.delete(recursive: true));
      final metrics = File('${root.path}/.dartitect/consumer-tax-metrics.json');
      await metrics.parent.create(recursive: true);
      await metrics.writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'analysisMillis': 60001,
          'buildMillis': 1,
        }),
      );

      final report = await ConsumerTaxInspector(root).inspect();
      final codes = report.findings.map((finding) => finding.code).toSet();

      expect(report.isCompliant, isFalse);
      expect(
        codes,
        containsAll(<String>['DT4000', 'DT4002', 'DT4003', 'DT4006']),
      );
      expect(codes, isNot(contains('DT4008')));
      expect(report.diagnostics, contains(contains('legacy schema 1')));
    },
  );

  test('CLI exposes the JSON consumer-tax report read-only', () async {
    final root = await _project(
      dependencies: const <String>['dartitect'],
      source: "import 'package:dartitect/dartitect.dart';\n",
    );
    addTearDown(() => root.delete(recursive: true));
    final output = StringBuffer();

    final exitCode = await DartitectCliRunner(
      currentDirectory: root,
      stdoutSink: output,
      stderrSink: StringBuffer(),
    ).run(<String>['inspect', '--consumer-tax', '--json']);
    final report = jsonDecode(output.toString()) as Map<String, Object?>;

    expect(exitCode, 0);
    expect(report['schemaVersion'], 2);
    expect(report['command'], 'inspect consumer-tax');
    expect(report['compliant'], isTrue);
    expect(File('${root.path}/.dartitect').existsSync(), isFalse);
  });

  test(
    'typed context factories may construct their selected provider owner',
    () async {
      final root = await _project(
        dependencies: const <String>['dartitect', 'dartitect_dio'],
        source: '''
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';

@DartitectTransportContextFactory('api')
final class ApiFactory {
  DioOwner open() => DioOwner.create();

  void dispose(DioOwner owner) => owner.dispose();
}
''',
        config: DartitectConfig(
          features: DartitectFeaturesConfig(),
          targets: DartitectTargetsConfig(const <DartitectPlatform>[
            DartitectPlatform.linux,
          ]),
          transports: <String, DartitectTransportConfig>{
            'api': DartitectTransportConfig(
              provider: 'dio',
              targets: const <DartitectPlatform>[DartitectPlatform.linux],
            ),
          },
        ),
      );
      addTearDown(() => root.delete(recursive: true));

      final report = await ConsumerTaxInspector(root).inspect();

      expect(report.architectureTax['observed'], 0);
      expect(
        report.findings.map((finding) => finding.code),
        isNot(contains('DT4002')),
      );
    },
  );

  test('test-tax blocks source-string architecture tests', () async {
    final root = await _project(
      dependencies: const <String>['dartitect'],
      source: "import 'package:dartitect/dartitect.dart';\n",
    );
    addTearDown(() => root.delete(recursive: true));
    final testFile = File('${root.path}/test/architecture_test.dart');
    await testFile.parent.create(recursive: true);
    await testFile.writeAsString('''
import 'dart:io';

void inspectArchitecture() {
  File('lib/main.dart').readAsStringSync();
}
''');

    final report = await ConsumerTaxInspector(root).inspect();

    expect(report.isCompliant, isFalse);
    expect(report.testTax['observed'], 1);
    expect(report.findings.map((finding) => finding.code), contains('DT4010'));
  });
}

Future<Directory> _project({
  required List<String> dependencies,
  required String source,
  DartitectConfig? config,
}) async {
  final root = await Directory.systemTemp.createTemp('dartitect-consumer-tax-');
  await File('${root.path}/pubspec.yaml').writeAsString('''
name: consumer_tax_fixture
environment:
  sdk: ^3.13.0
dependencies:
${dependencies.map((dependency) => '  $dependency: any').join('\n')}
''');
  await File('${root.path}/dartitect.json').writeAsString(
    (config ?? DartitectConfig(features: DartitectFeaturesConfig())).encode(),
  );
  final target = File('${root.path}/lib/composition.dart');
  await target.parent.create(recursive: true);
  await target.writeAsString(source);
  return root;
}
