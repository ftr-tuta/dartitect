import 'package:dartitect/dartitect.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:large_consumer_canary/all_features.dart';
import 'package:large_consumer_canary/contracts/app_api.contracts.dartitect.g.dart';
import 'package:large_consumer_canary/composition/application_module.wiring.dartitect.g.dart';
import 'package:large_consumer_canary/composition/session_module.wiring.dartitect.g.dart';
import 'package:large_consumer_canary/large_factories.dart';

void main() {
  test('30 concrete feature graphs open and close with exact scopes', () async {
    expect(largeFeatureNames, hasLength(30));
    final census = ResourceCensus();
    final appLease = census.acquire('application');
    final coordinator = ApplicationModule.create();
    final attempt = await coordinator.run();
    final application = (attempt as BootstrapSucceeded<ApplicationGraph>).graph;
    expect(LargeCensus.appStorageOpens, 1);
    expect(LargeCensus.appTransportOpens, 1);
    final session = await ResourceTransaction.create<SessionGraph>(
      (transaction) => SessionModule.create(application.root, transaction),
    );
    final sessionLease = census.acquire('session');
    expect(LargeCensus.sessionStorageOpens, 1);
    expect(LargeCensus.sessionTransportOpens, 1);
    expect(LargeCensus.sessionCreates, 1);
    final localapplication1 =
        await ResourceTransaction.create<LocalApplication1Runtime>(
          (transaction) => LocalApplication1Runtime.create(
            application.root,
            const LocalApplication1Factory(),
            transaction,
          ),
        );
    expect(LocalApplication1FeatureWiring.profile, 'local');
    await localapplication1.disposeAsync();
    final localapplication2 =
        await ResourceTransaction.create<LocalApplication2Runtime>(
          (transaction) => LocalApplication2Runtime.create(
            application.root,
            const LocalApplication2Factory(),
            transaction,
          ),
        );
    expect(LocalApplication2FeatureWiring.profile, 'local');
    await localapplication2.disposeAsync();
    final localapplication3 =
        await ResourceTransaction.create<LocalApplication3Runtime>(
          (transaction) => LocalApplication3Runtime.create(
            application.root,
            const LocalApplication3Factory(),
            transaction,
          ),
        );
    expect(LocalApplication3FeatureWiring.profile, 'local');
    await localapplication3.disposeAsync();
    final localsession1 =
        await ResourceTransaction.create<LocalSession1Runtime>(
          (transaction) => LocalSession1Runtime.create(
            session.root,
            const LocalSession1Factory(),
            transaction,
          ),
        );
    expect(LocalSession1FeatureWiring.profile, 'local');
    await localsession1.disposeAsync();
    final localsession2 =
        await ResourceTransaction.create<LocalSession2Runtime>(
          (transaction) => LocalSession2Runtime.create(
            session.root,
            const LocalSession2Factory(),
            transaction,
          ),
        );
    expect(LocalSession2FeatureWiring.profile, 'local');
    await localsession2.disposeAsync();
    final localsession3 =
        await ResourceTransaction.create<LocalSession3Runtime>(
          (transaction) => LocalSession3Runtime.create(
            session.root,
            const LocalSession3Factory(),
            transaction,
          ),
        );
    expect(LocalSession3FeatureWiring.profile, 'local');
    await localsession3.disposeAsync();
    final onlineapplication1 =
        await ResourceTransaction.create<OnlineApplication1Runtime>(
          (transaction) => OnlineApplication1Runtime.create(
            application.root,
            const OnlineApplication1Factory(),
            transaction,
          ),
        );
    expect(OnlineApplication1FeatureWiring.profile, 'online');
    expect(onlineapplication1.root.appApiGetProbe, isA<GetProbeOperation>());
    await onlineapplication1.disposeAsync();
    final onlineapplication2 =
        await ResourceTransaction.create<OnlineApplication2Runtime>(
          (transaction) => OnlineApplication2Runtime.create(
            application.root,
            const OnlineApplication2Factory(),
            transaction,
          ),
        );
    expect(OnlineApplication2FeatureWiring.profile, 'online');
    await onlineapplication2.disposeAsync();
    final onlineapplication3 =
        await ResourceTransaction.create<OnlineApplication3Runtime>(
          (transaction) => OnlineApplication3Runtime.create(
            application.root,
            const OnlineApplication3Factory(),
            transaction,
          ),
        );
    expect(OnlineApplication3FeatureWiring.profile, 'online');
    await onlineapplication3.disposeAsync();
    final onlinesession1 =
        await ResourceTransaction.create<OnlineSession1Runtime>(
          (transaction) => OnlineSession1Runtime.create(
            session.root,
            const OnlineSession1Factory(),
            transaction,
          ),
        );
    expect(OnlineSession1FeatureWiring.profile, 'online');
    await onlinesession1.disposeAsync();
    final onlinesession2 =
        await ResourceTransaction.create<OnlineSession2Runtime>(
          (transaction) => OnlineSession2Runtime.create(
            session.root,
            const OnlineSession2Factory(),
            transaction,
          ),
        );
    expect(OnlineSession2FeatureWiring.profile, 'online');
    await onlinesession2.disposeAsync();
    final onlinesession3 =
        await ResourceTransaction.create<OnlineSession3Runtime>(
          (transaction) => OnlineSession3Runtime.create(
            session.root,
            const OnlineSession3Factory(),
            transaction,
          ),
        );
    expect(OnlineSession3FeatureWiring.profile, 'online');
    await onlinesession3.disposeAsync();
    final cacheapplication1 =
        await ResourceTransaction.create<CacheApplication1Runtime>(
          (transaction) => CacheApplication1Runtime.create(
            application.root,
            const CacheApplication1Factory(),
            transaction,
          ),
        );
    expect(CacheApplication1FeatureWiring.profile, 'cache');
    await cacheapplication1.disposeAsync();
    final cacheapplication2 =
        await ResourceTransaction.create<CacheApplication2Runtime>(
          (transaction) => CacheApplication2Runtime.create(
            application.root,
            const CacheApplication2Factory(),
            transaction,
          ),
        );
    expect(CacheApplication2FeatureWiring.profile, 'cache');
    await cacheapplication2.disposeAsync();
    final cacheapplication3 =
        await ResourceTransaction.create<CacheApplication3Runtime>(
          (transaction) => CacheApplication3Runtime.create(
            application.root,
            const CacheApplication3Factory(),
            transaction,
          ),
        );
    expect(CacheApplication3FeatureWiring.profile, 'cache');
    await cacheapplication3.disposeAsync();
    final cachesession1 =
        await ResourceTransaction.create<CacheSession1Runtime>(
          (transaction) => CacheSession1Runtime.create(
            session.root,
            const CacheSession1Factory(),
            transaction,
          ),
        );
    expect(CacheSession1FeatureWiring.profile, 'cache');
    await cachesession1.disposeAsync();
    final cachesession2 =
        await ResourceTransaction.create<CacheSession2Runtime>(
          (transaction) => CacheSession2Runtime.create(
            session.root,
            const CacheSession2Factory(),
            transaction,
          ),
        );
    expect(CacheSession2FeatureWiring.profile, 'cache');
    await cachesession2.disposeAsync();
    final cachesession3 =
        await ResourceTransaction.create<CacheSession3Runtime>(
          (transaction) => CacheSession3Runtime.create(
            session.root,
            const CacheSession3Factory(),
            transaction,
          ),
        );
    expect(CacheSession3FeatureWiring.profile, 'cache');
    await cachesession3.disposeAsync();
    final replicaapplication1 =
        await ResourceTransaction.create<ReplicaApplication1Runtime>(
          (transaction) => ReplicaApplication1Runtime.create(
            application.root,
            const ReplicaApplication1Factory(),
            transaction,
          ),
        );
    expect(ReplicaApplication1FeatureWiring.profile, 'replica');
    await replicaapplication1.disposeAsync();
    final replicaapplication2 =
        await ResourceTransaction.create<ReplicaApplication2Runtime>(
          (transaction) => ReplicaApplication2Runtime.create(
            application.root,
            const ReplicaApplication2Factory(),
            transaction,
          ),
        );
    expect(ReplicaApplication2FeatureWiring.profile, 'replica');
    await replicaapplication2.disposeAsync();
    final replicaapplication3 =
        await ResourceTransaction.create<ReplicaApplication3Runtime>(
          (transaction) => ReplicaApplication3Runtime.create(
            application.root,
            const ReplicaApplication3Factory(),
            transaction,
          ),
        );
    expect(ReplicaApplication3FeatureWiring.profile, 'replica');
    await replicaapplication3.disposeAsync();
    final replicasession1 =
        await ResourceTransaction.create<ReplicaSession1Runtime>(
          (transaction) => ReplicaSession1Runtime.create(
            session.root,
            const ReplicaSession1Factory(),
            transaction,
          ),
        );
    expect(ReplicaSession1FeatureWiring.profile, 'replica');
    await replicasession1.disposeAsync();
    final replicasession2 =
        await ResourceTransaction.create<ReplicaSession2Runtime>(
          (transaction) => ReplicaSession2Runtime.create(
            session.root,
            const ReplicaSession2Factory(),
            transaction,
          ),
        );
    expect(ReplicaSession2FeatureWiring.profile, 'replica');
    await replicasession2.disposeAsync();
    final replicasession3 =
        await ResourceTransaction.create<ReplicaSession3Runtime>(
          (transaction) => ReplicaSession3Runtime.create(
            session.root,
            const ReplicaSession3Factory(),
            transaction,
          ),
        );
    expect(ReplicaSession3FeatureWiring.profile, 'replica');
    await replicasession3.disposeAsync();
    final offlinefullapplication1 =
        await ResourceTransaction.create<OfflineFullApplication1Runtime>(
          (transaction) => OfflineFullApplication1Runtime.create(
            application.root,
            const OfflineFullApplication1Factory(),
            transaction,
          ),
        );
    expect(OfflineFullApplication1FeatureWiring.profile, 'offline-full');
    await offlinefullapplication1.disposeAsync();
    final offlinefullapplication2 =
        await ResourceTransaction.create<OfflineFullApplication2Runtime>(
          (transaction) => OfflineFullApplication2Runtime.create(
            application.root,
            const OfflineFullApplication2Factory(),
            transaction,
          ),
        );
    expect(OfflineFullApplication2FeatureWiring.profile, 'offline-full');
    await offlinefullapplication2.disposeAsync();
    final offlinefullapplication3 =
        await ResourceTransaction.create<OfflineFullApplication3Runtime>(
          (transaction) => OfflineFullApplication3Runtime.create(
            application.root,
            const OfflineFullApplication3Factory(),
            transaction,
          ),
        );
    expect(OfflineFullApplication3FeatureWiring.profile, 'offline-full');
    await offlinefullapplication3.disposeAsync();
    final offlinefullsession1 =
        await ResourceTransaction.create<OfflineFullSession1Runtime>(
          (transaction) => OfflineFullSession1Runtime.create(
            session.root,
            const OfflineFullSession1Factory(),
            transaction,
          ),
        );
    expect(OfflineFullSession1FeatureWiring.profile, 'offline-full');
    await offlinefullsession1.disposeAsync();
    final offlinefullsession2 =
        await ResourceTransaction.create<OfflineFullSession2Runtime>(
          (transaction) => OfflineFullSession2Runtime.create(
            session.root,
            const OfflineFullSession2Factory(),
            transaction,
          ),
        );
    expect(OfflineFullSession2FeatureWiring.profile, 'offline-full');
    await offlinefullsession2.disposeAsync();
    final offlinefullsession3 =
        await ResourceTransaction.create<OfflineFullSession3Runtime>(
          (transaction) => OfflineFullSession3Runtime.create(
            session.root,
            const OfflineFullSession3Factory(),
            transaction,
          ),
        );
    expect(OfflineFullSession3FeatureWiring.profile, 'offline-full');
    await offlinefullsession3.disposeAsync();
    await session.disposeAsync();
    sessionLease.dispose();
    expect(session.root.sessionStorage.disposed, isTrue);
    expect(session.root.sessionApi.disposed, isTrue);
    final replacement = await ResourceTransaction.create<SessionGraph>(
      (transaction) => SessionModule.create(application.root, transaction),
    );
    expect(LargeCensus.sessionCreates, 2);
    await replacement.disposeAsync();
    expect(application.root.appStorage.disposed, isFalse);
    await application.disposeAsync();
    appLease.dispose();
    await coordinator.disposeAsync();
    expect(LargeCensus.liveContexts, 0);
    census.verifyZero();
  });
}
