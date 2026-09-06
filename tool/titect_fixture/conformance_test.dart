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
        final rawLimits = vector['limits'] as Map<String, Object?>?;
        final limits = TitectJsonLimits(
          maxBytes: rawLimits?['max_body_bytes'] as int? ?? 1048576,
          maxDepth: rawLimits?['max_json_depth'] as int? ?? 32,
          maxItems: rawLimits?['max_json_items'] as int? ?? 10000,
          maxStringScalars: rawLimits?['max_string_length'] as int? ?? 16384,
        );
        final List<int> roundTrip;
        switch (vector['profile']) {
          case 'titect-sync/1':
            final acknowledgement = vector['acknowledgement'] as String?;
            final selection = TitectSyncIntegritySelection.select(
              requested: (vector['requested'] as List<Object?>? ?? [])
                  .cast<String>(),
              acknowledgement: acknowledgement,
              policies: const [TitectExactJsonSha256Integrity()],
            );
            final codec = TitectSyncCodec(
              jsonLimits: rawLimits == null ? null : limits,
              integrity: selection,
            );
            roundTrip = codec.encode(
              codec.decode(bytes, acknowledgement: acknowledgement),
            );
          case 'titect-message/1' || 'titect-message/2':
            roundTrip = messageRoundTrip(
              bytes,
              profile: vector['profile']! as String,
              limits: limits,
            );
          case 'exact-json':
            final codec = TitectJsonCodec(limits: limits);
            roundTrip = codec.encode(codec.decode(bytes), sortKeys: true);
          default:
            throw const TitectWireException(TitectWireProblem.unsupported);
        }
        outcomes.add({
          'name': vector['name'],
          'accepted': true,
          'roundTrip': utf8.decode(roundTrip),
        });
      } on TitectWireException catch (failure) {
        outcomes.add({
          'name': vector['name'],
          'accepted': false,
          'problem': failure.problem.code,
        });
      }
    }
    expect(outcomes.length, vectors.length);
    // The driver consumes this event from package:test's machine reporter.
    // ignore: avoid_print
    print('TITECT_RESULTS:${jsonEncode(outcomes)}');
    final expected = jsonDecode(titectExpectationsJson) as List<Object?>;
    for (var i = 0; i < expected.length; i++) {
      expect(outcomes[i], expected[i], reason: outcomes[i]['name']! as String);
    }
  });
}
