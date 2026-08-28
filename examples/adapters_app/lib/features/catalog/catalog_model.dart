import 'package:dartitect/dartitect.dart';

/// Immutable catalog item projected from infrastructure DTOs.
final class const CatalogItem({
  /// Stable item key.
  required final int id,

  /// Display title mapped from the DTO.
  required final String title,

  /// Projection version.
  required final int version,
}) extends ValueEquality {
  /// Creates a catalog value.
  this;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, title, version];
}

/// Typed page/search cursor.
final class const CatalogCursor({
  /// Zero-based remote offset.
  final int offset = 0,

  /// Consumer search query.
  final String query = '',
}) extends ValueEquality {
  /// Creates a cursor.
  this;

  @override
  Iterable<Object?> get equalityFields => <Object?>[offset, query];
}

/// Expected catalog boundary failure without response payload.
final class CatalogFailure implements Exception {
  /// Creates a safe failure classification.
  const CatalogFailure(this.code);

  /// Stable safe classification.
  final String code;
}
