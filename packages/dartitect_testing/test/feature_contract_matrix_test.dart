import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'offline-full matrix runs every required contract on a fresh fixture',
    () async {
      var creates = 0;
      var disposals = 0;
      final callbacks = <FeatureContract, Future<void> Function(_Fixture)>{
        for (final contract in FeatureContract.values)
          contract: (fixture) async {
            fixture.calls += 1;
            expect(fixture.calls, 1);
          },
      };
      final matrix = FeatureContractMatrix<_Fixture>.offlineFull(
        fixtures: FeatureContractFixtures<_Fixture>(
          create: () {
            creates += 1;
            return _Fixture();
          },
          contracts: callbacks,
          dispose: (_) => disposals += 1,
        ),
      );

      final results = await matrix.run();
      expect(results, hasLength(13));
      expect(results.every((result) => result.succeeded), isTrue);
      expect(results.every((result) => result.disposeAttempted), isTrue);
      expect(creates, results.length);
      expect(disposals, results.length);
    },
  );

  test('matrix fails closed when a required callback is absent', () {
    expect(
      () => FeatureContractMatrix<_Fixture>.online(
        fixtures: FeatureContractFixtures<_Fixture>(
          create: _Fixture.new,
          contracts: const <FeatureContract, Future<void> Function(_Fixture)>{},
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'matrix captures assertion and cleanup failures independently',
    () async {
      final callbacks = <FeatureContract, Future<void> Function(_Fixture)>{
        for (final contract in <FeatureContract>[
          FeatureContract.onlineRead,
          FeatureContract.expectedFailure,
          FeatureContract.cancellation,
          FeatureContract.zeroResiduals,
        ])
          contract: (_) async {
            if (contract == FeatureContract.expectedFailure) {
              throw StateError('contract failed');
            }
          },
      };
      final matrix = FeatureContractMatrix<_Fixture>.online(
        fixtures: FeatureContractFixtures<_Fixture>(
          create: _Fixture.new,
          contracts: callbacks,
          dispose: (_) {},
        ),
      );

      final results = await matrix.run();
      expect(results.where((result) => !result.succeeded), hasLength(1));
      expect(
        results.singleWhere((result) => !result.succeeded).contract,
        FeatureContract.expectedFailure,
      );
    },
  );

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

final class _Fixture {
  var calls = 0;
}
