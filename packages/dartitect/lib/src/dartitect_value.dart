/// Marks one immutable value class for `dartitect model sync`.
///
/// The annotation is passive at runtime. Model discovery and generation live
/// in `dartitect_cli`, so importing this package never adds Analyzer or a build
/// runner to an application.
final class DartitectValue {
  /// Creates the marker used by the native model generator.
  const DartitectValue();
}
