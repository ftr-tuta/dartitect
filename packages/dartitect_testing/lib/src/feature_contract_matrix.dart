import 'dart:async';

/// Public feature contract profiles.
enum FeatureContractProfile {
  /// Remote authority without durable local persistence.
  online,

  /// Remote authority with a durable local cache.
  cache,

  /// Locally queryable synchronized replica.
  replica,

  /// Replica plus durable offline mutation delivery.
  offlineFull,
}

/// Stable behavioral cases required by one or more feature profiles.
enum FeatureContract {
  /// Successful typed remote read.
  onlineRead,

  /// Expected remote failure remains distinct from a crash.
  expectedFailure,

  /// Cooperative cancellation stops publication.
  cancellation,

  /// Teardown leaves no owned resources.
  zeroResiduals,

  /// Local persistence is the query authority.
  localAuthority,

  /// Remote refresh completes only after local observation.
  refreshObservation,

  /// Restart preserves durable cached state.
  cacheRestart,

  /// Checkpoint advances only after durable application.
  durableCheckpoint,

  /// Stale fencing generations cannot commit.
  fencing,

  /// Headless execution deduplicates and drains its graph.
  headlessExecution,

  /// Local mutation and outbox enqueue are atomic.
  atomicOutbox,

  /// Uncertain delivery is never retried blindly.
  uncertainDelivery,

  /// Conflict policy is explicit and durable.
  conflictRecovery,
}

/// Consumer fixture factory and typed contract callbacks.
final class FeatureContractFixtures<T extends Object> {
  /// Creates a fixture definition.
  FeatureContractFixtures({
    required this.create,
    required Map<FeatureContract, FutureOr<void> Function(T fixture)> contracts,
    this.dispose,
  }) : contracts =
           Map<FeatureContract, FutureOr<void> Function(T)>.unmodifiable(
             contracts,
           );

  /// Creates a fresh fixture for every matrix row.
  final FutureOr<T> Function() create;

  /// Consumer assertions keyed by stable contract.
  final Map<FeatureContract, FutureOr<void> Function(T fixture)> contracts;

  /// Releases each successfully created fixture.
  final FutureOr<void> Function(T fixture)? dispose;
}

/// Framework-neutral result of one matrix row.
final class FeatureContractResult {
  /// Creates a row result.
  const FeatureContractResult({
    required this.profile,
    required this.contract,
    required this.fixtureCreated,
    required this.disposeAttempted,
    this.error,
    this.stackTrace,
  });

  /// Matrix profile.
  final FeatureContractProfile profile;

  /// Stable contract row.
  final FeatureContract contract;

  /// Whether fixture creation completed.
  final bool fixtureCreated;

  /// Whether fixture cleanup was attempted.
  final bool disposeAttempted;

  /// First factory, assertion, or cleanup failure.
  final Object? error;

  /// Original first-failure stack.
  final StackTrace? stackTrace;

  /// Whether the row completed without failure.
  bool get succeeded => error == null;
}

/// Required behavioral matrix for one paved-road feature profile.
final class FeatureContractMatrix<T extends Object> {
  /// Creates an online matrix.
  FeatureContractMatrix.online({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureContractProfile.online, fixtures);

  /// Creates a cache matrix.
  FeatureContractMatrix.cache({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureContractProfile.cache, fixtures);

  /// Creates a replica matrix.
  FeatureContractMatrix.replica({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureContractProfile.replica, fixtures);

  /// Creates an offline-full matrix.
  FeatureContractMatrix.offlineFull({
    required FeatureContractFixtures<T> fixtures,
  }) : this._(FeatureContractProfile.offlineFull, fixtures);

  FeatureContractMatrix._(this.profile, this.fixtures) {
    final missing = requiredContracts
        .where((contract) => !fixtures.contracts.containsKey(contract))
        .toList();
    if (missing.isNotEmpty) {
      throw ArgumentError.value(
        missing.map((contract) => contract.name).toList(),
        'fixtures',
        'Missing required profile contracts.',
      );
    }
  }

  /// Matrix profile.
  final FeatureContractProfile profile;

  /// Consumer fixtures and assertions.
  final FeatureContractFixtures<T> fixtures;

  /// Stable required rows in execution order.
  List<FeatureContract> get requiredContracts => switch (profile) {
    FeatureContractProfile.online => const <FeatureContract>[
      FeatureContract.onlineRead,
      FeatureContract.expectedFailure,
      FeatureContract.cancellation,
      FeatureContract.zeroResiduals,
    ],
    FeatureContractProfile.cache => const <FeatureContract>[
      FeatureContract.onlineRead,
      FeatureContract.expectedFailure,
      FeatureContract.cancellation,
      FeatureContract.localAuthority,
      FeatureContract.refreshObservation,
      FeatureContract.cacheRestart,
      FeatureContract.zeroResiduals,
    ],
    FeatureContractProfile.replica => const <FeatureContract>[
      FeatureContract.onlineRead,
      FeatureContract.expectedFailure,
      FeatureContract.cancellation,
      FeatureContract.localAuthority,
      FeatureContract.refreshObservation,
      FeatureContract.cacheRestart,
      FeatureContract.durableCheckpoint,
      FeatureContract.fencing,
      FeatureContract.headlessExecution,
      FeatureContract.zeroResiduals,
    ],
    FeatureContractProfile.offlineFull => const <FeatureContract>[
      FeatureContract.onlineRead,
      FeatureContract.expectedFailure,
      FeatureContract.cancellation,
      FeatureContract.localAuthority,
      FeatureContract.refreshObservation,
      FeatureContract.cacheRestart,
      FeatureContract.durableCheckpoint,
      FeatureContract.fencing,
      FeatureContract.headlessExecution,
      FeatureContract.atomicOutbox,
      FeatureContract.uncertainDelivery,
      FeatureContract.conflictRecovery,
      FeatureContract.zeroResiduals,
    ],
  };

  /// Executes every required row against a fresh fixture.
  Future<List<FeatureContractResult>> run() async {
    final results = <FeatureContractResult>[];
    for (final contract in requiredContracts) {
      T? fixture;
      var fixtureCreated = false;
      var disposeAttempted = false;
      Object? failure;
      StackTrace? failureStack;
      try {
        fixture = await fixtures.create();
        fixtureCreated = true;
        await fixtures.contracts[contract]!(fixture);
      } catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
      } finally {
        final release = fixtures.dispose;
        if (fixtureCreated && fixture != null && release != null) {
          disposeAttempted = true;
          try {
            await release(fixture);
          } catch (error, stackTrace) {
            failure ??= error;
            failureStack ??= stackTrace;
          }
        }
      }
      results.add(
        FeatureContractResult(
          profile: profile,
          contract: contract,
          fixtureCreated: fixtureCreated,
          disposeAttempted: disposeAttempted,
          error: failure,
          stackTrace: failureStack,
        ),
      );
    }
    return List<FeatureContractResult>.unmodifiable(results);
  }
}
