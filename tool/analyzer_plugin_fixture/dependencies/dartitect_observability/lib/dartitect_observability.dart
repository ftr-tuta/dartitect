final class DartitectLogger {
  void info(String message, {ObservabilityContext? context}) {}
}

final class ObservabilityContext {
  const ObservabilityContext({this.attributes = const <String, Object?>{}});

  final Map<String, Object?> attributes;
}

final class ObservabilityClassifiedValue<T> {
  const ObservabilityClassifiedValue(this.value, {required this.classes});

  final T value;
  final Set<Object> classes;
}

final class ObservabilityRiskAcceptance {
  const ObservabilityRiskAcceptance.explicit({required this.reason});

  final String reason;
}

final class ObservabilityRuntime {
  static Object withPrivacy({required List<Object> destinations}) => Object();
}

final class PreparedLogSinkRegistration {
  const PreparedLogSinkRegistration.borrowed(Object sink);
}

final class ObservabilityDestinationRegistration {
  const ObservabilityDestinationRegistration.remote({
    required String name,
    required List<PreparedLogSinkRegistration> logSinks,
  });
}
