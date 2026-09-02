import 'package:dartitect_observability/dartitect_observability.dart';

/// Compiles the observability composition surface published in Dartitect 1.0.
ObservabilityRuntime observabilityRuntimeFromOneDotZero() =>
    ObservabilityRuntime(
      logSinks: const <LogSinkRegistration>[],
      redactor: const Redactor(),
      samplingPolicy: FixedSamplingPolicy(logRate: 1, spanRate: 0),
      allowedContextKeys: const <String>{'safe.count'},
      queueCapacity: 8,
    );
