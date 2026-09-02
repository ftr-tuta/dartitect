import 'package:dartitect_observability/dartitect_observability.dart';

void configureQaRiskAcceptance() {
  const ObservabilityRiskAcceptance.explicit(
    reason: 'QA-only validation of diagnostic telemetry',
  );
}
