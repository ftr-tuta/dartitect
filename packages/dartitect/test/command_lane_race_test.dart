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

  test(
    'reentrant callbacks cancel or dispose every unkeyed policy safely',
    () async {
      for (final policy in _policies) {
        for (final dispose in <bool>[false, true]) {
          await _exerciseReentrantUnkeyed(policy, dispose: dispose);
        }
      }
    },
  );

  test(
    'reentrant callbacks cancel or dispose every keyed policy safely',
    () async {
      for (final policy in _policies) {
        for (final dispose in <bool>[false, true]) {
          await _exerciseReentrantKeyed(policy, dispose: dispose);
        }
      }
    },
  );
}

const _policies = <CommandConcurrency>[
  CommandConcurrency.reject(),
  CommandConcurrency.join(),
  CommandConcurrency.drop(),
  CommandConcurrency.sequential(maxQueue: 3),
  CommandConcurrency.restartLatest(),
  CommandConcurrency.concurrent(maxConcurrent: 3),
];

Future<void> _exerciseReentrantUnkeyed(
  CommandConcurrency policy, {
  required bool dispose,
}) async {
  late final CommandLane<int, String> lane;
  Future<void>? disposal;
  var requested = false;
  lane = CommandLane<int, String>(
    concurrency: policy,
    action: (signal) async {
      await signal.whenCancelled;
      signal.throwIfCancelled();
      return const Ok<int>(0);
    },
    onChanged: () {
      if (requested || lane.runningCount != 1) return;
      requested = true;
      if (dispose) {
        disposal = lane.dispose();
      } else {
        lane.cancel('reentrant cancel');
      }
    },
  );

  final outcome = lane.execute();
  if (disposal case final future?) await future;
  expect(await outcome, isA<CommandCancelled<int, String>>());
  await Future.wait<void>(<Future<void>>[lane.dispose(), lane.dispose()]);
  expect(lane.runningCount, 0, reason: '${policy.kind}/dispose=$dispose');
  expect(lane.queuedCount, 0, reason: '${policy.kind}/dispose=$dispose');
}

Future<void> _exerciseReentrantKeyed(
  CommandConcurrency policy, {
  required bool dispose,
}) async {
  late final KeyedCommandLane<String, int, int, String> lane;
  Future<void>? disposal;
  var requested = false;
  lane = KeyedCommandLane<String, int, int, String>(
    concurrency: CommandConcurrency.keyed(perKey: policy),
    action: (key, argument, signal) async {
      await signal.whenCancelled;
      signal.throwIfCancelled();
      return const Ok<int>(0);
    },
    onChanged: () {
      if (requested || lane.runningCount != 1) return;
      requested = true;
      if (dispose) {
        disposal = lane.dispose();
      } else {
        lane.cancelAll('reentrant cancel');
      }
    },
  );

  final outcome = lane.execute('key', 1);
  if (disposal case final future?) await future;
  expect(await outcome, isA<CommandCancelled<int, String>>());
  await Future.wait<void>(<Future<void>>[lane.dispose(), lane.dispose()]);
  expect(lane.runningCount, 0, reason: '${policy.kind}/dispose=$dispose');
  expect(lane.queuedCount, 0, reason: '${policy.kind}/dispose=$dispose');
  expect(lane.activeKeyCount, 0, reason: '${policy.kind}/dispose=$dispose');
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
