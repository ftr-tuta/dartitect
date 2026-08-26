import 'package:dartitect_testing/dartitect_testing.dart';
import 'package:test/test.dart';

void main() {
  test('counter and finite sequence are deterministic and instance-owned', () {
    final counter = DeterministicIdGenerator(prefix: 'request', seed: 4);
    expect(counter.nextId(), 'request-5');
    expect(counter.nextId(), 'request-6');

    final sequence = DeterministicIdGenerator.sequence(<String>['a', 'b']);
    expect(sequence.nextId(), 'a');
    expect(sequence.nextId(), 'b');
    expect(sequence.nextId, throwsStateError);
  });
}
