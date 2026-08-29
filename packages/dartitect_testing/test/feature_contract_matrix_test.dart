import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test('offline-full runs every typed row with cleanup and census', () async {
    var creates = 0;
    final matrix = FeatureContractMatrix<_Fixture>.offlineFull(
      fixtures: FeatureContractFixtures<_Fixture>(
        create: () {
          creates += 1;
          return _Fixture();
        },
      ),
    );

    final results = await matrix.run();
    expect(results, hasLength(13));
    expect(results.every((result) => result.succeeded), isTrue);
    expect(results.every((result) => result.disposeAttempted), isTrue);
    expect(results.every((result) => result.censusChecked), isTrue);
    expect(creates, results.length);
  });

  test('empty evidence cannot pass a required behavioral row', () async {
    final matrix = FeatureContractMatrix<_EmptyFixture>.online(
      fixtures: FeatureContractFixtures<_EmptyFixture>(
        create: _EmptyFixture.new,
      ),
    );

    final results = await matrix.run();
    expect(
      results
          .where((result) => !result.succeeded)
          .map((result) => result.contract),
      containsAll(<FeatureContract>[
        FeatureContract.onlineRead,
        FeatureContract.expectedFailure,
        FeatureContract.cancellation,
      ]),
    );
  });

  test('residual census fails the row after mandatory disposal', () async {
    final matrix = FeatureContractMatrix<_ResidualFixture>.online(
      fixtures: FeatureContractFixtures<_ResidualFixture>(
        create: _ResidualFixture.new,
      ),
    );

    final results = await matrix.run();
    expect(results.every((result) => !result.succeeded), isTrue);
    expect(results.every((result) => result.disposeAttempted), isTrue);
  });

  test('read-only diagnostics harness rejects mutating methods', () {
    expect(
      const ReadOnlyDiagnosticsContractHarness(<String>{
        'ext.dartitect.capabilities',
        'ext.dartitect.snapshot',
        'ext.dartitect.events',
      }).forbiddenMethods(),
      isEmpty,
    );
    expect(
      const ReadOnlyDiagnosticsContractHarness(<String>{'ext.dartitect.retry'})
          .forbiddenMethods(),
      <String>['ext.dartitect.retry'],
    );
  });
}

class _Fixture implements OfflineFullFeatureContractFixture {
  var _disposed = false;

  FeatureContractObservation _observation(
    FeatureContract contract,
    Set<FeatureContractFact> facts,
  ) => FeatureContractObservation(contract: contract, facts: facts);

  @override
  Future<void> disposeAsync() async => _disposed = true;

  @override
  FeatureResidualCensus get residualCensus => _disposed
      ? const FeatureResidualCensus.empty()
      : FeatureResidualCensus(<String, int>{'fixture': 1});

  @override
  FeatureContractObservation stimulateOnlineRead() =>
      _observation(FeatureContract.onlineRead, <FeatureContractFact>{
        FeatureContractFact.typedSuccess,
        FeatureContractFact.valuePublished,
      });

  @override
  FeatureContractObservation stimulateExpectedFailure() =>
      _observation(FeatureContract.expectedFailure, <FeatureContractFact>{
        FeatureContractFact.typedFailure,
        FeatureContractFact.crashPreserved,
      });

  @override
  FeatureContractObservation stimulateCancellation() =>
      _observation(FeatureContract.cancellation, <FeatureContractFact>{
        FeatureContractFact.cancellationObserved,
        FeatureContractFact.stalePublicationRejected,
      });

  @override
  FeatureContractObservation stimulateLocalAuthority() =>
      _observation(FeatureContract.localAuthority, <FeatureContractFact>{
        FeatureContractFact.localSnapshotObserved,
        FeatureContractFact.remoteCommittedLocally,
      });

  @override
  FeatureContractObservation stimulateRefreshObservation() => _observation(
    FeatureContract.refreshObservation,
    <FeatureContractFact>{FeatureContractFact.exactRevisionObserved},
  );

  @override
  FeatureContractObservation stimulateCacheRestart() =>
      _observation(FeatureContract.cacheRestart, <FeatureContractFact>{
        FeatureContractFact.freshGraphCreated,
        FeatureContractFact.durableStateRecovered,
      });

  @override
  FeatureContractObservation stimulateDurableCheckpoint() =>
      _observation(FeatureContract.durableCheckpoint, <FeatureContractFact>{
        FeatureContractFact.dataCommittedBeforeCheckpoint,
        FeatureContractFact.checkpointPersisted,
      });

  @override
  FeatureContractObservation stimulateFencing() =>
      _observation(FeatureContract.fencing, <FeatureContractFact>{
        FeatureContractFact.staleFencingRejected,
        FeatureContractFact.currentFencingCommitted,
      });

  @override
  FeatureContractObservation stimulateHeadlessExecution() =>
      _observation(FeatureContract.headlessExecution, <FeatureContractFact>{
        FeatureContractFact.freshHeadlessGraph,
        FeatureContractFact.duplicateHeadlessRequestHandled,
        FeatureContractFact.headlessGraphDrained,
      });

  @override
  FeatureContractObservation stimulateAtomicOutbox() =>
      _observation(FeatureContract.atomicOutbox, <FeatureContractFact>{
        FeatureContractFact.domainAndOutboxAtomic,
        FeatureContractFact.atomicRollback,
      });

  @override
  FeatureContractObservation stimulateUncertainDelivery() =>
      _observation(FeatureContract.uncertainDelivery, <FeatureContractFact>{
        FeatureContractFact.uncertaintyPersisted,
        FeatureContractFact.uncertainRetryStopped,
      });

  @override
  FeatureContractObservation stimulateConflictRecovery() =>
      _observation(FeatureContract.conflictRecovery, <FeatureContractFact>{
        FeatureContractFact.conflictPersisted,
        FeatureContractFact.explicitConflictPolicy,
      });
}

class _EmptyFixture implements OnlineFeatureContractFixture {
  var _disposed = false;

  FeatureContractObservation _empty(FeatureContract contract) =>
      FeatureContractObservation(
        contract: contract,
        facts: const <FeatureContractFact>{},
      );

  @override
  Future<void> disposeAsync() async => _disposed = true;

  @override
  FeatureResidualCensus get residualCensus => _disposed
      ? const FeatureResidualCensus.empty()
      : FeatureResidualCensus(<String, int>{'fixture': 1});

  @override
  FeatureContractObservation stimulateCancellation() =>
      _empty(FeatureContract.cancellation);

  @override
  FeatureContractObservation stimulateExpectedFailure() =>
      _empty(FeatureContract.expectedFailure);

  @override
  FeatureContractObservation stimulateOnlineRead() =>
      _empty(FeatureContract.onlineRead);
}

final class _ResidualFixture extends _EmptyFixture {
  @override
  FeatureResidualCensus get residualCensus =>
      FeatureResidualCensus(<String, int>{'timer': 1});
}
