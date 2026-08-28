import 'package:dartitect_modeling/dartitect_modeling.dart';

/// Evidence from selecting the same immutable model twice.
final class ProjectionContractRun<Projection> {
  /// Creates deterministic projection evidence.
  const ProjectionContractRun({
    required this.first,
    required this.second,
    required this.deterministic,
  });

  /// First selected projection.
  final Projection first;

  /// Second selected projection from the identical model instance.
  final Projection second;

  /// Whether the consumer-provided equivalence contract accepted both values.
  final bool deterministic;
}

/// Exercises a generated record selector without prescribing a test runner.
final class ProjectionContractHarness<Model, Projection> {
  /// Creates a selector harness with optional domain-specific [equivalent].
  const ProjectionContractHarness({required this.selector, this.equivalent});

  /// Generated pure selector under test.
  final DartitectProjectionSelector<Model, Projection> selector;

  /// Projection equivalence used to report determinism.
  final bool Function(Projection left, Projection right)? equivalent;

  /// Selects twice and returns evidence for consumer assertions.
  ProjectionContractRun<Projection> run(Model model) {
    final first = selector(model);
    final second = selector(model);
    return ProjectionContractRun<Projection>(
      first: first,
      second: second,
      deterministic: equivalent?.call(first, second) ?? first == second,
    );
  }
}

/// Evidence from a forward mapping and an optional bidirectional round-trip.
final class MapperContractRun<Source, Target> {
  /// Creates mapper contract evidence.
  const MapperContractRun({
    required this.forward,
    required this.mapperIsBidirectional,
    required this.reverse,
    required this.roundTripEquivalent,
  });

  /// Forward result returned without translation or exception conversion.
  final Result<Target, DartitectMappingFailure> forward;

  /// Whether the mapper implements the bidirectional runtime contract.
  final bool mapperIsBidirectional;

  /// Reverse result when forward mapping succeeded on a bidirectional mapper.
  final Result<Source, DartitectMappingFailure>? reverse;

  /// Source equivalence, `false` for reverse failure, or `null` when untried.
  final bool? roundTripEquivalent;
}

/// Exercises generated one-way and bidirectional mappers without test APIs.
final class MapperContractHarness<Source, Target> {
  /// Creates a mapper harness with optional source equivalence.
  const MapperContractHarness({required this.mapper, this.sourceEquivalent});

  /// Generated pure mapper under test.
  final DartitectBoundaryMapper<Source, Target> mapper;

  /// Domain equivalence used for successful bidirectional round-trips.
  final bool Function(Source left, Source right)? sourceEquivalent;

  /// Runs forward mapping and reverse mapping when the contract supports it.
  MapperContractRun<Source, Target> run(Source source) {
    final forward = mapper.toTarget(source);
    final bidirectional =
        mapper is DartitectBidirectionalBoundaryMapper<Source, Target>;
    Result<Source, DartitectMappingFailure>? reverse;
    bool? equivalent;
    if (bidirectional) {
      forward.fold<void>((target) {
        reverse =
            (mapper as DartitectBidirectionalBoundaryMapper<Source, Target>)
                .fromTarget(target);
        equivalent = reverse!.fold<bool>(
          (roundTrip) =>
              sourceEquivalent?.call(source, roundTrip) ?? source == roundTrip,
          (_, _) => false,
        );
      }, (_, _) {});
    }
    return MapperContractRun<Source, Target>(
      forward: forward,
      mapperIsBidirectional: bidirectional,
      reverse: reverse,
      roundTripEquivalent: equivalent,
    );
  }
}
