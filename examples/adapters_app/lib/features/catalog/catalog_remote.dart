import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';

import 'catalog_model.dart';

/// Provider-neutral remote catalog port consumed by presentation state.
abstract interface class CatalogRemote {
  /// Fetches one typed page without exposing transport DTOs or clients.
  Future<Result<PageBatch<CatalogCursor, CatalogItem>, CatalogFailure>> page(
    PageRequest<CatalogCursor> request,
    CancellationSignal cancellation,
  );
}
