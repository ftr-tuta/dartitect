import 'dart:convert';
import 'dart:io';

import 'package:dartitect_cli/dartitect_cli.dart';

Future<void> main(List<String> arguments) async {
  final root = Directory(arguments.isEmpty ? '.' : arguments.single);
  await for (final event in ProjectScanner(root).scanEvents()) {
    switch (event) {
      case ProjectScanFileAnalyzed(:final index, :final total):
        stdout.writeln(
          jsonEncode(<String, Object?>{'analyzed': index, 'total': total}),
        );
      case ProjectScanCompleted(:final scan):
        exitCode = scan.violations.isEmpty ? 0 : 1;
      case ProjectScanCancelled():
        exitCode = 130;
      case ProjectScanStarted() ||
          ProjectScanFileDiscovered() ||
          ProjectScanFinding():
        break;
    }
  }
}
