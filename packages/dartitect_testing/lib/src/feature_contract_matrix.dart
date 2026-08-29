import 'dart:async';

import 'package:dartitect/dartitect.dart';

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

/// Closed observable facts accepted as contract evidence.
enum FeatureContractFact {
  /// A typed success was returned.
  typedSuccess,

  /// The successful value reached the declared authority.
  valuePublished,

  /// An expected typed failure was observed.
  typedFailure,

  /// No unexpected crash was translated into an expected failure.
  crashPreserved,

  /// Cancellation reached the admitted operation.
  cancellationObserved,

  /// Cancelled or stale work did not publish.
  stalePublicationRejected,

  /// Presentation read only the local authority.
  localSnapshotObserved,

  /// Remote data committed through the local transaction.
  remoteCommittedLocally,

  /// Refresh waited for the exact local revision.
  exactRevisionObserved,

  /// A fresh graph reopened durable state.
  freshGraphCreated,

  /// Durable state survived restart.
  durableStateRecovered,

  /// Dataset data committed before its checkpoint.
  dataCommittedBeforeCheckpoint,

  /// The checkpoint was persisted durably.
  checkpointPersisted,

  /// A stale fencing token was rejected atomically.
  staleFencingRejected,

  /// The current fencing token committed atomically.
  currentFencingCommitted,

  /// A fresh headless graph was created per admitted execution.
  freshHeadlessGraph,

  /// Duplicate headless input was bounded or deduplicated.
  duplicateHeadlessRequestHandled,

  /// The headless graph drained before close.
  headlessGraphDrained,

  /// Domain mutation and outbox enqueue committed atomically.
  domainAndOutboxAtomic,

  /// Failed local mutation and enqueue rolled back together.
  atomicRollback,

  /// Uncertain delivery was persisted.
  uncertaintyPersisted,

  /// Uncertain delivery was not retried automatically.
  uncertainRetryStopped,

  /// Conflict state was persisted durably.
  conflictPersisted,

  /// An explicit consumer conflict policy decided recovery.
  explicitConflictPolicy,
}

/// Typed, closed evidence returned after one fixture stimulus.
final class FeatureContractObservation {
  /// Creates an immutable observation for [contract].
  FeatureContractObservation({
    required this.contract,
    required Iterable<FeatureContractFact> facts,
  }) : facts = Set<FeatureContractFact>.unmodifiable(facts);

  /// Contract exercised by the stimulus.
  final FeatureContract contract;

  /// Closed observable facts produced by the fixture.
  final Set<FeatureContractFact> facts;
}

/// Framework-neutral residual-resource census captured after disposal.
final class FeatureResidualCensus {
  /// Creates a census from non-negative resource counts.
  FeatureResidualCensus(Map<String, int> counts)
    : counts = Map<String, int>.unmodifiable(counts) {
    for (final entry in this.counts.entries) {
      if (entry.key.trim().isEmpty || entry.value < 0) {
        throw ArgumentError.value(counts, 'counts', 'Invalid census entry.');
      }
    }
  }

  /// A canonical empty census.
  const FeatureResidualCensus.empty() : counts = const <String, int>{};

  /// Static resource category to residual count.
  final Map<String, int> counts;

  /// Whether every owned resource was released.
  bool get isEmpty => counts.values.every((count) => count == 0);

  /// Total residual resources.
  int get total => counts.values.fold(0, (total, count) => total + count);
}

/// Typed online-profile stimulus and observation fixture.
abstract interface class OnlineFeatureContractFixture
    implements AsyncDisposable {
  /// Exercises a successful typed remote read.
  FutureOr<FeatureContractObservation> stimulateOnlineRead();

  /// Exercises an expected typed remote failure.
  FutureOr<FeatureContractObservation> stimulateExpectedFailure();

  /// Exercises cooperative cancellation and its publication fence.
  FutureOr<FeatureContractObservation> stimulateCancellation();

  /// Captures residual resources after [disposeAsync] completes.
  FeatureResidualCensus get residualCensus;
}

/// Additional cache-profile stimuli.
abstract interface class CacheFeatureContractFixture
    implements OnlineFeatureContractFixture {
  /// Exercises presentation backed only by local authority.
  FutureOr<FeatureContractObservation> stimulateLocalAuthority();

  /// Exercises exact-revision observation after refresh.
  FutureOr<FeatureContractObservation> stimulateRefreshObservation();

  /// Exercises a restart with durable cached state.
  FutureOr<FeatureContractObservation> stimulateCacheRestart();
}

