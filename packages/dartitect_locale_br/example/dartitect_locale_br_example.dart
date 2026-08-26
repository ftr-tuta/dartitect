import 'package:dartitect_locale_br/dartitect_locale_br.dart';

void main() {
  final postalCode = BrazilianPostalCode.parse('79002-072');
  assert(postalCode.formatted == '79.002-072');
}
