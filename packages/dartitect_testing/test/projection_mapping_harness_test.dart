import 'package:dartitect_modeling/dartitect_modeling.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test('projection harness reports deterministic selector evidence', () {
    const harness = ProjectionContractHarness<_Source, ({String id})>(
      selector: _select,
    );

    final run = harness.run(const _Source('one'));

    expect(run.first.id, 'one');
    expect(run.second, run.first);
    expect(run.deterministic, isTrue);
  });

  test('mapper harness runs a successful bidirectional round-trip', () {
    const harness = MapperContractHarness<_Source, _Target>(
      mapper: _BidirectionalMapper(),
    );

    final run = harness.run(const _Source('one'));

    expect(run.forward, const Ok<_Target>(_Target('one')));
    expect(run.mapperIsBidirectional, isTrue);
    expect(run.reverse, const Ok<_Source>(_Source('one')));
    expect(run.roundTripEquivalent, isTrue);
  });

  test('mapper harness leaves reverse evidence absent for one-way mapping', () {
    const harness = MapperContractHarness<_Source, _Target>(
      mapper: _OneWayMapper(),
    );

    final run = harness.run(const _Source('one'));

    expect(run.mapperIsBidirectional, isFalse);
    expect(run.reverse, isNull);
    expect(run.roundTripEquivalent, isNull);
  });
}

final class _Source {
  const _Source(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is _Source && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class _Target {
  const _Target(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is _Target && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

({String id}) _select(_Source source) => (id: source.id);

final class _OneWayMapper implements DartitectBoundaryMapper<_Source, _Target> {
  const _OneWayMapper();

  @override
  Result<_Target, DartitectMappingFailure> toTarget(_Source source) =>
      Ok<_Target>(_Target(source.id));
}

final class _BidirectionalMapper
    implements DartitectBidirectionalBoundaryMapper<_Source, _Target> {
  const _BidirectionalMapper();

  @override
  Result<_Target, DartitectMappingFailure> toTarget(_Source source) =>
      Ok<_Target>(_Target(source.id));

  @override
  Result<_Source, DartitectMappingFailure> fromTarget(_Target target) =>
      Ok<_Source>(_Source(target.id));
}
