// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_dio/dartitect_dio.dart';
import 'package:dartitect_flutter/dartitect_flutter_reactive.dart';
import 'package:dartitect_sync/dartitect_sync.dart';

abstract final class LargeCensus {
  static int liveContexts = 0;
  static int appStorageOpens = 0;
  static int sessionStorageOpens = 0;
  static int appTransportOpens = 0;
  static int sessionTransportOpens = 0;
  static int sessionCreates = 0;
}

final class LargeFailure implements Exception {
  const LargeFailure(this.code);
  final String code;
}

final class LargeMutation {
  const LargeMutation(this.value);
  final String value;
}

abstract interface class LargeLocalPort {
  Stream<void> watch();
  Future<Result<List<String>, LargeFailure>> read(
    CancellationSignal cancellation,
  );
}

base class LargeStorage
    implements
        LargeLocalPort,
        MutationOutboxStore<String, LargeMutation, LargeFailure> {
  LargeStorage() {
    LargeCensus.liveContexts += 1;
  }
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final LargeCheckpointStore checkpoints = LargeCheckpointStore();
  final Map<String, OutboxOperation<String, LargeMutation>> _outbox =
      <String, OutboxOperation<String, LargeMutation>>{};
  bool disposed = false;
  @override
  Stream<void> watch() => _changes.stream;
  @override
  Future<Result<List<String>, LargeFailure>> read(
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<List<String>>(<String>['large']);
  }

  @override
  Future<Result<void, LargeFailure>> applyLocalAndEnqueue(
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    _outbox[operation.idempotencyKey] = operation;
    _changes.add(null);
    return const Ok<void>(null);
  }

  @override
  Future<Result<void, LargeFailure>> markState(
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal signal,
  ) async {
    signal.throwIfCancelled();
    _outbox[operation.idempotencyKey] = operation;
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<OutboxOperation<String, LargeMutation>>, LargeFailure>>
  loadRecoverable(CancellationSignal signal) async {
    signal.throwIfCancelled();
    return Ok<List<OutboxOperation<String, LargeMutation>>>(
      List<OutboxOperation<String, LargeMutation>>.unmodifiable(_outbox.values),
    );
  }

  @override
  Future<Result<void, LargeFailure>> compensate(
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal signal,
  ) async => const Ok<void>(null);
  Future<void> close() async {
    if (disposed) return;
    disposed = true;
    LargeCensus.liveContexts -= 1;
    await _changes.close();
  }
}

final class LargeCheckpointStore implements SyncCheckpointStore<String, int> {
  final Map<String, int> _values = <String, int>{};
  @override
  Future<int?> read(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    return _values[key];
  }

  @override
  Future<void> write(
    String key,
    int checkpoint,
    CancellationSignal signal, {
    int? fencingToken,
  }) async {
    signal.throwIfCancelled();
    _values[key] = checkpoint;
  }

  @override
  Future<void> remove(String key, CancellationSignal signal) async {
    signal.throwIfCancelled();
    _values.remove(key);
  }
}

final class AppStorage extends LargeStorage {}

final class SessionStorage extends LargeStorage {}

@DartitectApplicationContextFactory('app_storage')
final class AppStorageFactory {
  Future<AppStorage> open() async {
    LargeCensus.appStorageOpens += 1;
    return AppStorage();
  }

  Future<void> dispose(AppStorage value) => value.close();
}

@DartitectSessionContextFactory('session_storage')
final class SessionStorageFactory {
  Future<SessionStorage> open() async {
    LargeCensus.sessionStorageOpens += 1;
    return SessionStorage();
  }

  Future<void> dispose(SessionStorage value) => value.close();
}

base class LargeTransport implements Disposable {
  LargeTransport(this.owner) {
    LargeCensus.liveContexts += 1;
  }
  final DioOwner owner;
  DioJsonClient get client => DefaultDioJsonClient(owner.dio);
  bool disposed = false;
  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    owner.dispose();
    LargeCensus.liveContexts -= 1;
  }
}

final class AppTransport extends LargeTransport {
  AppTransport(super.owner);
}

final class SessionTransport extends LargeTransport {
  SessionTransport(super.owner);
}

