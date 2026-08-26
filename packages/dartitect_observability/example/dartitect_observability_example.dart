import 'package:dartitect_observability/dartitect_observability.dart';

/// Runs local-first observability without a remote provider.
Future<void> main() async {
  final runtime = ObservabilityRuntime();
  runtime.logger.info('Application started.');
  await runtime.disposeAsync();
}
