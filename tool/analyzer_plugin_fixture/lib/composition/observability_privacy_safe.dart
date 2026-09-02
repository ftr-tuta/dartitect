import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sentry/dartitect_sentry.dart';

final class ReviewedCustomerValue {
  const ReviewedCustomerValue();
}

void configurePrivacySafely(DartitectLogger logger) {
  logger.info('static privacy event');
  const DioObservabilityInterceptor();
  const ObservabilityContext(
    attributes: <String, Object?>{
      'customer': ObservabilityClassifiedValue<ReviewedCustomerValue>(
        ReviewedCustomerValue(),
        classes: <Object>{'business.customer.value'},
      ),
    },
  );
  ObservabilityRuntime.withPrivacy(
    destinations: <Object>[
      ObservabilityDestinationRegistration.remote(
        name: 'sentry',
        logSinks: <PreparedLogSinkRegistration>[
          PreparedLogSinkRegistration.borrowed(SentryLogSink.sanitizedInput()),
        ],
      ),
    ],
  );
}