@DartitectTransportContextFactory('app_api')
final class AppTransportFactory {
  AppTransport open() {
    LargeCensus.appTransportOpens += 1;
    return AppTransport(DioOwner.create());
  }

  DioJsonClient client(AppTransport value) => value.client;
  void dispose(AppTransport value) => value.dispose();
}

@DartitectTransportContextFactory('session_api')
final class SessionTransportFactory {
  SessionTransport open() {
    LargeCensus.sessionTransportOpens += 1;
    return SessionTransport(DioOwner.create());
  }

  void dispose(SessionTransport value) => value.dispose();
}

final class LargeSession {
  const LargeSession();
}

@DartitectSessionFactory()
final class LargeSessionFactory {
  LargeSession create() {
    LargeCensus.sessionCreates += 1;
    return const LargeSession();
  }
}

final class LargeRemotePort {
  const LargeRemotePort(this.transport);
  final LargeTransport transport;
}

final class LargeMapper {
  const LargeMapper();
}

final class LargeRepository implements AsyncDisposable {
  LargeRepository(Iterable<Object> seams) : seams = List<Object>.of(seams);
  final List<Object> seams;
  bool disposed = false;
  @override
  Future<void> disposeAsync() async {
    disposed = true;
  }
}

final class LargeViewModel implements AsyncDisposable {
  const LargeViewModel(this.repository);
  final LargeRepository repository;
  @override
  Future<void> disposeAsync() async {}
}

final class LargeIdempotencyPolicy
    implements MutationIdempotencyPolicy<String, LargeMutation> {
  const LargeIdempotencyPolicy();
  @override
  String create(String key, LargeMutation argument) =>
      'large:$key:${argument.value}';
}

final class LargeConflictPolicy implements MutationConflictPolicy<String> {
  const LargeConflictPolicy();
  @override
  String resolve(String local, String remote) => local;
}

