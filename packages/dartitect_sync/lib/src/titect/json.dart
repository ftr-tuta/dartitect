import 'dart:convert';
import 'dart:typed_data';

/// Payload-free classification of a rejected wire document.
enum TitectWireProblem {
  /// Invalid UTF-8, JSON grammar, or scalar value.
  syntax,

  /// A finite allocation or document limit was exceeded.
  limit,

  /// Missing, additional, or incorrectly typed fields.
  shape,

  /// Unsupported protocol, document kind, mode, or capability.
  unsupported,

  /// Inconsistent timestamps, identity, or integrity metadata.
  integrity,

  /// A requested numeric conversion would lose precision.
  precision,
}

/// Expected wire failure containing no document values or opaque identifiers.
final class TitectWireException implements Exception {
  /// Creates a payload-free rejection.
  const TitectWireException(this.problem);

  /// Stable reason suitable for consumer failure mapping.
  final TitectWireProblem problem;

  @override
  String toString() => 'TitectWireException(${problem.name})';
}

/// JSON number retained as decimal text, without a VM or browser `num` cast.
final class TitectNumber {
  TitectNumber._(this.lexeme);

  /// Validates one finite JSON number within an explicit character bound.
  factory TitectNumber.parse(String value, {int maxCharacters = 1048576}) {
    if (maxCharacters <= 0) throw ArgumentError.value(maxCharacters);
    if (value.length > maxCharacters) {
      throw const TitectWireException(TitectWireProblem.limit);
    }
    if (_number.firstMatch(value)?.end != value.length ||
        (value.contains(RegExp('[.eE]')) && !double.parse(value).isFinite)) {
      throw const TitectWireException(TitectWireProblem.syntax);
    }
    return TitectNumber._(value);
  }

  static final _number = RegExp(
    r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$',
  );

  /// Original JSON token, including its decimal/exponent representation.
  final String lexeme;

  /// Whether the token uses JSON integer syntax.
  bool get isInteger => !lexeme.contains(RegExp('[.eE]'));

  /// Converts integer syntax to arbitrary precision without rounding.
  BigInt toBigIntExact() {
    if (!isInteger)
      throw const TitectWireException(TitectWireProblem.precision);
    return BigInt.parse(lexeme);
  }

  /// Converts only within the exact portable integer range, on every platform.
  int toIntExact() {
    final value = toBigIntExact();
    if (value.abs() > BigInt.parse('9007199254740991')) {
      throw const TitectWireException(TitectWireProblem.precision);
    }
    return value.toInt();
  }

  /// Converts only when the decimal value equals the binary64 value exactly.
  double toDoubleExact() {
    final result = double.parse(lexeme);
    if (!result.isFinite) {
      throw const TitectWireException(TitectWireProblem.precision);
    }
    final parts = lexeme.toLowerCase().split('e');
    final mantissa = parts.first.replaceAll('.', '');
    final numerator = BigInt.parse(mantissa);
    if (numerator == BigInt.zero) return result;
    final exponent = parts.length == 1 ? 0 : int.tryParse(parts.last);
    // Nonzero binary64 values cannot equal decimal exponents beyond this
    // bounded range. Refuse before constructing an unbounded power of ten.
    if (exponent == null || exponent.abs() > lexeme.length + 1075) {
      throw const TitectWireException(TitectWireProblem.precision);
    }
    final dot = parts.first.indexOf('.');
    final scale = (dot < 0 ? 0 : parts.first.length - dot - 1) - exponent;
    final decimalNumerator = scale < 0
        ? numerator * BigInt.from(10).pow(-scale)
        : numerator;
    final decimalDenominator = scale > 0
        ? BigInt.from(10).pow(scale)
        : BigInt.one;
    final bytes = ByteData(8)..setFloat64(0, result);
    final high = bytes.getUint32(0);
    final low = bytes.getUint32(4);
    final binaryExponent = (high >> 20) & 0x7ff;
    var binaryNumerator =
        (BigInt.from(high & 0xfffff) << 32) | BigInt.from(low);
    if (binaryExponent != 0) binaryNumerator |= BigInt.one << 52;
    if ((high & 0x80000000) != 0) binaryNumerator = -binaryNumerator;
    final power = (binaryExponent == 0 ? 1 : binaryExponent) - 1023 - 52;
    final binaryDenominator = power < 0 ? BigInt.one << -power : BigInt.one;
    if (power > 0) binaryNumerator <<= power;
    if (decimalNumerator * binaryDenominator !=
        binaryNumerator * decimalDenominator) {
      throw const TitectWireException(TitectWireProblem.precision);
    }
    return result;
  }

