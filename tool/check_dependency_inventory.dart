import 'dart:io';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final policy = File('${root.path}/DEPENDENCIES.adoc').readAsStringSync();
  final errors = <String>[];
  final packageRoot = Directory('${root.path}/packages');
  for (final package in packageRoot.listSync(followLinks: false)) {
    if (package is! Directory) continue;
    final pubspec = File('${package.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final name = RegExp(
      r'^name:\s*([^\s]+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync())?.group(1);
    if (name == null || !policy.contains('| $name')) {
      errors.add('Dependency rationale missing for ${name ?? package.path}.');
    }
    if (!File('${package.path}/LICENSE').existsSync()) {
      errors.add('LICENSE missing for $name.');
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln('Dependency rationale and package licenses are complete.');
}
