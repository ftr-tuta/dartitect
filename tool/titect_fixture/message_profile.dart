// Consumer-owned, broker-free titect-message/1 conformance fixture.
import 'dart:convert';

import 'package:dartitect_sync/dartitect_sync_titect.dart';

/// Independently validates and encodes the pinned message fixture's profile.
List<int> messageRoundTrip(List<int> bytes) {
  final codec = TitectJsonCodec(
    limits: TitectJsonLimits(maxStringScalars: 16384),
  );
  final decoded = codec.decode(bytes);
  const required = {
    'id',
    'source',
    'specversion',
    'type',
    'subject',
    'time',
    'dataschema',
    'datacontenttype',
    'profile',
    'data',
  };
  const optional = {'correlationid', 'causationid'};
  if (decoded is! Map<String, Object?> ||
      !decoded.keys.toSet().containsAll(required) ||
      !{...required, ...optional}.containsAll(decoded.keys)) {
    throw const TitectWireException(TitectWireProblem.shape);
  }
  for (final name in decoded.keys.where((name) => name != 'data')) {
    if (decoded[name] is! String)
      throw const TitectWireException(TitectWireProblem.shape);
  }
  for (final name in ['id', 'source', 'subject', 'dataschema', ...optional]) {
    final value = decoded[name];
    if (value is String &&
        (value.isEmpty ||
            _space(value.runes.first) ||
            _space(value.runes.last))) {
      throw const TitectWireException(TitectWireProblem.shape);
    }
  }
  final type = decoded['type']! as String;
  final typeMatch = RegExp(r'[A-Za-z][A-Za-z0-9._-]{0,254}')
      .matchAsPrefix(type);
  if (typeMatch?.end != type.length ||
      decoded['profile'] != 'titect-message/1' ||
      decoded['specversion'] != '1.0' ||
      decoded['datacontenttype'] != 'application/json') {
    throw const TitectWireException(TitectWireProblem.unsupported);
  }
  final time = decoded['time']! as String;
  final parsed = DateTime.tryParse(time);
  if (parsed == null ||
      parsed.year == 0 ||
      !parsed.isUtc ||
      parsed.toIso8601String() != time ||
      time.length != 24) {
    throw const TitectWireException(TitectWireProblem.integrity);
  }
  // Preserve decimal tokens. The paired gate reports any disagreement with
  // Python's binary64 canonicalization; it must not silently round to pass.
  final encoded = codec.encode(decoded, sortKeys: true);
  utf8.decode(encoded); // Explicitly exercise the resulting UTF-8 boundary.
  return encoded;
}

bool _space(int scalar) =>
    scalar >= 9 && scalar <= 13 ||
    scalar >= 28 && scalar <= 32 ||
    scalar >= 0x2000 && scalar <= 0x200a ||
    const {
      0x85,
      0xa0,
      0x1680,
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
    }.contains(scalar);