@DartitectFeatureFactory('local_application_1')
final class LocalApplication1Factory {
  const LocalApplication1Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRepository createRepository(
    LargeLocalPort localPort,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('local_application_2')
final class LocalApplication2Factory {
  const LocalApplication2Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRepository createRepository(
    LargeLocalPort localPort,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('local_application_3')
final class LocalApplication3Factory {
  const LocalApplication3Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRepository createRepository(
    LargeLocalPort localPort,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('local_session_1')
final class LocalSession1Factory {
  const LocalSession1Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRepository createRepository(
    LargeLocalPort localPort,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('local_session_2')
final class LocalSession2Factory {
  const LocalSession2Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRepository createRepository(
    LargeLocalPort localPort,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('local_session_3')
final class LocalSession3Factory {
  const LocalSession3Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRepository createRepository(
    LargeLocalPort localPort,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('online_application_1')
final class OnlineApplication1Factory {
  const OnlineApplication1Factory();
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeRemotePort remotePort,
    LargeMapper mapper,
  ) => LargeRepository(<Object>[remotePort, mapper]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('online_application_2')
final class OnlineApplication2Factory {
  const OnlineApplication2Factory();
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeRemotePort remotePort,
    LargeMapper mapper,
  ) => LargeRepository(<Object>[remotePort, mapper]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('online_application_3')
final class OnlineApplication3Factory {
  const OnlineApplication3Factory();
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeRemotePort remotePort,
    LargeMapper mapper,
  ) => LargeRepository(<Object>[remotePort, mapper]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('online_session_1')
final class OnlineSession1Factory {
  const OnlineSession1Factory();
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeRemotePort remotePort,
    LargeMapper mapper,
  ) => LargeRepository(<Object>[remotePort, mapper]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('online_session_2')
final class OnlineSession2Factory {
  const OnlineSession2Factory();
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeRemotePort remotePort,
    LargeMapper mapper,
  ) => LargeRepository(<Object>[remotePort, mapper]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('online_session_3')
final class OnlineSession3Factory {
  const OnlineSession3Factory();
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeRemotePort remotePort,
    LargeMapper mapper,
  ) => LargeRepository(<Object>[remotePort, mapper]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('cache_application_1')
final class CacheApplication1Factory {
  const CacheApplication1Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, remotePort, mapper, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('cache_application_2')
final class CacheApplication2Factory {
  const CacheApplication2Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, remotePort, mapper, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('cache_application_3')
final class CacheApplication3Factory {
  const CacheApplication3Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, remotePort, mapper, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('cache_session_1')
final class CacheSession1Factory {
  const CacheSession1Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, remotePort, mapper, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('cache_session_2')
final class CacheSession2Factory {
  const CacheSession2Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, remotePort, mapper, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('cache_session_3')
final class CacheSession3Factory {
  const CacheSession3Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
  ) => LargeRepository(<Object>[localPort, remotePort, mapper, localAuthority]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('replica_application_1')
final class ReplicaApplication1Factory {
  const ReplicaApplication1Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'replica_application_1',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(AppStorage storage) =>
      storage.checkpoints;
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('replica_application_2')
final class ReplicaApplication2Factory {
  const ReplicaApplication2Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'replica_application_2',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(AppStorage storage) =>
      storage.checkpoints;
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('replica_application_3')
final class ReplicaApplication3Factory {
  const ReplicaApplication3Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'replica_application_3',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(AppStorage storage) =>
      storage.checkpoints;
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('replica_session_1')
final class ReplicaSession1Factory {
  const ReplicaSession1Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'replica_session_1',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(
    SessionStorage storage,
  ) => storage.checkpoints;
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('replica_session_2')
final class ReplicaSession2Factory {
  const ReplicaSession2Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'replica_session_2',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(
    SessionStorage storage,
  ) => storage.checkpoints;
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('replica_session_3')
final class ReplicaSession3Factory {
  const ReplicaSession3Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'replica_session_3',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(
    SessionStorage storage,
  ) => storage.checkpoints;
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('offline_full_application_1')
final class OfflineFullApplication1Factory {
  const OfflineFullApplication1Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'offline_full_application_1',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(AppStorage storage) =>
      storage.checkpoints;
  MutationOutboxStore<String, LargeMutation, LargeFailure> createOutboxStore(
    AppStorage storage,
  ) => storage;
  MutationIdempotencyPolicy<String, LargeMutation> createIdempotencyPolicy() =>
      const LargeIdempotencyPolicy();
  MutationConflictPolicy<String> createConflictPolicy() =>
      const LargeConflictPolicy();
  Future<Result<void, LargeFailure>> synchronizeMutation(
    LargeRemotePort remotePort,
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<void>(null);
  }

  MutationFailurePolicy classifyMutationFailure(LargeFailure failure) =>
      const MutationFailurePolicy.queued();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('offline_full_application_2')
final class OfflineFullApplication2Factory {
  const OfflineFullApplication2Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'offline_full_application_2',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(AppStorage storage) =>
      storage.checkpoints;
  MutationOutboxStore<String, LargeMutation, LargeFailure> createOutboxStore(
    AppStorage storage,
  ) => storage;
  MutationIdempotencyPolicy<String, LargeMutation> createIdempotencyPolicy() =>
      const LargeIdempotencyPolicy();
  MutationConflictPolicy<String> createConflictPolicy() =>
      const LargeConflictPolicy();
  Future<Result<void, LargeFailure>> synchronizeMutation(
    LargeRemotePort remotePort,
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<void>(null);
  }

  MutationFailurePolicy classifyMutationFailure(LargeFailure failure) =>
      const MutationFailurePolicy.queued();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('offline_full_application_3')
final class OfflineFullApplication3Factory {
  const OfflineFullApplication3Factory();
  LargeLocalPort createLocalPort(AppStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(AppTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'offline_full_application_3',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(AppStorage storage) =>
      storage.checkpoints;
  MutationOutboxStore<String, LargeMutation, LargeFailure> createOutboxStore(
    AppStorage storage,
  ) => storage;
  MutationIdempotencyPolicy<String, LargeMutation> createIdempotencyPolicy() =>
      const LargeIdempotencyPolicy();
  MutationConflictPolicy<String> createConflictPolicy() =>
      const LargeConflictPolicy();
  Future<Result<void, LargeFailure>> synchronizeMutation(
    LargeRemotePort remotePort,
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<void>(null);
  }

  MutationFailurePolicy classifyMutationFailure(LargeFailure failure) =>
      const MutationFailurePolicy.queued();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('offline_full_session_1')
final class OfflineFullSession1Factory {
  const OfflineFullSession1Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'offline_full_session_1',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(
    SessionStorage storage,
  ) => storage.checkpoints;
  MutationOutboxStore<String, LargeMutation, LargeFailure> createOutboxStore(
    SessionStorage storage,
  ) => storage;
  MutationIdempotencyPolicy<String, LargeMutation> createIdempotencyPolicy() =>
      const LargeIdempotencyPolicy();
  MutationConflictPolicy<String> createConflictPolicy() =>
      const LargeConflictPolicy();
  Future<Result<void, LargeFailure>> synchronizeMutation(
    LargeRemotePort remotePort,
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<void>(null);
  }

  MutationFailurePolicy classifyMutationFailure(LargeFailure failure) =>
      const MutationFailurePolicy.queued();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('offline_full_session_2')
final class OfflineFullSession2Factory {
  const OfflineFullSession2Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'offline_full_session_2',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(
    SessionStorage storage,
  ) => storage.checkpoints;
  MutationOutboxStore<String, LargeMutation, LargeFailure> createOutboxStore(
    SessionStorage storage,
  ) => storage;
  MutationIdempotencyPolicy<String, LargeMutation> createIdempotencyPolicy() =>
      const LargeIdempotencyPolicy();
  MutationConflictPolicy<String> createConflictPolicy() =>
      const LargeConflictPolicy();
  Future<Result<void, LargeFailure>> synchronizeMutation(
    LargeRemotePort remotePort,
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<void>(null);
  }

  MutationFailurePolicy classifyMutationFailure(LargeFailure failure) =>
      const MutationFailurePolicy.queued();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}

@DartitectFeatureFactory('offline_full_session_3')
final class OfflineFullSession3Factory {
  const OfflineFullSession3Factory();
  LargeLocalPort createLocalPort(SessionStorage storage) => storage;
  Stream<void> watch(LargeLocalPort localPort) => localPort.watch();
  Future<Result<List<String>, LargeFailure>> read(
    LargeLocalPort localPort,
    CancellationSignal cancellation,
  ) => localPort.read(cancellation);
  LargeRemotePort createRemotePort(SessionTransport transport) =>
      LargeRemotePort(transport);
  LargeMapper createMapper() => const LargeMapper();
  SyncDataset<String, int, LargeFailure> createDataset() =>
      SyncDataset<String, int, LargeFailure>(
        key: 'offline_full_session_3',
        synchronize: (context) async => Ok<SyncDatasetOutcome<int>>(
          SyncDatasetOutcome<int>.checkpoint((context.checkpoint ?? 0) + 1),
        ),
      );
  SyncCheckpointStore<String, int> createCheckpointStore(
    SessionStorage storage,
  ) => storage.checkpoints;
  MutationOutboxStore<String, LargeMutation, LargeFailure> createOutboxStore(
    SessionStorage storage,
  ) => storage;
  MutationIdempotencyPolicy<String, LargeMutation> createIdempotencyPolicy() =>
      const LargeIdempotencyPolicy();
  MutationConflictPolicy<String> createConflictPolicy() =>
      const LargeConflictPolicy();
  Future<Result<void, LargeFailure>> synchronizeMutation(
    LargeRemotePort remotePort,
    OutboxOperation<String, LargeMutation> operation,
    CancellationSignal cancellation,
  ) async {
    cancellation.throwIfCancelled();
    return const Ok<void>(null);
  }

  MutationFailurePolicy classifyMutationFailure(LargeFailure failure) =>
      const MutationFailurePolicy.queued();
  LargeRepository createRepository(
    LargeLocalPort localPort,
    LargeRemotePort remotePort,
    LargeMapper mapper,
    PullReactiveSource<List<String>, LargeFailure> localAuthority,
    SyncEngine<String, int, LargeFailure> syncEngine,
  ) => LargeRepository(<Object>[
    localPort,
    remotePort,
    mapper,
    localAuthority,
    syncEngine,
  ]);
  LargeViewModel createViewModel(LargeRepository repository) =>
      LargeViewModel(repository);
}
