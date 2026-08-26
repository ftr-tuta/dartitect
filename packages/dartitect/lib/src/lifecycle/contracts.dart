/// A resource that can release itself synchronously.
abstract interface class Disposable {
  /// Releases this resource.
  ///
  /// Implementations should make repeated calls harmless.
  void dispose();
}

/// A resource that can release itself asynchronously.
abstract interface class AsyncDisposable {
  /// Releases this resource and completes after cleanup finishes.
  ///
  /// Implementations should make repeated calls harmless.
  Future<void> disposeAsync();
}
