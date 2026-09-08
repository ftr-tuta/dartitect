import 'dart:convert';

import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:test/test.dart';

void main() {
  const policy = TitectExactJsonSha256Integrity();
  const capability = TitectExactJsonSha256Integrity.capabilityName;
  final selection = TitectSyncIntegritySelection.select(
    requested: [capability],
    acknowledgement: capability,
    policies: [policy],
  );
  final codec = TitectSyncCodec(integrity: selection);
  final page = policy.seal(
    codec.fromPayload('delta', {
      'dataset_id': 'd',
      'generation': 7,
      'upserts': [
        {'item_id': 'a', 'revision': 1, 'value': TitectNumber.parse('1E+000')},
      ],
      'tombstones': [
        {
          'item_id': 'b',
          'revision': 2,
          'deleted_at': '2026-01-01T00:00:00.000Z',
        },
      ],
      'next_cursor': 'opaque/+=',
      'integrity': {
        'algorithm': 'sha-256',
        'digest': '0' * 64,
        'item_count': 2,
      },
    }) as TitectPage,
    codec: codec,
  );
  final wire = utf8.decode(codec.encode(page));
  final integrityError = isA<TitectWireException>().having(
    (e) => e.problem.code,
    'code',
    'integrity',
  );

  test('complete envelope, ordered data and lexical number are covered', () {
    expect(
      codec.encode(
        codec.decode(utf8.encode(wire), acknowledgement: capability),
      ),
      utf8.encode(wire),
    );
    for (final pair in [
      ['"delta"', '"snapshot"'],
      ['"d"', '"e"'],
      ['"generation":7', '"generation":8'],
      ['"a"', '"c"'],
      ['"revision":1', '"revision":3'],
      ['1E+000', '1e0'],
      ['"b"', '"c"'],
      ['00:00:00.000Z', '00:00:01.000Z'],
      ['opaque/+=', 'changed'],
      ['"item_count":2', '"item_count":2.0'],
    ]) {
      expect(
        () => codec.decode(
          utf8.encode(wire.replaceFirst(pair[0], pair[1])),
          acknowledgement: capability,
        ),
        throwsA(integrityError),
        reason: pair.first,
      );
    }
  });
  test('every selected response needs the persisted acknowledgement', () async {
    for (final header in [null, 'changed']) {
      expect(
        () => codec.decode(utf8.encode(wire), acknowledgement: header),
        throwsA(integrityError),
      );
      await expectLater(
        codec.read(Stream.value(utf8.encode(wire)), acknowledgement: header),
        throwsA(integrityError),
      );
    }
    expect(
      () => TitectSyncCodec().decode(
        utf8.encode(wire),
        acknowledgement: capability,
      ),
      throwsA(integrityError),
    );
  });
  test(
    'exact JSON emits all normative escapes and literal Unicode separators',
    () {
      final json = TitectJsonCodec();
      const value = '"\\\b\f\n\r\t\u0000\u001f/\u2028\u2029😀';
      final encoded = json.encode(value, sortKeys: true);
      expect(
        utf8.decode(encoded),
        '"\\"\\\\\\b\\f\\n\\r\\t\\u0000\\u001f/\u2028\u2029😀"',
      );
      expect(json.decode(encoded), value);
    },
  );
}
