import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

void main() {
  test('bounded progress rejects stale and non-monotonic executions', () {
    final reporter = BoundedProgressReporter<String>(capacity: 2);

    expect(
      reporter.report(
        const OperationProgress<String>(
          executionId: 1,
          sequence: 1,
          payload: 'one',
        ),
      ),
      isTrue,
    );
    expect(
      reporter.report(
        const OperationProgress<String>(
          executionId: 2,
          sequence: 1,
          payload: 'two',
        ),
      ),
      isTrue,
    );
    expect(
      reporter.report(
        const OperationProgress<String>(
          executionId: 1,
          sequence: 2,
          payload: 'late',
        ),
      ),
      isFalse,
    );
    expect(
      reporter.report(
        const OperationProgress<String>(
          executionId: 2,
          sequence: 1,
          payload: 'duplicate',
        ),
      ),
      isFalse,
    );
    expect(reporter.events.map((event) => event.payload), <String>[
      'one',
      'two',
    ]);
    expect(reporter.droppedEventCount, 2);

    reporter.dispose();
    expect(reporter.events, isEmpty);
    expect(reporter.isDisposed, isTrue);
  });

  test('execution context enforces cancellation and UTC deadline', () {
    final cancellation = CancellationSource();
    final reporter = BoundedProgressReporter<int>();
    var now = DateTime.utc(2026, 8, 28, 12);
    final context = CommandExecutionContext<int>(
      executionId: 7,
      cancellation: cancellation.signal,
      deadline: now.add(const Duration(seconds: 1)),
      now: () => now,
      progress: reporter,
    );

    expect(context.publish(10), isTrue);
    expect(reporter.events.single.sequence, 1);
    now = now.add(const Duration(seconds: 1));
    expect(
      () => context.publish(20),
      throwsA(isA<OperationDeadlineExceededException>()),
    );

    final other = CommandExecutionContext<int>(
      executionId: 8,
      cancellation: cancellation.signal,
    );
    cancellation.cancel('stop');
    expect(() => other.publish(1), throwsA(isA<CancellationException>()));
  });

  test('safe reporter isolates destination failure and recursion', () {
    late SafeProgressReporter<int> safe;
    final target = _Reporter<int>((event) {
      safe.report(event);
      throw StateError('destination');
    });
    safe = SafeProgressReporter<int>(reporter: target);

    expect(
      safe.report(
        const OperationProgress<int>(executionId: 1, sequence: 1, payload: 1),
      ),
      isFalse,
    );
    expect(safe.failureCount, 1);
    expect(safe.droppedReentrantCount, 1);
    expect(safe.isDisabled, isTrue);
  });
}

final class _Reporter<P> implements ProgressReporter<P> {
  const _Reporter(this.callback);

  final bool Function(OperationProgress<P> progress) callback;

  @override
  bool report(OperationProgress<P> progress) => callback(progress);
}
