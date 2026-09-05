@TestOn('vm || browser')
library;

import 'dart:convert';

import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:test/test.dart';

import 'message_profile.dart';
import 'vectors.g.dart';

void main() {
  test('executes the shared wire corpus through real Dart codecs', () {
    final vectors = jsonDecode(titectVectorsJson) as List<Object?>;
    final outcomes = <Map<String, Object?>>[];
    for (final raw in vectors) {
      final vector = raw! as Map<String, Object?>;
      final padding = vector['appendSpaces'] as int? ?? 0;
      final bytes = utf8.encode('${vector['wire']}${' ' * padding}');
      try {
        final codec = TitectSyncCodec();
        final roundTrip = vector['profile'] == 'titect-sync/1'
            ? codec.encode(codec.decode(bytes))
            : messageRoundTrip(bytes);
        outcomes.add({
          'name': vector['name'],
          'accepted': true,
          'roundTrip': utf8.decode(roundTrip),
        });
      } on TitectWireException catch (failure) {
        outcomes.add({
          'name': vector['name'],
          'accepted': false,
          'problem': failure.problem.name,
        });
      }
    }
    expect(outcomes.length, vectors.length);
    // The driver consumes this event from package:test's machine reporter.
    // ignore: avoid_print
    print('TITECT_RESULTS:${jsonEncode(outcomes)}');
  });
}
