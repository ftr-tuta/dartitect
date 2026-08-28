abstract interface class AsyncDisposable {
  Future<void> disposeAsync();
}

final class BootstrapCoordinator<T> implements AsyncDisposable {
  @override
  Future<void> disposeAsync() async {}
}

final class ReactiveOwner implements AsyncDisposable {
  @override
  Future<void> disposeAsync() async {}
}
