import 'dart:math';

import 'package:dartitect_locale_br/dartitect_locale_br.dart';
import 'package:test/test.dart';

const _seed = 11003;
const _cases = 10000;

void main() {
  test('deterministic ASCII CEP fuzz round-trips every supported form', () {
    final random = Random(_seed);
    for (var index = 0; index < _cases; index += 1) {
      final digits = _digits(random);
      final dotted =
          '${digits.substring(0, 2)}.${digits.substring(2, 5)}-'
          '${digits.substring(5)}';
      final hyphenated = '${digits.substring(0, 5)}-${digits.substring(5)}';
      for (final input in <String>[digits, dotted, hyphenated, ' $dotted ']) {
        final value = BrazilianPostalCode.parse(input);
        expect(value.digits, digits, reason: 'seed=$_seed case=$index');
        expect(value.formatted, dotted, reason: 'case=$index');
        expect(value.hyphenated, hyphenated, reason: 'case=$index');
        expect(BrazilianPostalCode.tryParse('$value'), value);
      }
    }
  });

  test('deterministic malformed and Unicode CEP fuzz fails closed', () {
    final random = Random(_seed + 1);
    for (var index = 0; index < _cases; index += 1) {
      final digits = _digits(random);
      final malformedSeparators =
          '${digits.substring(0, 2)}_${digits.substring(2, 5)}-'
          '${digits.substring(5)}';
      final malformed = <String>[
        digits.substring(1),
        '${digits}0',
        '${digits.substring(0, 4)} ${digits.substring(4)}',
        malformedSeparators,
        'Ａ${digits.substring(1)}',
        '${digits.substring(0, 7)}${_fullWidth(digits.codeUnitAt(7) - 48)}',
      ];
      for (final input in malformed) {
        expect(
          BrazilianPostalCode.tryParse(input),
          isNull,
          reason: 'seed=$_seed case=$index input=$input',
        );
      }
    }
  });
}

String _digits(Random random) => List<String>.generate(
  8,
  (_) => '${random.nextInt(10)}',
  growable: false,
).join();

String _fullWidth(int digit) => String.fromCharCode(0xff10 + digit);
