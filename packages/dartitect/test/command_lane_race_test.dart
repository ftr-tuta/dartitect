import 'dart:async';
import 'dart:math';

import 'package:dartitect/dartitect.dart';
import 'package:test/test.dart';

const _seed = 12001;
const _iterations = 240;

void main() {
  test(
    'deterministic execute cancel dispose races drain every policy',
    () async {
      final random = Random(_seed);
      final policies = <CommandConcurrency>[
        const CommandConcurrency.reject(),
        const CommandConcurrency.join(),
        const CommandConcurrency.drop(),
        const CommandConcurrency.sequential(maxQueue: 3),
        const CommandConcurrency.restartLatest(),
        const CommandConcurrency.concurrent(maxConcurrent: 3),
      ];
      for (var iteration = 0; iteration < _iterations; iteration += 1) {
        final policy = policies[iteration % policies.length];
        final gates = <Completer<void>>[];
        final outcomes = <Future<CommandOutcome<int, String>>>[];
        var active = 0;
        var peak = 0;
        final lane = CommandLane<int, String>(
          concurrency: policy,
          action: (signal) async {
            active += 1;
            peak = max(peak, active);
            final gate = Completer<void>();
            gates.add(gate);
            try {
              await Future.any(<Future<Object?>>[
                gate.future,
                signal.whenCancelled,
              ]);
              signal.throwIfCancelled();
              return Ok<int>(iteration);
            } finally {
              active -= 1;
            }
          },
        );

        final calls = 4 + random.nextInt(9);
        for (var call = 0; call < calls; call += 1) {
          outcomes.add(lane.execute());
          expect(lane.queuedCount, lessThanOrEqualTo(3));
          if (random.nextInt(5) == 0) lane.cancel('seed-$_seed-$iteration');
          if (random.nextBool()) {
            final open = gates.where((gate) => !gate.isCompleted).firstOrNull;
            open?.complete();
          }
          if (random.nextBool()) await Future<void>.delayed(Duration.zero);
        }

        final terminalBeforeDispose = lane.lastOutcomeExecutionId;
        await Future.wait<void>(<Future<void>>[lane.dispose(), lane.dispose()]);
        await Future.wait<CommandOutcome<int, String>>(outcomes);
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }
        await Future<void>.delayed(Duration.zero);

        expect(active, 0, reason: 'seed=$_seed iteration=$iteration');
        expect(lane.runningCount, 0, reason: 'iteration=$iteration');
        expect(lane.queuedCount, 0, reason: 'iteration=$iteration');
        expect(lane.isDisposed, isTrue, reason: 'iteration=$iteration');
        expect(lane.lastOutcomeExecutionId, terminalBeforeDispose);
        if (policy.kind != CommandConcurrencyKind.restartLatest) {
          final bound = policy.kind == CommandConcurrencyKind.concurrent
              ? policy.maxConcurrent
              : 1;
          expect(
            peak,
            lessThanOrEqualTo(bound),
            reason: 'iteration=$iteration',
          );
        }
        expect(
          await lane.execute(),
          isA<CommandRejected<int, String>>().having(
            (outcome) => outcome.reason,
            'reason',
            CommandLaneRejectionReason.disposed,
          ),
        );
      }
    },
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