  @override
  String toString() => lexeme;
}

/// Allocation limits applied before retaining strings, children, or bytes.
final class TitectJsonLimits {
  /// Creates positive bounds; depth counts the root as zero.
  TitectJsonLimits({
    this.maxBytes = 1048576,
    this.maxDepth = 32,
    this.maxItems = 10000,
    this.maxStringScalars = 1048576,
  }) {
    if (maxBytes <= 0 ||
        maxDepth <= 0 ||
        maxDepth > 128 ||
        maxItems <= 0 ||
        maxStringScalars <= 0) {
      throw ArgumentError('Invalid JSON allocation bounds.');
    }
  }

  /// Bytes accepted from a transport, independently of Content-Length.
  final int maxBytes;

  /// Maximum nesting; capped at 128 to bound recursive parser stack usage.
  final int maxDepth;

  /// Aggregate values, including containers; keys have separate string bounds.
  final int maxItems;

  /// Unicode scalar values per decoded string or key.
  final int maxStringScalars;
}

/// Bounded JSON reader preserving numbers and rejecting unpaired surrogates.
///
/// Decoded containers are immutable. No unbounded `jsonDecode` tree is built.
/// Duplicate object keys follow the pinned Python decoder's last-value rule;
/// all occurrences still consume the parser's allocation counters.
final class TitectJsonCodec {
  /// Uses explicit allocation bounds.
  TitectJsonCodec({TitectJsonLimits? limits})
    : limits = limits ?? TitectJsonLimits();

  /// Limits enforced by both input and output paths.
  final TitectJsonLimits limits;

  /// Reads at most the byte budget, cancelling the subscription on rejection.
  Future<Object?> read(Stream<List<int>> chunks) async {
    final bytes = BytesBuilder(copy: true);
    await for (final chunk in chunks) {
      if (chunk.length > limits.maxBytes - bytes.length) {
        throw const TitectWireException(TitectWireProblem.limit);
      }
      bytes.add(chunk);
    }
    return decode(bytes.takeBytes());
  }

  /// Parses bytes with strict UTF-8 and incremental structural admission.
  Object? decode(List<int> bytes) {
    if (bytes.length > limits.maxBytes) {
      throw const TitectWireException(TitectWireProblem.limit);
    }
    try {
      return _Parser(utf8.decode(bytes), limits).parse();
    } on FormatException {
      throw const TitectWireException(TitectWireProblem.syntax);
    }
  }

  /// Encodes bounded JSON with exact numeric tokens and optional key sorting.
  ///
  /// Sorting uses Unicode scalar order. This is not a claim of compatibility
  /// with a canonical numeric or integrity profile.
  List<int> encode(Object? value, {bool sortKeys = false}) {
    final output = BytesBuilder(copy: false);
    var count = 0;
    void emit(String text) {
      if (text.length > limits.maxBytes - output.length) {
        throw const TitectWireException(TitectWireProblem.limit);
      }
      final bytes = utf8.encode(text);
      if (bytes.length > limits.maxBytes - output.length) {
        throw const TitectWireException(TitectWireProblem.limit);
      }
      output.add(bytes);
    }

    void write(Object? item, int depth) {
      if (depth > limits.maxDepth || ++count > limits.maxItems) {
        throw const TitectWireException(TitectWireProblem.limit);
      }
      switch (item) {
        case null:
          emit('null');
        case bool():
          emit(item ? 'true' : 'false');
        case TitectNumber():
          emit(item.lexeme);
        case BigInt():
          emit(item.toString());
        case int():
          if (item.abs() > 9007199254740991) {
            throw const TitectWireException(TitectWireProblem.precision);
          }
          emit(item.toString());
        case String():
          _validateString(item, limits.maxStringScalars);
          if (item.length > limits.maxBytes - output.length) {
            throw const TitectWireException(TitectWireProblem.limit);
          }
          emit(jsonEncode(item));
        case List<Object?>():
          emit('[');
          for (var i = 0; i < item.length; i++) {
            if (i != 0) emit(',');
            write(item[i], depth + 1);
          }
          emit(']');
        case Map<String, Object?>():
          if (item.length > limits.maxItems - count) {
            throw const TitectWireException(TitectWireProblem.limit);
          }
          final keys = item.keys.toList();
          if (sortKeys) keys.sort(_compareScalars);
          emit('{');
          for (var i = 0; i < keys.length; i++) {
            if (i != 0) emit(',');
            _validateString(keys[i], limits.maxStringScalars);
            emit(jsonEncode(keys[i]));
            emit(':');
            write(item[keys[i]], depth + 1);
          }
          emit('}');
        default:
          throw const TitectWireException(TitectWireProblem.shape);
      }
    }

    write(value, 0);
    return output.takeBytes();
  }
}

