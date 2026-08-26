import 'package:dartitect_locale_br/dartitect_locale_br.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes supported forms and exposes both masks', () {
    for (final input in const <String>['12345678', '12345-678', '12.345-678']) {
      final value = BrazilianPostalCode.parse(input);
      expect(value.digits, '12345678');
      expect(value.formatted, '12.345-678');
      expect(value.hyphenated, '12345-678');
    }
  });

  test('tryParse rejects empty, malformed, and Unicode lookalike digits', () {
    for (final input in const <String>[
      '',
      '123',
      '1234 5678',
      '１２３４５６７８',
      '١٢٣٤٥٦٧٨',
      '12.345_678',
    ]) {
      expect(BrazilianPostalCode.tryParse(input), isNull, reason: input);
      expect(() => BrazilianPostalCode.parse(input), throwsFormatException);
    }
  });

  test('has value equality and canonical string output', () {
    final left = BrazilianPostalCode('12.345-678');
    final right = BrazilianPostalCode('12345678');
    expect(left, right);
    expect(left.hashCode, right.hashCode);
    expect('$left', '12.345-678');
  });

  test('accepts structural edge values without claiming assignment', () {
    final value = BrazilianPostalCode.parse(' 00.000-000 ');
    expect(value.digits, '00000000');
    expect(value.formatted, '00.000-000');
  });
}