/// Additional replica-profile stimuli.
abstract interface class ReplicaFeatureContractFixture
    implements CacheFeatureContractFixture {
  /// Exercises data commit followed by a durable checkpoint.
  FutureOr<FeatureContractObservation> stimulateDurableCheckpoint();

  /// Exercises current and stale fencing tokens.
  FutureOr<FeatureContractObservation> stimulateFencing();

  /// Exercises deduplicated headless work with a fresh graph.
  FutureOr<FeatureContractObservation> stimulateHeadlessExecution();
}

/// Additional offline-full profile stimuli.
abstract interface class OfflineFullFeatureContractFixture
    implements ReplicaFeatureContractFixture {
  /// Exercises atomic domain mutation and outbox enqueue.
  FutureOr<FeatureContractObservation> stimulateAtomicOutbox();

  /// Exercises persisted uncertainty without blind retry.
  FutureOr<FeatureContractObservation> stimulateUncertainDelivery();

  /// Exercises explicit, durable conflict recovery.
  FutureOr<FeatureContractObservation> stimulateConflictRecovery();
}

/// Factory that creates a fresh typed fixture for every matrix row.
final class FeatureContractFixtures<T extends OnlineFeatureContractFixture> {
  /// Creates a fixture factory.
  const FeatureContractFixtures({required this.create});

  /// Creates a fresh fixture.
  final FutureOr<T> Function() create;
}

/// Framework-neutral result of one matrix row.
final class FeatureContractResult {
  /// Creates a row result.
  const FeatureContractResult({
    required this.profile,
    required this.contract,
    required this.fixtureCreated,
    required this.disposeAttempted,
    required this.censusChecked,
    this.observation,
    this.error,
    this.stackTrace,
  });

  /// Matrix profile.
  final FeatureProfile profile;

  /// Stable contract row.
  final FeatureContract contract;

  /// Whether fixture creation completed.
  final bool fixtureCreated;

  /// Whether mandatory fixture cleanup was attempted.
  final bool disposeAttempted;

  /// Whether residual census verification ran after disposal.
  final bool censusChecked;

  /// Typed evidence returned by the stimulus.
  final FeatureContractObservation? observation;

  /// First stimulus, validation, cleanup, or census failure.
  final Object? error;

  /// Original first-failure stack.
  final StackTrace? stackTrace;

  /// Whether the row completed with valid evidence and zero residuals.
  bool get succeeded => error == null;
}

