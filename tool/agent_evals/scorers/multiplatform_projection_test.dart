import 'package:dartitect_flutter_quality_eval_fixture/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects every native capability outcome explicitly', () {
    expect(
      <String>[
        for (final state in CapabilityState.values) projectCapability(state),
      ],
      <String>[
        'Ready',
        'Unsupported',
        'Permission required',
        'Permission denied',
        'Temporarily unavailable',
        'Provider failure',
      ],
    );
  });
}
