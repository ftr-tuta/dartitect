import 'package:dartitect_testing/dartitect_testing.dart';

/// Demonstrates deterministic disposal observation without a test framework.
Future<void> main() async {
  final order = <String>[];
  final probe = DisposalProbe(label: 'database', order: order);
  await probe.disposeAsync();
  assert(order.single == 'database:disposeAsync');
}