/// Required behavioral matrix for one paved-road feature profile.
final class FeatureContractMatrix<T extends OnlineFeatureContractFixture> {
  /// Creates an online matrix.
  FeatureContractMatrix.online({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureProfile.online, fixtures);

  /// Creates a cache matrix.
  FeatureContractMatrix.cache({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureProfile.cache, fixtures);

  /// Creates a replica matrix.
  FeatureContractMatrix.replica({required FeatureContractFixtures<T> fixtures})
    : this._(FeatureProfile.replica, fixtures);

  /// Creates an offline-full matrix.
  FeatureContractMatrix.offlineFull({
    required FeatureContractFixtures<T> fixtures,
  }) : this._(FeatureProfile.offlineFull, fixtures);

  FeatureContractMatrix._(this.profile, this.fixtures);

  /// Matrix profile from `package:dartitect`.
  final FeatureProfile profile;

  /// Fresh typed fixture factory.
  final FeatureContractFixtures<T> fixtures;

  /// Stable required rows in execution order.
  List<FeatureContract> get requiredContracts =>
      _requirements[profile]!.keys.toList(growable: false);

  /// Executes and verifies every row against a fresh fixture.
  Future<List<FeatureContractResult>> run() async {
    final results = <FeatureContractResult>[];
    for (final contract in requiredContracts) {
      T? fixture;
      var fixtureCreated = false;
      var disposeAttempted = false;
      var censusChecked = false;
      FeatureContractObservation? observation;
      Object? failure;
      StackTrace? failureStack;
      try {
        fixture = await fixtures.create();
        fixtureCreated = true;
        observation = await _stimulate(fixture, contract);
        _verifyObservation(
          observation,
          contract,
          _requirements[profile]![contract]!,
        );
      } catch (error, stackTrace) {
        failure = error;
        failureStack = stackTrace;
      } finally {
        if (fixtureCreated && fixture != null) {
          disposeAttempted = true;
          try {
            await fixture.disposeAsync();
            censusChecked = true;
            final census = fixture.residualCensus;
            if (!census.isEmpty) {
              throw StateError(
                'Feature contract left ${census.total} residual resource(s).',
              );
            }
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
          censusChecked: censusChecked,
          observation: observation,
          error: failure,
          stackTrace: failureStack,
        ),
      );
    }
    return List<FeatureContractResult>.unmodifiable(results);
  }

  static FutureOr<FeatureContractObservation> _stimulate(
    OnlineFeatureContractFixture fixture,
    FeatureContract contract,
  ) => switch (contract) {
    FeatureContract.onlineRead => fixture.stimulateOnlineRead(),
    FeatureContract.expectedFailure => fixture.stimulateExpectedFailure(),
    FeatureContract.cancellation => fixture.stimulateCancellation(),
    FeatureContract.zeroResiduals => FeatureContractObservation(
      contract: FeatureContract.zeroResiduals,
      facts: const <FeatureContractFact>{},
    ),
    FeatureContract.localAuthority =>
      (fixture as CacheFeatureContractFixture).stimulateLocalAuthority(),
    FeatureContract.refreshObservation =>
      (fixture as CacheFeatureContractFixture).stimulateRefreshObservation(),
    FeatureContract.cacheRestart =>
      (fixture as CacheFeatureContractFixture).stimulateCacheRestart(),
    FeatureContract.durableCheckpoint =>
      (fixture as ReplicaFeatureContractFixture).stimulateDurableCheckpoint(),
    FeatureContract.fencing =>
      (fixture as ReplicaFeatureContractFixture).stimulateFencing(),
    FeatureContract.headlessExecution =>
      (fixture as ReplicaFeatureContractFixture).stimulateHeadlessExecution(),
    FeatureContract.atomicOutbox =>
      (fixture as OfflineFullFeatureContractFixture).stimulateAtomicOutbox(),
    FeatureContract.uncertainDelivery =>
      (fixture as OfflineFullFeatureContractFixture)
          .stimulateUncertainDelivery(),
    FeatureContract.conflictRecovery =>
      (fixture as OfflineFullFeatureContractFixture)
          .stimulateConflictRecovery(),
  };

  static void _verifyObservation(
    FeatureContractObservation observation,
    FeatureContract contract,
    Set<FeatureContractFact> required,
  ) {
    if (observation.contract != contract ||
        !observation.facts.containsAll(required)) {
      throw StateError(
        'Feature contract evidence is incomplete or mismatched.',
      );
    }
  }
}

const Map<FeatureProfile, Map<FeatureContract, Set<FeatureContractFact>>>
_requirements =
    <FeatureProfile, Map<FeatureContract, Set<FeatureContractFact>>>{
      FeatureProfile.online: <FeatureContract, Set<FeatureContractFact>>{
        FeatureContract.onlineRead: <FeatureContractFact>{
          FeatureContractFact.typedSuccess,
          FeatureContractFact.valuePublished,
        },
        FeatureContract.expectedFailure: <FeatureContractFact>{
          FeatureContractFact.typedFailure,
          FeatureContractFact.crashPreserved,
        },
        FeatureContract.cancellation: <FeatureContractFact>{
          FeatureContractFact.cancellationObserved,
          FeatureContractFact.stalePublicationRejected,
        },
        FeatureContract.zeroResiduals: <FeatureContractFact>{},
      },
      FeatureProfile.cache: <FeatureContract, Set<FeatureContractFact>>{
        FeatureContract.onlineRead: <FeatureContractFact>{
          FeatureContractFact.typedSuccess,
          FeatureContractFact.valuePublished,
        },
        FeatureContract.expectedFailure: <FeatureContractFact>{
          FeatureContractFact.typedFailure,
          FeatureContractFact.crashPreserved,
        },
        FeatureContract.cancellation: <FeatureContractFact>{
          FeatureContractFact.cancellationObserved,
          FeatureContractFact.stalePublicationRejected,
        },
        FeatureContract.localAuthority: <FeatureContractFact>{
          FeatureContractFact.localSnapshotObserved,
          FeatureContractFact.remoteCommittedLocally,
        },
        FeatureContract.refreshObservation: <FeatureContractFact>{
          FeatureContractFact.exactRevisionObserved,
        },
        FeatureContract.cacheRestart: <FeatureContractFact>{
          FeatureContractFact.freshGraphCreated,
          FeatureContractFact.durableStateRecovered,
        },
        FeatureContract.zeroResiduals: <FeatureContractFact>{},
      },
      FeatureProfile.replica: <FeatureContract, Set<FeatureContractFact>>{
        FeatureContract.onlineRead: <FeatureContractFact>{
          FeatureContractFact.typedSuccess,
          FeatureContractFact.valuePublished,
        },
        FeatureContract.expectedFailure: <FeatureContractFact>{
          FeatureContractFact.typedFailure,
          FeatureContractFact.crashPreserved,
        },
        FeatureContract.cancellation: <FeatureContractFact>{
          FeatureContractFact.cancellationObserved,
          FeatureContractFact.stalePublicationRejected,
        },
        FeatureContract.localAuthority: <FeatureContractFact>{
          FeatureContractFact.localSnapshotObserved,
          FeatureContractFact.remoteCommittedLocally,
        },
        FeatureContract.refreshObservation: <FeatureContractFact>{
          FeatureContractFact.exactRevisionObserved,
        },
        FeatureContract.cacheRestart: <FeatureContractFact>{
          FeatureContractFact.freshGraphCreated,
          FeatureContractFact.durableStateRecovered,
        },
        FeatureContract.durableCheckpoint: <FeatureContractFact>{
          FeatureContractFact.dataCommittedBeforeCheckpoint,
          FeatureContractFact.checkpointPersisted,
        },
        FeatureContract.fencing: <FeatureContractFact>{
          FeatureContractFact.staleFencingRejected,
          FeatureContractFact.currentFencingCommitted,
        },
        FeatureContract.headlessExecution: <FeatureContractFact>{
          FeatureContractFact.freshHeadlessGraph,
          FeatureContractFact.duplicateHeadlessRequestHandled,
          FeatureContractFact.headlessGraphDrained,
        },
        FeatureContract.zeroResiduals: <FeatureContractFact>{},
      },
      FeatureProfile.offlineFull: <FeatureContract, Set<FeatureContractFact>>{
        FeatureContract.onlineRead: <FeatureContractFact>{
          FeatureContractFact.typedSuccess,
          FeatureContractFact.valuePublished,
        },
        FeatureContract.expectedFailure: <FeatureContractFact>{
          FeatureContractFact.typedFailure,
          FeatureContractFact.crashPreserved,
        },
        FeatureContract.cancellation: <FeatureContractFact>{
          FeatureContractFact.cancellationObserved,
          FeatureContractFact.stalePublicationRejected,
        },
        FeatureContract.localAuthority: <FeatureContractFact>{
          FeatureContractFact.localSnapshotObserved,
          FeatureContractFact.remoteCommittedLocally,
        },
        FeatureContract.refreshObservation: <FeatureContractFact>{
          FeatureContractFact.exactRevisionObserved,
        },
        FeatureContract.cacheRestart: <FeatureContractFact>{
          FeatureContractFact.freshGraphCreated,
          FeatureContractFact.durableStateRecovered,
        },
        FeatureContract.durableCheckpoint: <FeatureContractFact>{
          FeatureContractFact.dataCommittedBeforeCheckpoint,
          FeatureContractFact.checkpointPersisted,
        },
        FeatureContract.fencing: <FeatureContractFact>{
          FeatureContractFact.staleFencingRejected,
          FeatureContractFact.currentFencingCommitted,
        },
        FeatureContract.headlessExecution: <FeatureContractFact>{
          FeatureContractFact.freshHeadlessGraph,
          FeatureContractFact.duplicateHeadlessRequestHandled,
          FeatureContractFact.headlessGraphDrained,
        },
        FeatureContract.atomicOutbox: <FeatureContractFact>{
          FeatureContractFact.domainAndOutboxAtomic,
          FeatureContractFact.atomicRollback,
        },
        FeatureContract.uncertainDelivery: <FeatureContractFact>{
          FeatureContractFact.uncertaintyPersisted,
          FeatureContractFact.uncertainRetryStopped,
        },
        FeatureContract.conflictRecovery: <FeatureContractFact>{
          FeatureContractFact.conflictPersisted,
          FeatureContractFact.explicitConflictPolicy,
        },
        FeatureContract.zeroResiduals: <FeatureContractFact>{},
      },
    };
