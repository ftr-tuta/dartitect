import 'package:dartitect/dartitect.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';

void main() async {
  final dispatcher = JobDispatcher<int, int, StateError, void>(
    definitions: <JobDefinition<int, int, StateError, void>>[
      JobDefinition<int, int, StateError, void>(
        name: 'double',
        createGraph: (_) =>
            ResourceTransaction.create((_) => const _DoubleJob()),
      ),
    ],
  );
  final terminal = await dispatcher.handle(
    JobEnvelope<int>(
      jobId: 'example-1',
      definition: 'double',
      deadline: DateTime.now().toUtc().add(const Duration(seconds: 10)),
      payload: 2,
    ),
  );
  final doubled = terminal is JobCompleted<int, StateError>
      ? terminal.result
      : null;
  assert(doubled == 4);
  await dispatcher.disposeAsync();
}

final class _DoubleJob implements JobHandler<int, int, StateError, void> {
  const _DoubleJob();

  @override
  Future<Result<int, StateError>> execute(
    int payload,
    JobExecutionContext<void> context,
  ) async => Ok<int>(payload * 2);
}
