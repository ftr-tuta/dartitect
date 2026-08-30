/// Marks a concrete, statically analyzed application-context factory.
///
/// Tooling resolves this annotation by library identity and never loads or
/// invokes the annotated class in the CLI isolate.
final class DartitectApplicationContextFactory {
  /// Associates the declaration with one config-v3 context name.
  const DartitectApplicationContextFactory(this.context);

  /// Snake-case storage-context name.
  final String context;
}

/// Marks a concrete, statically analyzed session-context factory.
final class DartitectSessionContextFactory {
  /// Associates the declaration with one config-v3 context name.
  const DartitectSessionContextFactory(this.context);

  /// Snake-case storage- or transport-context name.
  final String context;
}

/// Marks the factory that constructs authenticated session graph roots.
final class DartitectSessionFactory {
  /// Creates the annotation.
  const DartitectSessionFactory();
}

/// Marks a concrete, statically analyzed transport-context factory.
final class DartitectTransportContextFactory {
  /// Associates the declaration with one config-v3 transport name.
  const DartitectTransportContextFactory(this.context);

  /// Snake-case transport-context name.
  final String context;
}

/// Marks a concrete consumer-owned feature factory.
final class DartitectFeatureFactory {
  /// Associates the declaration with one config-v3 feature name.
  const DartitectFeatureFactory(this.feature);

  /// Snake-case feature name.
  final String feature;
}
