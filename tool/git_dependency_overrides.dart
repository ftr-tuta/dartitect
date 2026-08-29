import 'dart:convert';
import 'dart:io';

/// Emits Git dependency overrides for the selected packages and every
/// transitive Dartitect dependency they require.
void main(List<String> arguments) {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  var repository = 'https://github.com/ftr-tuta/dartitect.git';
  var ref = 'v1.0.0-rc.6';
  final packages = <String>[];
  for (final argument in arguments) {
    if (argument.startsWith('--repository=')) {
      repository = argument.substring('--repository='.length);
    } else if (argument.startsWith('--ref=')) {
      ref = argument.substring('--ref='.length);
    } else if (argument.startsWith('-')) {
      throw ArgumentError('Unknown option: $argument');
    } else {
      packages.addAll(argument.split(',').where((value) => value.isNotEmpty));
    }
  }
  if (packages.isEmpty) {
    throw ArgumentError(
      'Usage: dart run tool/git_dependency_overrides.dart '
      '[--repository=<url>] [--ref=<tag>] <package>[,<package>...]',
    );
  }
  stdout.write(
    buildGitDependencyOverrides(
      root,
      packages,
      repository: repository,
      ref: ref,
    ),
  );
}

String buildGitDependencyOverrides(
  Directory root,
  Iterable<String> selectedPackages, {
  required String repository,
  required String ref,
}) {
  if (repository.trim().isEmpty || repository.contains(RegExp(r'[\r\n]'))) {
    throw ArgumentError.value(repository, 'repository', 'must be one URL');
  }
  if (ref.trim().isEmpty || ref.contains(RegExp(r'[\r\n]'))) {
    throw ArgumentError.value(ref, 'ref', 'must be one Git ref');
  }
  final contract = jsonDecode(
    File('${root.path}/tool/package_release_contract.json').readAsStringSync(),
  );
  if (contract is! Map<String, Object?> ||
      contract['publicationOrder'] is! List<Object?>) {
    throw const FormatException('Invalid package release contract.');
  }
  final order = (contract['publicationOrder']! as List<Object?>).cast<String>();
  final known = order.toSet();
  final graph = <String, Set<String>>{};
  for (final package in order) {
    final pubspec = File('${root.path}/packages/$package/pubspec.yaml');
    if (!pubspec.existsSync()) {
      throw StateError('Missing pubspec for $package.');
    }
    final source = pubspec.readAsStringSync();
    graph[package] = <String>{
      for (final dependency in order)
        if (RegExp(
          '^  ${RegExp.escape(dependency)}:',
          multiLine: true,
        ).hasMatch(source))
          dependency,
    };
  }

  final requested = selectedPackages.toSet();
  final unknown = requested.difference(known).toList()..sort();
  if (unknown.isNotEmpty) {
    throw ArgumentError('Unknown Dartitect packages: ${unknown.join(', ')}.');
  }
  final closure = <String>{};
  void include(String package) {
    if (!closure.add(package)) return;
    for (final dependency in graph[package]!) {
      include(dependency);
    }
  }

  for (final package in requested) {
    include(package);
  }

  final buffer = StringBuffer('dependency_overrides:\n');
  for (final package in order.where(closure.contains)) {
    buffer
      ..writeln('  $package:')
      ..writeln('    git:')
      ..writeln('      url: $repository')
      ..writeln('      ref: $ref')
      ..writeln('      path: packages/$package');
  }
  return buffer.toString();
}
