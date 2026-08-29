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
        'transport': false,
        'storage': false,
        'sync': false,
        'scheduler': false,
      });
      expect(report.requiredSymbols, containsAll(<String>['Result', 'Ok']));
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
        containsAll(<String>['DT4000', 'DT4002', 'DT4003', 'DT4006', 'DT4008']),
      );
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
    expect(report['schemaVersion'], 1);
    expect(report['command'], 'inspect consumer-tax');
    expect(report['compliant'], isTrue);
    expect(File('${root.path}/.dartitect').existsSync(), isFalse);
  });
}

Future<Directory> _project({
  required List<String> dependencies,
  required String source,
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
    DartitectConfig(features: DartitectFeaturesConfig()).encode(),
  );
  final target = File('${root.path}/lib/composition.dart');
  await target.parent.create(recursive: true);
  await target.writeAsString(source);
  return root;
}
