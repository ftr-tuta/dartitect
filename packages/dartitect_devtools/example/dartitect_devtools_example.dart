import 'package:dartitect/dartitect.dart';
import 'package:dartitect_devtools/dartitect_devtools.dart';
import 'package:dartitect_observability/dartitect_observability.dart';

Future<void> main() async {
  final buffer = DartitectDiagnosticBuffer(capacity: 32);
  final registration = DartitectDevToolsRegistration.register(
    enabled: false,
    buffer: buffer,
    detail: DartitectDiagnosticDetail.topology,
  );
  final runtime = ObservabilityRuntime.withPrivacy(
    privacyPolicy: ObservabilityPrivacyPolicy.fromProfile(
      profile: ObservabilityPrivacyProfile.balanced,
    ),
    destinations: <ObservabilityDestinationRegistration>[
      ObservabilityDestinationRegistration.local(
        logSinks: const <PreparedLogSinkRegistration>[
          PreparedLogSinkRegistration.owned(PreparedDeveloperLogSink()),
        ],
      ),
    ],
  );
  final privacyRegistration =
      DartitectObservabilityPrivacyRegistration.register(
        enabled: false,
        runtime: runtime,
      );

  privacyRegistration.dispose();
  registration.dispose();
  buffer.dispose();
  await runtime.disposeAsync();
}
