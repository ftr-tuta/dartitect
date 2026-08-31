import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  const fixtures = <String, String>{
    'examples/model_generator_fixture': 'modeling',
    'examples/openapi_contract_fixture': 'contracts',
    'examples/thin_consumer_canary': 'wiring',
  };
  var outputs = 0;
  for (final fixture in fixtures.entries) {
    final manifest = File(
      '${root.path}/${fixture.key}/.dartitect/generation/'
      '${fixture.value}/manifest.json',
    );
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, Object?> ||
        decoded['schemaVersion'] != 3 ||
        decoded['protocolVersion'] != 1 ||
        decoded['namespace'] != fixture.value) {
      throw StateError(
        '${fixture.key} has an incompatible generation manifest.',
      );
    }
    final entries = decoded['outputs'];
    if (entries is! List<Object?> || entries.isEmpty) {
      throw StateError('${fixture.key} has no owned generated outputs.');
    }
    for (final raw in entries) {
      if (raw is! Map<String, Object?>) {
        throw StateError('${fixture.key} has an invalid output entry.');
      }
      final path = raw['path'];
      final source = raw['source'];
      final rendererId = raw['rendererId'];
      final digest = raw['outputDigest'];
      if (path is! String ||
          source is! String ||
          rendererId is! String ||
          rendererId.isEmpty ||
          digest is! String ||
          raw['rendererVersion'] is! int ||
          raw['semanticSchemaVersion'] is! int ||
          !_digest.hasMatch(digest) ||
          !_digest.hasMatch('${raw['inputDigest']}') ||
          !_confined(path) ||
          !_confined(source)) {
        throw StateError(
          '${fixture.key} has an invalid owned output contract.',
        );
      }
      final generated = File('${root.path}/${fixture.key}/$path');
      final input = File('${root.path}/${fixture.key}/$source');
      if (!await generated.exists() || !await input.exists()) {
        throw StateError('${fixture.key} is missing $source or $path.');
      }
      final actual = await sha256.bind(generated.openRead()).first;
      if ('$actual' != digest) {
        throw StateError('${fixture.key}/$path differs from its owned digest.');
      }
      outputs += 1;
    }
  }
  stdout.writeln(
    'Validated $outputs generated output(s) across ${fixtures.length} '
    'downstream protocols.',
  );
}

final _digest = RegExp(r'^[a-f0-9]{64}$');

bool _confined(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.startsWith('\\') &&
    !path.split(RegExp(r'[/\\]+')).contains('..');
