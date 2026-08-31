import 'package:dartitect_tooling_packaged_canary/tooling_probe.dart';
import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test('tooling entrypoints link and census returns to zero', () {
    expect(toolingTypes, hasLength(7));
    expect(toolingExtension, startsWith('ext.dartitect.'));
    final census = ResourceCensus();
    final lease = census.acquire('tooling');
    lease.dispose();
    census.verifyZero();
  });
}
