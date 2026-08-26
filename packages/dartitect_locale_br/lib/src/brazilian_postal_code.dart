/// Immutable Brazilian postal code containing exactly eight ASCII digits.
final class BrazilianPostalCode {
  /// Strictly parses [input] or throws [FormatException].
  factory BrazilianPostalCode(String input) => BrazilianPostalCode.parse(input);

  const BrazilianPostalCode._(this.digits);

  /// Strictly parses plain, `XXXXX-XXX`, or `XX.XXX-XXX` input.
  factory BrazilianPostalCode.parse(String input) {
    final value = tryParse(input);
    if (value == null) {
      throw const FormatException(
        'Brazilian postal code must contain exactly eight ASCII digits.',
      );
    }
    return value;
  }

  /// Parses [input], returning `null` for empty, malformed, or Unicode digits.
  static BrazilianPostalCode? tryParse(String input) {
    final trimmed = input.trim();
    final match = RegExp(
      r'^(?:([0-9]{8})|([0-9]{5})-([0-9]{3})|([0-9]{2})\.([0-9]{3})-([0-9]{3}))$',
    ).firstMatch(trimmed);
    if (match == null) return null;
    final digits =
        match.group(1) ??
        (match.group(2) != null
            ? '${match.group(2)}${match.group(3)}'
            : '${match.group(4)}${match.group(5)}${match.group(6)}');
    return BrazilianPostalCode._(digits);
  }

  /// Canonical eight ASCII digits.
  final String digits;

  /// Human-readable `XX.XXX-XXX` representation.
  String get formatted =>
      '${digits.substring(0, 2)}.${digits.substring(2, 5)}-'
      '${digits.substring(5)}';

  /// Compact `XXXXX-XXX` representation.
  String get hyphenated => '${digits.substring(0, 5)}-${digits.substring(5)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrazilianPostalCode && digits == other.digits;

  @override
  int get hashCode => digits.hashCode;

  @override
  String toString() => formatted;
}
