import 'dart:convert';
import 'dart:io';

/// Rechecks the intended package names against the official pub.dev API.
Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--live')) {
    throw const FormatException('Usage: check_pub_dev_identity.dart [--live]');
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final release = _object(
    jsonDecode(
      File('${root.path}/tool/package_release_contract.json')
          .readAsStringSync(),
    ),
  );
  final candidate = _object(
    jsonDecode(
      File('${root.path}/tool/rc_candidate_contract.json').readAsStringSync(),
    ),
  );
  final order = _strings(release['publicationOrder']);
  final observation = _object(candidate['nameRegistryObservation']);
  final recorded = _strings(observation['packages']);
  if (!_same(order, recorded) ||
      observation['registry'] != 'https://pub.dev' ||
      observation['expectedStatus'] != 404) {
    throw const FormatException('Invalid pub.dev identity observation.');
  }
  final publisher = _object(candidate['publisherIdentity']);
  if (publisher['status'] != 'NOT_AUTHORIZED' ||
      publisher['requiredBeforePubDevMaterialization'] != true ||
      '${publisher['reason']}'.trim().isEmpty) {
    throw const FormatException('Publisher identity is not fail-closed.');
  }
  if (arguments.isEmpty) {
    stdout.writeln(
      'Recorded pub.dev identity contract covers ${order.length} names; '
      'use --live to recheck availability.',
    );
    return;
  }

  final client = HttpClient()..userAgent = 'dartitect-release-audit/1.0';
  final errors = <String>[];
  try {
    for (final name in order) {
      final request = await client.getUrl(
        Uri.https('pub.dev', '/api/packages/$name'),
      );
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.notFound) {
        errors.add('$name returned HTTP ${response.statusCode}, expected 404.');
      }
    }
  } finally {
    client.close(force: true);
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Live pub.dev check passed: all ${order.length} names returned HTTP 404; '
    'publisher identity remains required before a pub.dev upload.',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<String> _strings(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string list.');
  }
  return value.cast<String>();
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((value) => value);
