import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';

final class CanaryPersistence {
  const CanaryPersistence();
}

final class CanaryTransport {
  const CanaryTransport();
}

@DartitectApplicationContextFactory('local_store')
final class LocalStoreFactory {
  const LocalStoreFactory();

  CanaryPersistence open() => const CanaryPersistence();

  void dispose(CanaryPersistence value) {}
}

@DartitectTransportContextFactory('synthetic')
final class SyntheticTransportFactory {
  const SyntheticTransportFactory();

  CanaryTransport open() => const CanaryTransport();

  void dispose(CanaryTransport value) {}
}

final class CanaryLocalPort {
  const CanaryLocalPort();
}

final class CanaryRemotePort {
  const CanaryRemotePort();
}

final class CanaryMapper {
  const CanaryMapper();
}

final class CanaryLocalAuthority {
  const CanaryLocalAuthority();
}

final class CanaryRepository implements AsyncDisposable {
  CanaryRepository() {
    counter = owner.value<int>(0);
    doubled = owner.lazyComputed<int>(
      label: 'canary.counter.doubled',
      dependencies: () => <ReactiveValue<int>>[counter],
      compute: (read) => read.read(counter) * 2,
    );
  }

  final ReactiveOwner owner = ReactiveOwner();
  late final ReactiveValue<int> counter;
  late final ReactiveLazyComputed<int> doubled;
  final BoundedLocalHistory<int> history = BoundedLocalHistory<int>(
    initialValue: 0,
    maxEntries: 8,
  );
  var _disposed = false;

  void increment() {
    owner.update<void>((write) => write.set(counter, counter.value + 1));
    history.edit(counter.value);
  }

  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    history.dispose();
    owner.dispose();
  }
}

final class CanaryViewModel {
  const CanaryViewModel(this.repository);

  final CanaryRepository repository;

  ReactiveValue<int> get counter => repository.counter;
  ReactiveLazyComputed<int> get doubled => repository.doubled;

  void increment() => repository.increment();
}

@DartitectFeatureFactory('paved_road')
final class PavedRoadFactory {
  const PavedRoadFactory();

  CanaryLocalPort createLocalPort() => const CanaryLocalPort();
  CanaryRemotePort createRemotePort() => const CanaryRemotePort();
  CanaryMapper createMapper() => const CanaryMapper();
  CanaryLocalAuthority createLocalAuthority() => const CanaryLocalAuthority();
  CanaryRepository createRepository(CanaryLocalAuthority localAuthority) =>
      CanaryRepository();
  CanaryViewModel createViewModel(CanaryRepository repository) =>
      CanaryViewModel(repository);
}
