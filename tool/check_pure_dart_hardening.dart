import 'dart:convert';
import 'dart:io';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final contract = _object(
    jsonDecode(
      File('${root.path}/tool/pure_dart_hardening_contract.json')
          .readAsStringSync(),
    ),
  );
  final errors = <String>[];
  if (contract['schemaVersion'] != 1 || contract['goal'] != 'V1S-11') {
    errors.add('Unsupported pure-Dart hardening contract.');
  }
  final suites = _objects(contract['deterministicSuites'], errors);
  final seeds = <int>{};
  for (final suite in suites) {
    final name = suite['name'];
    final path = suite['file'];
    final seed = suite['seed'];
    final minimumCases = suite['minimumCases'];
    final markers = _strings(suite['requiredMarkers'], errors);
    if (name is! String ||
        path is! String ||
        seed is! int ||
        seed <= 0 ||
        minimumCases is! int ||
        minimumCases < 100 ||
        markers.isEmpty ||
        !seeds.add(seed)) {
      errors.add('Invalid deterministic suite: $name.');
      continue;
    }
    final source = _source(root, path, errors);
    if (!source.contains('const _seed = $seed;') ||
        !source.contains('const _cases = $minimumCases;')) {
      errors.add('$name seed/case constants disagree with the contract.');
    }
    for (final marker in markers) {
      if (!source.toLowerCase().contains(marker.toLowerCase())) {
        errors.add('$name is missing coverage marker: $marker.');
      }
    }
  }

  final generator = _map(contract['generator'], errors);
  _requireMarkers(
    root,
    _strings(generator['evidenceFiles'], errors),
    _strings(generator['requiredMarkers'], errors),
    errors,
    label: 'generator',
  );
  final ecosystem = _map(contract['ecosystem'], errors);
  final ecosystemFile = ecosystem['evidenceFile'];
  if (ecosystemFile is! String) {
    errors.add('Ecosystem evidence file is invalid.');
  } else {
    _requireMarkers(
      root,
      <String>[ecosystemFile],
      _strings(ecosystem['requiredMarkers'], errors),
      errors,
      label: 'ecosystem',
    );
  }

  _validateCompatibility(contract['compatibility'], errors);
  _validatePerformance(root, contract['performance'], errors);
  final webPackages = _strings(contract['requiredWebPackages'], errors);
  if (!webPackages.toSet().containsAll(const <String>{
    'dartitect',
    'dartitect_geometry',
    'dartitect_locale_br',
  })) {
    errors.add('Pure-Dart web package coverage is incomplete.');
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Pure-Dart hardening contract passed ${suites.length} deterministic '
    'suites, generator/ecosystem recovery, schema compatibility, and '
    'performance evidence.',
  );
}

void _validateCompatibility(Object? value, List<String> errors) {
  final compatibility = _map(value, errors);
  bool exact(String key, List<int> expected) {
    final raw = compatibility[key];
    return raw is List<Object?> &&
        raw.length == expected.length &&
        raw.every((item) => item is int) &&
        raw.cast<int>().toSet().containsAll(expected);
  }

  if (!exact('manifestAcceptedSchemas', const <int>[1]) ||
      !exact('manifestRejectedSchemas', const <int>[0, 2]) ||
      !exact('journalAcceptedSchemas', const <int>[2]) ||
      !exact('journalRejectedSchemas', const <int>[1, 3])) {
    errors.add('Generator manifest/journal compatibility matrix changed.');
  }
}

void _validatePerformance(Directory root, Object? value, List<String> errors) {
  final performance = _map(value, errors);
  for (final key in const <String>['artifact', 'budget', 'checker']) {
    final path = performance[key];
    if (path is! String || !File('${root.path}/$path').existsSync()) {
      errors.add('Performance $key is missing.');
    }
  }
  final counts = performance['modelCounts'];
  final commands = performance['commands'];
  if (counts is! List<Object?> ||
      counts.length != 2 ||
      !counts.contains(100) ||
      !counts.contains(500) ||
      commands is! List<Object?> ||
      commands.length != 2 ||
      !commands.contains('sync') ||
      !commands.contains('check') ||
      performance['minimumRuns'] != 5) {
    errors.add('Model generation performance matrix is incomplete.');
  }
}

void _requireMarkers(
  Directory root,
  List<String> paths,
  List<String> markers,
  List<String> errors, {
  required String label,
}) {
  final combined = StringBuffer();
  for (final path in paths) {
    combined.write(_source(root, path, errors));
  }
  final source = combined.toString().toLowerCase();
  for (final marker in markers) {
    if (!source.contains(marker.toLowerCase())) {
      errors.add('$label evidence is missing coverage marker: $marker.');
    }
  }
}

String _source(Directory root, String path, List<String> errors) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    errors.add('Evidence file is missing: $path.');
    return '';
  }
  return file.readAsStringSync();
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

Map<String, Object?> _map(Object? value, List<String> errors) {
  if (value is! Map<String, Object?>) {
    errors.add('Expected a JSON object field.');
    return <String, Object?>{};
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value, List<String> errors) {
  if (value is! List<Object?> ||
      value.any((item) => item is! Map<String, Object?>)) {
    errors.add('Expected a JSON object list.');
    return <Map<String, Object?>>[];
  }
  return value.cast<Map<String, Object?>>();
}

List<String> _strings(Object? value, List<String> errors) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    errors.add('Expected a JSON string list.');
    return <String>[];
  }
  return value.cast<String>();
}
