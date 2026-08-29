import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'offline-full derives every row from observed runtime evidence',
    () async {
      var creates = 0;
      final matrix = FeatureContractMatrix<_ObservedDriver>.offlineFull(
        fixtures: FeatureContractFixtures<_ObservedDriver>(
          create: (harness) {
            creates += 1;
            return _ObservedDriver(harness);
          },
        ),
      );

      final results = await matrix.run();

      expect(results, hasLength(15));
      expect(results.every((result) => result.succeeded), isTrue);
      expect(results.every((result) => result.disposeAttempted), isTrue);
      expect(results.every((result) => result.censusChecked), isTrue);
      expect(
        creates,
        results.length + 1,
        reason: 'restart creates a second graph',
      );
      final crash = results.singleWhere(
        (result) => result.contract == FeatureContract.unexpectedCrash,
      );
      expect(
        crash.observation!.facts,
        contains(FeatureContractFact.crashPreserved),
      );
      final checkpoint = results.singleWhere(
        (result) => result.contract == FeatureContract.durableCheckpoint,
      );
      final applied = checkpoint.observation!.events.singleWhere(
        (event) => event.kind == FeatureRuntimeEventKind.datasetApplied,
      );
      final persisted = checkpoint.observation!.events.singleWhere(
        (event) => event.kind == FeatureRuntimeEventKind.checkpointWritten,
      );
      expect(applied.sequence, lessThan(persisted.sequence));
    },
  );

  test('a driver cannot pass by returning self-reported facts', () async {
    final matrix = FeatureContractMatrix<_IncompleteDriver>.online(
      fixtures: FeatureContractFixtures<_IncompleteDriver>(
        create: _IncompleteDriver.new,
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
        FeatureContract.unexpectedCrash,
        FeatureContract.cancellation,
        FeatureContract.concurrency,
        FeatureContract.restart,
      ]),
    );
    expect(
      results
          .where((result) => result.observation != null)
          .expand((result) => result.observation!.facts),
      isEmpty,
    );
  });

  test('matrix-owned ResourceCensus fails after mandatory disposal', () async {
    final matrix = FeatureContractMatrix<_LeakingDriver>.online(
      fixtures: FeatureContractFixtures<_LeakingDriver>(
        create: _LeakingDriver.new,
      ),
    );

    final results = await matrix.run();

    expect(results.every((result) => !result.succeeded), isTrue);
    expect(results.every((result) => result.disposeAttempted), isTrue);
    expect(results.every((result) => result.censusChecked), isTrue);
    expect(
      results
          .singleWhere(
            (result) => result.contract == FeatureContract.zeroResiduals,
          )
          .error
          .toString(),
      contains('census'),
    );
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

final class _ObservedDriver implements OfflineFullFeatureContractDriver {
  _ObservedDriver(this.harness);

  final FeatureContractHarness harness;
  var _disposed = false;

  @override
  Future<void> stimulate(
    FeatureContract contract,
    CancellationSignal cancellation,
  ) async {
    if (_disposed) throw StateError('Driver is disposed.');
    switch (contract) {
      case FeatureContract.onlineRead:
        harness.store.remoteSucceeded();
        harness.store.publish();
      case FeatureContract.expectedFailure:
        if (!harness.faults.takeExpectedFailure()) {
          throw StateError('Expected failure was not injected.');
        }
        harness.store.expectedFailure();
      case FeatureContract.unexpectedCrash:
        harness.faults.throwIfCrashArmed();
      case FeatureContract.cancellation:
        await cancellation.whenCancelled;
        cancellation.throwIfCancelled();
      case FeatureContract.concurrency:
        final operation = harness.store.beginOperation();
        try {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        } finally {
          operation.dispose();
        }
      case FeatureContract.restart:
        if (harness.store.hasDurableState) {
          harness.store.readDurableState();
        } else {
          harness.store.writeDurableState();
        }
      case FeatureContract.zeroResiduals:
        return;
      case FeatureContract.localAuthority:
        harness.store.readLocalSnapshot();
        harness.store.commitRemoteLocally();
      case FeatureContract.refreshObservation:
        final revision = harness.store.commitRemoteLocally();
        harness.store.observeRevision(revision);
      case FeatureContract.durableCheckpoint:
        final revision = harness.store.applyDataset();
        harness.store.writeCheckpoint(revision);
      case FeatureContract.fencing:
        harness.store.commitCurrentFence(2);
        harness.store.rejectStaleFence(1);
      case FeatureContract.headlessExecution:
        final graph = harness.openHeadlessGraph();
        try {
          harness.acceptHeadless('request-1', graph.graphId);
          harness.duplicateHeadless('request-1', graph.graphId);
          harness.completeHeadless('request-1', graph.graphId);
        } finally {
          graph.dispose();
        }
      case FeatureContract.atomicOutbox:
        harness.store.commitDomainAndOutbox('operation-1');
        harness.store.rollbackDomainAndOutbox();
      case FeatureContract.uncertainDelivery:
        harness.store.attemptDelivery('operation-1');
        harness.store.persistUncertainty('operation-1');
      case FeatureContract.conflictRecovery:
        harness.store.persistConflict('operation-1');
        harness.store.resolveConflict('operation-1');
    }
  }

  @override
  Future<void> disposeAsync() async => _disposed = true;
}

class _IncompleteDriver implements OnlineFeatureContractDriver {
  _IncompleteDriver(this.harness);

  final FeatureContractHarness harness;

  @override
  Future<void> stimulate(
    FeatureContract contract,
    CancellationSignal cancellation,
  ) async {}

  @override
  Future<void> disposeAsync() async {}
}

final class _LeakingDriver extends _IncompleteDriver {
  _LeakingDriver(super.harness) : _leak = harness.resources.acquire('timer');

  // Deliberately not released: the matrix-owned census must catch it.
  final CensusLease _leak;

  @override
  Future<void> disposeAsync() async {
    // Keep the field reachable to prove this is an intentional leak fixture.
    if (_leak.isDisposed) throw StateError('Leak was unexpectedly released.');
  }
}
