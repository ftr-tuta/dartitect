import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dio/dio.dart';

import '../features/catalog/catalog_model.dart';
import '../features/catalog/catalog_remote.dart';

/// Dio-backed catalog adapter kept inside the infrastructure boundary.
final class DioCatalogRemote implements CatalogRemote {
  /// Creates an adapter around a borrowed, consumer-configured [Dio].
  const DioCatalogRemote(this.dio);

  /// Borrowed client owned by the application composition root.
  final Dio dio;

  @override
  Future<Result<PageBatch<CatalogCursor, CatalogItem>, CatalogFailure>> page(
    PageRequest<CatalogCursor> request,
    CancellationSignal cancellation,
  ) async {
    final binding = DioCancellationBinding(cancellation);
    try {
      final response = await captureDioException<Response<Object?>>(
        () => dio.get<Object?>(
          '/catalog',
          queryParameters: <String, Object?>{
            'offset': request.cursor.offset,
            'query': request.cursor.query,
          },
          options: Options(
            extra: <String, Object?>{
              'routeTemplate': RouteTemplate('/catalog'),
            },
          ),
          cancelToken: binding.token,
        ),
      );
      if (response case Err<DioFailure>(:final stackTrace)) {
        return Err<CatalogFailure>(
          const CatalogFailure('transport'),
          stackTrace,
        );
      }
      return _mapResponse(
        (response as Ok<Response<Object?>>).value,
        request.cursor,
      );
    } finally {
      binding.dispose();
    }
  }

  Result<PageBatch<CatalogCursor, CatalogItem>, CatalogFailure> _mapResponse(
    Response<Object?> response,
    CatalogCursor cursor,
  ) {
    final rows = response.data;
    if (rows is! List<Object?>) {
      return Err<CatalogFailure>(
        const CatalogFailure('mapping'),
        StackTrace.current,
      );
    }
    final items = <CatalogItem>[
      for (final row in rows)
        if (row is Map<String, Object?>)
          CatalogItem(
            id: row['id']! as int,
            title: row['title']! as String,
            version: row['version']! as int,
          ),
    ];
    return Ok<PageBatch<CatalogCursor, CatalogItem>>(
      PageBatch<CatalogCursor, CatalogItem>(
        items: items,
        nextCursor: items.length < 25
            ? null
            : CatalogCursor(
                offset: cursor.offset + items.length,
                query: cursor.query,
              ),
      ),
    );
  }
}
