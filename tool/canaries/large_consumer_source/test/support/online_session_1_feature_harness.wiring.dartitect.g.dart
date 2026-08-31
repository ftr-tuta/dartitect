// GENERATED CODE - DO NOT EDIT BY HAND.
// Managed by `dartitect wiring sync` from strict config v3.
// ignore_for_file: public_member_api_docs, directives_ordering

import 'package:dartitect_testing/dartitect_testing.dart';

/// Fully managed contract harness selected from the OnlineSession1 feature profile.
final class OnlineSession1FeatureHarness<
  T extends OnlineFeatureContractDriver
> {
  const OnlineSession1FeatureHarness({required this.fixtures});

  /// Consumer fixtures and domain assertions; infrastructure is matrix-owned.
  final FeatureContractFixtures<T> fixtures;

  /// Declared stable capability closure.
  static const List<String> capabilities = <String>['attachments'];

  /// Exact profile matrix for this generated feature.
  FeatureContractMatrix<T> get matrix =>
      FeatureContractMatrix<T>.online(fixtures: fixtures);

  /// Executes every required row with a fresh graph and zero-residual census.
  Future<List<FeatureContractResult>> run() => matrix.run();
}
