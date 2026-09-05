/// Classification of a bounded HTTP Retry-After field.
enum RetryAfterKind {
  /// The field was not supplied.
  absent,

  /// A non-negative minimum delay was accepted.
  valid,

  /// The field did not match the HTTP grammar.
  invalid,

  /// The field or its delay exceeded the configured bound.
  excessive,
}

/// Payload-free HTTP feedback. Raw field values are never retained.
final class RetryAfterHint {
  const RetryAfterHint._(this.kind, this.minimumDelay);

  /// No server feedback was supplied.
  const RetryAfterHint.absent() : this._(RetryAfterKind.absent, null);

  /// Malformed feedback forbids automatic retry when used in a decision.
  const RetryAfterHint.invalid() : this._(RetryAfterKind.invalid, null);

  /// Excessive feedback must be deferred, never clamped to a shorter delay.
  const RetryAfterHint.excessive() : this._(RetryAfterKind.excessive, null);

  /// Creates a validated non-negative server minimum.
  factory RetryAfterHint.valid(Duration minimumDelay) {
    if (minimumDelay < Duration.zero) {
      throw ArgumentError.value(minimumDelay, 'minimumDelay');
    }
    return RetryAfterHint._(RetryAfterKind.valid, minimumDelay);
  }

  /// Accepted classification.
  final RetryAfterKind kind;

  /// Minimum wait measured from receipt, present only for valid feedback.
  final Duration? minimumDelay;
}

/// Bounded RFC 9110 Retry-After parser supporting all three HTTP-date forms.
///
/// The caller supplies the UTC receipt time and owns clock synchronization.
/// Past dates mean zero delay. No server Date header or clock correction is
/// inferred. Limits are checked before copying or parsing the field.
final class RetryAfterParser {
  /// Creates a parser with explicit retention and accepted-delay limits.
  RetryAfterParser({required this.maximumDelay, this.maximumFieldBytes = 128}) {
    if (maximumDelay < Duration.zero || maximumFieldBytes <= 0) {
      throw ArgumentError('Retry-After bounds are invalid.');
    }
  }

  /// Largest accepted minimum; larger values are excessive, not saturated.
  final Duration maximumDelay;

  /// Maximum ASCII bytes including optional surrounding HTTP whitespace.
  final int maximumFieldBytes;

  /// Parses a single field, without retaining it in the returned metadata.
  RetryAfterHint parse(String? field, {required DateTime receivedAt}) {
    if (!receivedAt.isUtc) {
      throw ArgumentError.value(receivedAt, 'receivedAt', 'Must use UTC.');
    }
    if (field == null) return const RetryAfterHint.absent();
    if (field.length > maximumFieldBytes) {
      return const RetryAfterHint.excessive();
    }
    for (var i = 0; i < field.length; i++) {
      final unit = field.codeUnitAt(i);
      if (unit > 0x7e || unit < 0x20 && unit != 0x09) {
        return const RetryAfterHint.invalid();
      }
    }
    var start = 0;
    var end = field.length;
    bool whitespace(int index) =>
        field.codeUnitAt(index) == 0x20 || field.codeUnitAt(index) == 0x09;
    while (start < end && whitespace(start)) {
      start++;
    }
    while (end > start && whitespace(end - 1)) {
      end--;
    }
    final value = field.substring(start, end);
    if (value.isEmpty) return const RetryAfterHint.invalid();
    if (_digits.hasMatch(value)) {
      final limit = maximumDelay.inSeconds;
      var seconds = 0;
      for (var i = 0; i < value.length; i++) {
        final digit = value.codeUnitAt(i) - 0x30;
        if (seconds > limit ~/ 10 ||
            seconds == limit ~/ 10 && digit > limit % 10) {
          return const RetryAfterHint.excessive();
        }
        seconds = seconds * 10 + digit;
      }
      return RetryAfterHint.valid(Duration(seconds: seconds));
    }
    final date = _date(value, receivedAt);
    if (date == null) return const RetryAfterHint.invalid();
    final delay = date.isAfter(receivedAt)
        ? date.difference(receivedAt)
        : Duration.zero;
    return delay > maximumDelay
        ? const RetryAfterHint.excessive()
        : RetryAfterHint.valid(delay);
  }
}

final _digits = RegExp(r'^[0-9]+$');
final _imf = RegExp(
  r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), ([0-9]{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([0-9]{4}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT$',
);
final _rfc850 = RegExp(
  r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), ([0-9]{2})-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT$',
);
final _asctime = RegExp(
  r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ([0-9]{2}| [0-9]) ([0-9]{2}):([0-9]{2}):([0-9]{2}) ([0-9]{4})$',
);
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime? _date(String value, DateTime now) {
  final imf = _imf.firstMatch(value);
  final obsolete = imf == null ? _rfc850.firstMatch(value) : null;
  final asc = imf == null && obsolete == null
      ? _asctime.firstMatch(value)
      : null;
  final match = imf ?? obsolete ?? asc;
  if (match == null) return null;
  final isAsc = asc != null;
  var year = int.parse(match[isAsc ? 7 : 4]!);
  final month = _months.indexOf(match[isAsc ? 2 : 3]!) + 1;
  final day = int.parse(match[isAsc ? 3 : 2]!.trim());
  final hour = int.parse(match[isAsc ? 4 : 5]!);
  final minute = int.parse(match[isAsc ? 5 : 6]!);
  final second = int.parse(match[isAsc ? 6 : 7]!);
  if (obsolete != null) {
    year += now.year ~/ 100 * 100;
    final candidate = DateTime.utc(year, month, day, hour, minute, second);
    final boundary = DateTime.utc(
      now.year + 50,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    if (candidate.isAfter(boundary)) year -= 100;
  }
  if (year < 1 || hour > 23 || minute > 59 || second > 60) return null;
  final date = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second == 60 ? 59 : second,
  );
  if (date.year != year ||
      date.month != month ||
      date.day != day ||
      _weekdays[date.weekday - 1] != match[1]!.substring(0, 3))
    return null;
  return second == 60 ? date.add(const Duration(seconds: 1)) : date;
}