void _validateString(String value, int maximum) {
  var scalars = 0;
  for (var i = 0; i < value.length; i++) {
    if (++scalars > maximum)
      throw const TitectWireException(TitectWireProblem.limit);
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const TitectWireException(TitectWireProblem.syntax);
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const TitectWireException(TitectWireProblem.syntax);
    }
  }
}

int _compareScalars(String a, String b) {
  final left = a.runes.iterator;
  final right = b.runes.iterator;
  while (left.moveNext()) {
    if (!right.moveNext()) return 1;
    final result = left.current.compareTo(right.current);
    if (result != 0) return result;
  }
  return right.moveNext() ? -1 : 0;
}

final class _Parser {
  _Parser(this.source, this.limits);
  final String source;
  final TitectJsonLimits limits;
  var offset = 0;
  var items = 0;

  Never syntax() => throw const TitectWireException(TitectWireProblem.syntax);
  Never bound() => throw const TitectWireException(TitectWireProblem.limit);
  int get peek => offset < source.length ? source.codeUnitAt(offset) : -1;
  void whitespace() {
    while (peek == 32 || peek == 9 || peek == 10 || peek == 13) {
      offset++;
    }
  }

  void require(int unit) {
    if (peek != unit) syntax();
    offset++;
  }

  Object? parse() {
    final result = value(0);
    whitespace();
    if (offset != source.length) syntax();
    return result;
  }

  Object? value(int depth) {
    if (depth > limits.maxDepth || ++items > limits.maxItems) bound();
    whitespace();
    if (peek == 34) return string();
    if (peek == 123) {
      offset++;
      whitespace();
      final result = <String, Object?>{};
      if (peek != 125) {
        while (true) {
          final key = string();
          whitespace();
          require(58);
          result[key] = value(depth + 1);
          whitespace();
          if (peek != 44) break;
          offset++;
          whitespace();
        }
      }
      require(125);
      return Map<String, Object?>.unmodifiable(result);
    }
    if (peek == 91) {
      offset++;
      whitespace();
      final result = <Object?>[];
      if (peek != 93) {
        while (true) {
          result.add(value(depth + 1));
          whitespace();
          if (peek != 44) break;
          offset++;
        }
      }
      require(93);
      return List<Object?>.unmodifiable(result);
    }
    for (final literal in const {
      'null': null,
      'true': true,
      'false': false,
    }.entries) {
      if (source.startsWith(literal.key, offset)) {
        offset += literal.key.length;
        return literal.value;
      }
    }
    final start = offset;
    while (peek >= 48 && peek <= 57 ||
        peek == 45 ||
        peek == 43 ||
        peek == 46 ||
        peek == 101 ||
        peek == 69) {
      offset++;
    }
    if (offset == start) syntax();
    return TitectNumber.parse(
      source.substring(start, offset),
      maxCharacters: limits.maxBytes,
    );
  }

  String string() {
    require(34);
    final result = StringBuffer();
    var scalars = 0;
    var highSurrogate = false;
    while (peek != 34) {
      if (peek < 32) syntax();
      var unit = source.codeUnitAt(offset++);
      if (unit == 92) {
        final escape = peek;
        offset++;
        unit = switch (escape) {
          34 || 47 || 92 => escape,
          98 => 8,
          102 => 12,
          110 => 10,
          114 => 13,
          116 => 9,
          117 => hexUnit(),
          _ => syntax(),
        };
      }
      if (highSurrogate) {
        if (unit < 0xdc00 || unit > 0xdfff) syntax();
        highSurrogate = false;
      } else {
        if (unit >= 0xdc00 && unit <= 0xdfff) syntax();
        if (++scalars > limits.maxStringScalars) bound();
        highSurrogate = unit >= 0xd800 && unit <= 0xdbff;
      }
      result.writeCharCode(unit);
    }
    if (highSurrogate) syntax();
    offset++;
    return result.toString();
  }

  int hexUnit() {
    if (source.length - offset < 4) syntax();
    final token = source.substring(offset, offset + 4);
    if (!RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(token)) syntax();
    offset += 4;
    return int.parse(token, radix: 16);
  }
}
