import 'dart:convert';
import 'dart:io';

Future<void> materializeNativeEvidenceHarness({
  required Directory root,
  required Directory consumer,
  required Set<String> packages,
  bool copyHarnessSources = true,
  bool copyIntegrationTests = true,
  bool copyIosNativeTests = false,
}) async {
  final generatedTestDirectory = Directory('${consumer.path}/test');
  if (generatedTestDirectory.existsSync()) {
    await generatedTestDirectory.delete(recursive: true);
  }
  final generatedAnalysisOptions = File(
    '${consumer.path}/analysis_options.yaml',
  );
  if (generatedAnalysisOptions.existsSync()) {
    await generatedAnalysisOptions.delete();
  }
  final dependencyNames = <String>{'dartitect', ...packages}.toList()..sort();
  String path(String package) => jsonEncode(
    '${root.path}/packages/$package'.replaceAll(Platform.pathSeparator, '/'),
  );
  await File('${consumer.path}/pubspec.yaml').writeAsString('''
name: dartitect_native_capabilities_harness
description: Ephemeral V1S-13 native evidence harness.
version: 0.0.0
publish_to: none

environment:
  sdk: ^3.13.0
  flutter: '>=3.47.1'

dependencies:
${dependencyNames.map((name) => '  $name:\n    path: ${path(name)}').join('\n')}
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

dependency_overrides:
  dartitect:
    path: ${path('dartitect')}

flutter:
  uses-material-design: true
''');
  final source = Directory('${root.path}/tool/canaries/native_capabilities');
  if (copyHarnessSources) {
    await copyDirectory(
      Directory('${source.path}/lib'),
      Directory('${consumer.path}/lib'),
    );
  } else {
    await File('${consumer.path}/lib/main.dart').writeAsString('''
import 'package:flutter/widgets.dart';

void main() => runApp(const SizedBox.shrink());
''');
  }
  if (copyIntegrationTests) {
    await copyDirectory(
      Directory('${source.path}/integration_test'),
      Directory('${consumer.path}/integration_test'),
    );
  }
  if (copyIosNativeTests) {
    await copyDirectory(
      Directory('${source.path}/ios/RunnerTests'),
      Directory('${consumer.path}/ios/RunnerTests'),
    );
  }
}

Future<void> copyDirectory(Directory source, Directory destination) async {
  if (!source.existsSync()) return;
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}/$relative';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}
