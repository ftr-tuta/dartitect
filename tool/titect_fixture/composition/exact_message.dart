import 'package:dartitect_sync/dartitect_sync_titect.dart';

/// Synthetic consumer data used identically by native persistence and capacity.
List<int> exactMessage(String identity, {bool large = false}) =>
    TitectJsonCodec().encode({
      'id': identity,
      'source': 'urn:example:dartitect',
      'specversion': '1.0',
      'type': 'example.changed.v1',
      'subject': 'synthetic',
      'time': '2026-09-05T00:00:00.000Z',
      'dataschema': 'urn:example:exact:1',
      'datacontenttype': 'application/json',
      'profile': 'titect-message/2',
      'data': {
        'value': TitectNumber.parse('1.00000000000000001'),
        'tokens': [
          for (final token in [
            '1',
            '1.0',
            '1e0',
            '1E+000',
            '-0',
            '-0.0',
            '1e9999999999999999999999',
            '1e-9999999999999999999999',
            if (large) '9' * 4301,
          ])
            TitectNumber.parse(token),
        ],
        'text': '😀\ue000\u2028\u2029\u0000',
      },
    }, sortKeys: true);
