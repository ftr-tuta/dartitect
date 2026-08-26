import 'package:dartitect/dartitect.dart';

/// Immutable catalog item projected from infrastructure DTOs.
final class CatalogItem extends ValueEquality {
  /// Creates a catalog value.
  const CatalogItem({
    required this.id,
    required this.title,
    required this.version,
  });

  /// Stable item key.
  final int id;

  /// Display title mapped from the DTO.
  final String title;

  /// Projection version.
  final int version;

  @override
  Iterable<Object?> get equalityFields => <Object?>[id, title, version];
}

/// Typed page/search cursor.
final class CatalogCursor extends ValueEquality {
  /// Creates a cursor.
  const CatalogCursor({this.offset = 0, this.query = ''});

  /// Zero-based remote offset.
  final int offset;

  /// Consumer search query.
  final String query;

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
