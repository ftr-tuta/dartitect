// Consumer-owned, broker-free message conformance fixture.
import 'dart:convert';

import 'package:dartitect_sync/dartitect_sync_titect.dart';

/// Independently validates and encodes the pinned message fixture's profile.
List<int> messageRoundTrip(
  List<int> bytes, {
  String profile = 'titect-message/1',
  TitectJsonLimits? limits,
}) {
  if (profile != 'titect-message/1' && profile != 'titect-message/2') {
    throw const TitectWireException(TitectWireProblem.unsupported);
  }
  final codec = TitectJsonCodec(
    limits: limits ?? TitectJsonLimits(maxStringScalars: 16384),
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
  if (decoded['profile'] != profile) {
    throw const TitectWireException(TitectWireProblem.unsupported);
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
      decoded['specversion'] != '1.0' ||
      decoded['datacontenttype'] != 'application/json') {
    throw const TitectWireException(TitectWireProblem.shape);
  }
  final time = decoded['time']! as String;
  final parsed = DateTime.tryParse(time);
  if (parsed == null ||
      parsed.year == 0 ||
      !parsed.isUtc ||
      parsed.toIso8601String() != time ||
      time.length != 24) {
    throw const TitectWireException(TitectWireProblem.shape);
  }
  // /1 explicitly selects historical binary64 interpretation. /2 never calls
  // this conversion, even when a /1 representation would be convenient.
  final encoded = codec.encode(
    profile == 'titect-message/1' ? _legacy(decoded) : decoded,
    sortKeys: true,
  );
  utf8.decode(encoded); // Explicitly exercise the resulting UTF-8 boundary.
  return encoded;
}

Object? _legacy(Object? value) => switch (value) {
  TitectNumber() => TitectNumber.parse(_legacyNumber(value)),
  List<Object?>() => value.map(_legacy).toList(growable: false),
  Map<String, Object?>() => value.map(
    (key, item) => MapEntry(key, _legacy(item)),
  ),
  _ => value,
};

String _legacyNumber(TitectNumber value) {
  if (value.isInteger) return value.lexeme == '-0' ? '0' : value.lexeme;
  final number = double.parse(value.lexeme);
  if (!number.isFinite) {
    throw const TitectWireException(TitectWireProblem.precision);
  }
  if (number == 0) return number.isNegative ? '-0.0' : '0.0';
  final sign = number.isNegative ? '-' : '';
  final parts = number.abs().toString().toLowerCase().split('e');
  final mantissa = parts.first;
  final dot = mantissa.indexOf('.');
  var digits = mantissa.replaceAll('.', '');
  var decimalPoint =
      (dot < 0 ? mantissa.length : dot) +
      (parts.length == 1 ? 0 : int.parse(parts.last));
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
    decimalPoint--;
  }
  while (digits.length > 1 && digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
  }
  final exponent = decimalPoint - 1;
  if (exponent < -4 || exponent >= 16) {
    final fraction = digits.length == 1 ? '' : '.${digits.substring(1)}';
    return '$sign${digits[0]}${fraction}e${exponent < 0 ? '-' : '+'}'
        '${exponent.abs().toString().padLeft(2, '0')}';
  }
  if (decimalPoint <= 0) return '${sign}0.${'0' * -decimalPoint}$digits';
  if (decimalPoint >= digits.length) {
    return '$sign$digits${'0' * (decimalPoint - digits.length)}.0';
  }
  return '$sign${digits.substring(0, decimalPoint)}.${digits.substring(decimalPoint)}';
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
