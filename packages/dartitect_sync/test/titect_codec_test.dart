import 'dart:async';
import 'dart:convert';

import 'package:dartitect_sync/dartitect_sync_titect.dart';
import 'package:test/test.dart';

void main() {
  final codec = TitectSyncCodec();
  final json = TitectJsonCodec();
  final wireError = isA<TitectWireException>();

  test('profile limits can be narrowed but never widened', () {
    expect(
      () => TitectSyncCodec(jsonLimits: TitectJsonLimits(maxBytes: 1048577)),
      throwsArgumentError,
    );
    expect(
      () => TitectSyncCodec(jsonLimits: TitectJsonLimits(maxDepth: 33)),
      throwsArgumentError,
    );
    expect(
      () => TitectSyncCodec(jsonLimits: TitectJsonLimits(maxItems: 10001)),
      throwsArgumentError,
    );
    expect(
      TitectSyncCodec(jsonLimits: TitectJsonLimits(maxBytes: 1024))
          .json
          .limits
          .maxBytes,
      1024,
    );
  });

  test('page byte budget remains charged across failed reads', () async {
    final budget = TitectReadBudget(5);
    await expectLater(
      TitectSyncResponse.read(
        Stream.value(utf8.encode('{bad')),
        codec: codec,
        budget: budget,
      ),
      throwsA(wireError),
    );
    expect(budget.admittedBytes, 4);
    await expectLater(
      TitectSyncResponse.read(
        Stream.value(utf8.encode('{}')),
        codec: codec,
        budget: budget,
      ),
      throwsA(wireError),
    );
    expect(budget.admittedBytes, 4);
    expect(budget.remainingBytes, 1);
  });

  test('retains integers beyond VM and Chrome ranges through round trips', () {
    for (final text in [
      '9007199254740993',
      '18446744073709551617',
      '9' * 1000,
    ]) {
      final wire = utf8.encode(
        '{"protocol":"titect-sync/1","kind":"dataset",'
        '"payload":{"dataset_id":"d","generation":$text,"modes":["delta"]}}',
      );
      final document = codec.decode(wire) as TitectDatasetDescriptor;
      expect(document.generation.toString(), text);
      expect(codec.encode(document), wire);
      expect(() => TitectNumber.parse(text).toIntExact(), throwsA(wireError));
    }
  });

  test(
    'numeric narrowing checks the exact binary value including subnormals',
    () {
      for (final text in ['0', '-0.0', '0.5', '1.25', '9007199254740992']) {
        expect(TitectNumber.parse(text).toDoubleExact(), double.parse(text));
      }
      for (final text in [
        '0.1',
        '9007199254740993',
        '1e-9999',
        '1.00000000000000001',
      ]) {
        expect(
          () => TitectNumber.parse(text).toDoubleExact(),
          throwsA(wireError),
        );
      }
      expect(
        TitectNumber.parse('9007199254740991').toIntExact(),
        9007199254740991,
      );
      for (final text in [
        'NaN',
        'Infinity',
        '1e9999',
        '+1',
        '01',
        '1.',
        '1\n',
      ]) {
        expect(() => TitectNumber.parse(text), throwsA(wireError));
      }
      final decoded = json.decode(utf8.encode('[0.1,1e-9999,-0.0]'));
      expect(utf8.decode(json.encode(decoded)), '[0.1,1e-9999,-0.0]');
      expect(() => json.encode(0.1), throwsA(wireError));
    },
  );

  test(
    'rejects oversized chunks during reading and cancels the source',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final limited = TitectJsonCodec(limits: TitectJsonLimits(maxBytes: 5));
      final read = limited.read(source.stream);
      final expectation = expectLater(read, throwsA(wireError));
      source.add(utf8.encode('[12345'));
      await expectation;
      expect(cancelled, isTrue);
      await source.close();
    },
  );

  test(
    'checks depth, aggregate elements, scalar strings and output before growth',
    () {
      final limited = TitectJsonCodec(
        limits: TitectJsonLimits(
          maxBytes: 100,
          maxDepth: 2,
          maxItems: 4,
          maxStringScalars: 2,
        ),
      );
      expect(
        utf8.decode(limited.encode(limited.decode(utf8.encode('[[0]]')))),
        '[[0]]',
      );
      expect(limited.decode(utf8.encode('"😀a"')), '😀a');
      for (final text in ['[[[0]]]', '[1,2,3,4]', '"😀ab"', '{"abc":0}']) {
        expect(
          () => limited.decode(utf8.encode(text)),
          throwsA(wireError),
          reason: text,
        );
      }
      final cycle = <Object?>[];
      cycle.add(cycle);
      expect(() => limited.encode(cycle), throwsA(wireError));
      expect(() => limited.encode('a' * 1000), throwsA(wireError));
    },
  );

  test('strict UTF-8, Unicode pairs, Python whitespace and scalar sorting', () {
    for (final bytes in [
      <int>[0xff],
      utf8.encode(r'"\ud800"'),
      utf8.encode(r'"\udc00"'),
    ]) {
      expect(() => json.decode(bytes), throwsA(wireError));
    }
    expect(json.decode(utf8.encode(r'"\ud83d\ude00"')), '😀');
    expect(
      utf8.decode(json.encode({'😀': null, '\ue000': null}, sortKeys: true)),
      '{"\ue000":null,"😀":null}',
    );
    for (final id in ['\u0085id', 'id\u001f', '\u2000id']) {
      expect(
        () => codec.fromPayload('dataset', {
          'dataset_id': id,
          'generation': 1,
          'modes': ['delta'],
        }),
        throwsA(wireError),
      );
    }
    expect(
      (codec.fromPayload('dataset', {
        'dataset_id': '\ufeffid',
        'generation': 1,
        'modes': ['delta'],
      }) as TitectDatasetDescriptor).datasetId,
      '\ufeffid',
    );
  });

  test('rejects rollover timestamps, extra fields, versions and unsupported negotiation', () {
    for (final timestamp in [
      '2026-02-30T00:00:00.000Z',
      '0000-01-01T00:00:00.000Z',
      '2026-01-01T24:00:00.000Z',
      '2026-01-01T00:00:00Z',
    ]) {
      expect(
        () => codec.fromPayload('readiness', {
          'ready': true,
          'checked_at': timestamp,
          'reason': null,
          'retry_after_ms': null,
        }),
        throwsA(wireError),
      );
    }
    expect(
      () => codec.decode(
        utf8.encode(
          '{"protocol":"titect-sync/2","kind":"dataset","payload":{}}',
        ),
      ),
      throwsA(wireError),
    );
    expect(
      () => codec.fromPayload('dataset', {
        'dataset_id': 'd',
        'generation': 1,
        'modes': ['delta'],
        'future': true,
      }),
      throwsA(wireError),
    );
    final request = codec.fromPayload('bootstrap_request', {
      'client_id': 'c',
      'dataset_ids': ['d'],
      'capabilities': ['future'],
    }) as TitectBootstrapRequest;
    expect(
      () =>
          codec.requireCapabilities(request.capabilities, supported: {'delta'}),
      throwsA(wireError),
    );
  });

  test(
    'containers are immutable and duplicate keys still consume parser bounds',
    () {
      final value =
          json.decode(utf8.encode('{"x":[1],"x":[2]}')) as Map<String, Object?>;
      expect(utf8.decode(json.encode(value)), '{"x":[2]}');
      expect(() => value['x'] = null, throwsUnsupportedError);
      expect(
        () => (value['x']! as List<Object?>).add(null),
        throwsUnsupportedError,
      );
      final limited = TitectJsonCodec(limits: TitectJsonLimits(maxItems: 3));
      expect(
        () => limited.decode(utf8.encode('{"x":0,"x":0,"x":0}')),
        throwsA(wireError),
      );
    },
  );
}
