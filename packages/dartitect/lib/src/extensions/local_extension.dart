import 'dart:async';

/// Marks a project-local, statically compiled Dartitect extension declaration.
///
/// Tooling resolves this annotation by element identity. Annotated classes are
/// never loaded or executed by the CLI and must remain inside the consumer
/// project's real filesystem boundary.
final class DartitectProjectExtension {
  /// Creates the marker used by the semantic extension compiler.
  const DartitectProjectExtension();
}

/// Typed construction and teardown contract for one project-local binding.
///
/// The SDK deliberately provides no registry, string lookup, global install,
/// marketplace, or concrete implementation. Generated composition constructs
/// the declaration directly, owns the concrete [B], and invokes [dispose] once.
abstract interface class DartitectLocalExtension<B extends Object> {
  /// Builds one binding without plugin loading or global registration.
  FutureOr<B> build();

  /// Releases the exact binding returned by [build].
  FutureOr<void> dispose(B binding);
}
