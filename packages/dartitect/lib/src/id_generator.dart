import 'dart:math';
import 'dart:typed_data';

/// Injectable source of non-empty identifiers.
abstract interface class IdGenerator {
  /// Returns the next identifier owned by this generator instance.
  String nextId();
}

/// Stateless-across-instances UUID v4 generator backed by secure OS entropy.
///
/// Each instance owns its own `Random.secure` source. No global sequence,
/// singleton, timestamp, or device identifier participates in the result.
final class SecureUuidV4Generator implements IdGenerator {
  /// Creates a UUID v4 generator with a fresh secure entropy source.
  SecureUuidV4Generator() : _random = Random.secure();

  final Random _random;

  @override
  String nextId() {
    final bytes = Uint8List(16);
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = _random.nextInt(256);
    }
    return formatUuidV4RandomBytes(bytes);
  }
}

/// Formats exactly 16 random bytes as a canonical RFC 9562 UUID v4.
///
/// This helper is public only inside the package source surface so deterministic
/// conformance tests can exercise exact vectors. Application identifiers should
/// be created through [SecureUuidV4Generator].
String formatUuidV4RandomBytes(List<int> randomBytes) {
  if (randomBytes.length != 16 ||
      randomBytes.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError.value(
      randomBytes,
      'randomBytes',
      'must contain exactly 16 bytes',
    );
  }
  final bytes = Uint8List.fromList(randomBytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
