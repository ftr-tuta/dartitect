import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_observability/dartitect_observability.dart';
import 'package:dartitect_sentry/dartitect_sentry.dart';
import 'package:dio/dio.dart';

final class CustomerValue {
  const CustomerValue();
}

void configurePrivacyViolations(DartitectLogger logger) {
  const authorization = 'Bearer private-token';
  logger.info('authorization=$authorization');

  final dio = Dio();
  dio.interceptors.add(LogInterceptor());
  const DioObservabilityInterceptor();

  const ObservabilityRiskAcceptance.explicit(reason: 'production bypass');
  const ObservabilityContext(
    attributes: <String, Object?>{'customer': CustomerValue()},
  );
  ObservabilityRuntime.withPrivacy(
    destinations: <Object>[
      ObservabilityDestinationRegistration.remote(
        name: 'sentry',
        logSinks: <PreparedLogSinkRegistration>[
          PreparedLogSinkRegistration.borrowed(SentryLogSink()),
        ],
      ),
    ],
  );
}
