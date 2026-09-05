import 'dart:convert';
import 'dart:io';

const dependencySnippetProfiles = <String, List<String>>{
  'core': <String>['dartitect'],
  'flutter': <String>[
    'dartitect',
    'dartitect_flutter',
    'dartitect_flutter_testing',
  ],
  'drift': <String>['dartitect', 'dartitect_drift'],
  'objectbox': <String>['dartitect', 'dartitect_objectbox'],
  'tooling': <String>[
    'dartitect_cli',
    'dartitect_devtools',
    'dartitect_lints',
    'dartitect_mcp',
  ],
};

/// Emits official direct-dependency snippets without overrides or closure.
void main(List<String> arguments) {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  String? profile;
  final packages = <String>[];
  for (final argument in arguments) {
    if (argument.startsWith('--profile=')) {
      if (profile != null) throw ArgumentError('Duplicate --profile.');
      profile = argument.substring('--profile='.length);
    } else if (argument.startsWith('-')) {
      throw ArgumentError('Unknown option: $argument');
    } else {
      packages.addAll(argument.split(',').where((value) => value.isNotEmpty));
    }
  }
  if (profile != null) {
    final selected = dependencySnippetProfiles[profile];
    if (selected == null) throw ArgumentError('Unknown profile: $profile.');
    packages.addAll(selected);
  }
  if (packages.isEmpty) {
    throw ArgumentError(
      'Usage: dart run tool/dependency_snippets.dart '
      '[--profile=core|flutter|drift|objectbox|tooling] '
      '<package>[,<package>...]',
    );
  }
  stdout.write(buildDependencySnippet(root, packages));
}

/// Builds one deterministic `dependencies` block for direct packages only.
String buildDependencySnippet(
  Directory root,
  Iterable<String> selectedPackages, {
  bool workspace = false,
}) {
  final contract = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (contract is! Map<String, Object?> ||
      contract['dependencyOrder'] is! List<Object?> ||
      contract['distributedInternalDependency'] is! Map<String, Object?>) {
    throw const FormatException('Invalid package release contract.');
  }
  final order = (contract['dependencyOrder']! as List<Object?>).cast<String>();
  final dependency =
      contract[workspace
              ? 'workspaceInternalDependency'
              : 'distributedInternalDependency']!
          as Map<String, Object?>;
  final requested = selectedPackages.toSet();
  final unknown = requested.difference(order.toSet()).toList()..sort();
  if (unknown.isNotEmpty) {
    throw ArgumentError('Unknown Dartitect packages: ${unknown.join(', ')}.');
  }
  final buffer = StringBuffer('dependencies:\n');
  for (final package in order.where(requested.contains)) {
    buffer
      ..writeln('  $package:')
      ..writeln('    git:')
      ..writeln('      url: ${dependency['url']}')
      ..writeln('      path: packages/$package')
      ..writeln("      tag_pattern: '${dependency['tagPattern']}'")
      ..writeln('    version: ${dependency['version']}');
  }
  return buffer.toString();
}
