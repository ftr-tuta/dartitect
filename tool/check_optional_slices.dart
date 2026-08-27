import 'dart:convert';
import 'dart:io';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final contract = _object(
    jsonDecode(
      File('${root.path}/tool/optional_slice_gate.json').readAsStringSync(),
    ),
  );
  final errors = <String>[];
  if (contract['schemaVersion'] != 1 ||
      contract['goal'] != '08' ||
      contract['blocksStable1'] != false) {
    errors.add('Optional-slice gate metadata is invalid.');
  }
  const evidence = <String>[
    'dedicatedAdr',
    'realConsumer',
    'benchmark',
    'packageBoundaryReview',
  ];
  if (!_exactStrings(contract['requiredEvidence'], evidence)) {
    errors.add('Optional-slice required evidence changed unexpectedly.');
  }
  const expectedIds = <String>{
    'explicit-lazy-computed',
    'typed-command-progress',
    'versioned-ui-restoration',
    'bounded-local-history',
    'readonly-devtools-diagnostics',
  };
  final slices = _objects(contract['slices'], errors);
  final ids = <String>{};
  for (final slice in slices) {
    final id = slice['id'];
    if (id is! String || !ids.add(id)) {
      errors.add('Optional slice has an invalid or duplicate ID: $id.');
      continue;
    }
    if (slice['status'] != 'DEFERRED') {
      errors.add('$id must remain DEFERRED without its complete evidence.');
    }
    for (final key in evidence) {
      if (slice[key] != 'MISSING') {
        errors.add('$id cannot claim $key without an independent gate.');
      }
    }
    final reason = slice['reason'];
    if (reason is! String || reason.trim().length < 40) {
      errors.add('$id needs an explicit non-empty deferral reason.');
    }
  }
  if (ids.length != expectedIds.length || !ids.containsAll(expectedIds)) {
    errors.add('The five optional Goal 08 slices are not classified exactly.');
  }

  final release = _object(
    jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ),
  );
  final packages = _strings(release['publicationOrder'], errors);
  if (packages.contains('dartitect_state')) {
    errors.add('Deferred slices must not create dartitect_state.');
  }
  final source = StringBuffer();
  for (final directory in Directory('${root.path}/packages').listSync()) {
    if (directory is! Directory) continue;
    final lib = Directory('${directory.path}/lib');
    if (!lib.existsSync()) continue;
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart')) source.write(file.readAsStringSync());
    }
  }
  for (final marker in _strings(contract['forbiddenPublicMarkers'], errors)) {
    if (source.toString().contains(marker)) {
      errors.add('Deferred public marker was implemented: $marker.');
    }
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Goal 08 gate keeps all five optional slices DEFERRED with no new package.',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value, List<String> errors) {
  if (value is! List<Object?> ||
      value.any((element) => element is! Map<String, Object?>)) {
    errors.add('Expected a list of JSON objects.');
    return const <Map<String, Object?>>[];
  }
  return value.cast<Map<String, Object?>>();
}

List<String> _strings(Object? value, List<String> errors) {
  if (value is! List<Object?> || value.any((element) => element is! String)) {
    errors.add('Expected a list of strings.');
    return const <String>[];
  }
  return value.cast<String>();
}

bool _exactStrings(Object? actual, List<String> expected) =>
    actual is List<Object?> &&
    actual.length == expected.length &&
    actual.every((value) => value is String) &&
    actual.cast<String>().toSet().containsAll(expected);
