import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';
import 'package:test/test.dart';

void main() {
  test('installed overlap is a warning without concrete leakage', () async {
    final report = await DartitectVerificationService(Directory.current)
        .verify();

    expect(
      report.findings,
      contains(
        isA<DartitectFinding>()
            .having((finding) => finding.code, 'code', 'DT1019')
            .having(
              (finding) => finding.severity,
              'severity',
              FindingSeverity.warning,
            ),
      ),
    );
    expect(report.violations, isEmpty);
  });

  test('concrete provider leakage remains an error', () async {
    final root = await Directory.systemTemp.createTemp(
      'dartitect-interop-negative-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/pubspec.yaml').writeAsString('''name: negative
dependencies:
  provider: any
''');
    final source = File('${root.path}/lib/presentation/leak.dart');
    await source.parent.create(recursive: true);
    await source.writeAsString("import 'package:provider/provider.dart';\n");

    final report = await DartitectVerificationService(root).verify();

    expect(
      report.violations,
      contains(
        isA<DartitectFinding>()
            .having((finding) => finding.code, 'code', 'DT1006')
            .having(
              (finding) => finding.severity,
              'severity',
              FindingSeverity.error,
            ),
      ),
    );
    expect(report.project['providerStatus'], containsPair('status', 'error'));
  });
}
