import 'package:dartitect/dartitect.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';
import 'package:dartitect_workmanager/dartitect_workmanager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('envelope round-trips a closed scalar schema', () {
    final envelope = DartitectWorkmanagerEnvelope(
      jobId: 'job-1',
      definition: 'sync',
      deadline: DateTime.utc(2026, 9),
      payload: <String, Object?>{
        'tenant': 'safe-id',
        'attempt': 1,
        'flags': <Object?>[true, false],
      },
    );

    final decoded = DartitectWorkmanagerEnvelope.fromInputData(
      Map<String, dynamic>.from(envelope.toInputData()),
    );
    expect(decoded.jobId, 'job-1');
    expect(decoded.payload['attempt'], 1);
    expect(
      () => DartitectWorkmanagerEnvelope.fromInputData(<String, dynamic>{
        ...envelope.toInputData(),
        'unknown': true,
      }),
      throwsFormatException,
    );
  });

  test(
    'Windows returns typed unsupported without invoking the plugin',
    () async {
      final port = _Port();
      final scheduler = DartitectWorkmanagerScheduler(
        port: port,
        platform: DartitectWorkmanagerPlatform.windows,
      );
      final result = await scheduler.schedule(
        DartitectWorkmanagerEnvelope(
          jobId: 'job-1',
          definition: 'sync',
          deadline: DateTime.utc(2027),
          payload: const <String, Object?>{},
        ),
      );

      expect(result, isA<DartitectWorkmanagerUnsupported>());
      expect(port.calls, 0);
    },
  );

  test(
    'callback creates and disposes a fresh dispatcher graph per run',
    () async {
      var graphs = 0;
      var disposals = 0;
      final receipts = _Receipts();
      final callback =
          DartitectWorkmanagerCallback<String, String, _Failure, int>(
            decodePayload: (payload) => payload['value']! as String,
            receipts: receipts,
            now: () => DateTime.utc(2026),
            createGraph: () {
              graphs += 1;
              return ResourceTransaction.create((transaction) {
                final dispatcher = JobDispatcher<String, String, _Failure, int>(
                  definitions: <JobDefinition<String, String, _Failure, int>>[
                    JobDefinition<String, String, _Failure, int>(
                      name: 'sync',
                      createGraph: (payload) =>
                          ResourceTransaction.create((inner) {
                            final handler = _Handler(payload);
                            inner.own(handler, (value) => value.disposeAsync());
                            return handler;
                          }),
                    ),
                  ],
                );
                transaction.own(dispatcher, (value) async {
                  await value.disposeAsync();
                  disposals += 1;
                });
                return dispatcher;
              });
            },
          );
      final input = DartitectWorkmanagerEnvelope(
        jobId: 'job-1',
        definition: 'sync',
        deadline: DateTime.utc(2027),
        payload: const <String, Object?>{
          'value': 'private-workmanager-payload',
        },
      ).toInputData();

      expect(
        await callback.execute('sync', Map<String, dynamic>.from(input)),
        isTrue,
      );
      expect(
        await callback.execute(
          'sync',
          Map<String, dynamic>.from(<String, Object?>{
            ...input,
            'jobId': 'job-2',
          }),
        ),
        isTrue,
      );
      expect(graphs, 2);
      expect(disposals, 2);
      expect(
        receipts.values.map((receipt) => receipt.status),
        everyElement(DartitectWorkmanagerReceiptStatus.completed),
      );
      final receiptFacts = <Map<String, Object?>>[
        for (final receipt in receipts.values)
          <String, Object?>{
            'jobId': receipt.jobId,
            'status': receipt.status.name,
            'recordedAtUtc': receipt.recordedAtUtc,
          },
      ];
      expect('$receiptFacts', isNot(contains('private-workmanager-payload')));
    },
  );
}

final class _Failure {
  const _Failure();
}

final class _Handler implements JobHandler<String, String, _Failure, int> {
  _Handler(this.value);

  final String value;
  var disposed = false;

  @override
  Future<Result<String, _Failure>> execute(
    String payload,
    JobExecutionContext<int> context,
  ) async {
    context.command.cancellation.throwIfCancelled();
    return Ok<String>('$value:$payload');
  }

  Future<void> disposeAsync() async => disposed = true;
}

final class _Port implements DartitectWorkmanagerPort {
  var calls = 0;

  @override
  Future<void> cancel(String uniqueName) async => calls += 1;

  @override
  Future<void> initialize(Function callbackDispatcher) async => calls += 1;

  @override
  Future<void> schedule(
    String uniqueName,
    String taskName,
    Map<String, Object?> inputData,
  ) async => calls += 1;
}

final class _Receipts implements DartitectWorkmanagerReceiptStore {
  final List<DartitectWorkmanagerReceipt> values =
      <DartitectWorkmanagerReceipt>[];

  @override
  Future<void> write(DartitectWorkmanagerReceipt receipt) async {
    values.add(receipt);
  }
}
