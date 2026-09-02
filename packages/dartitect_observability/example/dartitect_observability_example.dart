import 'package:dartitect_observability/dartitect_observability.dart';

/// Runs local-first observability without a remote provider.
Future<void> main() async {
  final runtime = ObservabilityRuntime.withPrivacy(
    privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
      profile: ObservabilityPrivacyProfile.balanced,
    ),
    destinations: <ObservabilityDestinationRegistration>[
      ObservabilityDestinationRegistration.local(
        name: 'developer',
        logSinks: const <PreparedLogSinkRegistration>[
          PreparedLogSinkRegistration.owned(PreparedDeveloperLogSink()),
        ],
      ),
    ],
  );
  runtime.logger.info('Application started.');
  await runtime.flush(const Duration(seconds: 1));
  await runtime.disposeAsync();
}
