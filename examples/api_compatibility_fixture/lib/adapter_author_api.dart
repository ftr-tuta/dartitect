import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';

/// Representative provider adapter metadata with no network execution.
RouteTemplate adapterRoute() => RouteTemplate('/tasks/{id}');

/// Optional feedback parsing compiled against the public provider boundary.
DioRetryAfterPolicy adapterRetryFeedback(ResilienceClock clock) =>
    DioRetryAfterPolicy(
      parser: RetryAfterParser(maximumDelay: const Duration(seconds: 30)),
      clock: clock,
    );
