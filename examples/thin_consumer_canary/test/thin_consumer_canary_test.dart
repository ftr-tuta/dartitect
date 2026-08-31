import 'package:dartitect/dartitect_credentials.dart';
import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:dartitect_flutter/dartitect_flutter_forms.dart';
import 'package:dartitect_flutter/dartitect_flutter_queries.dart';
import 'package:dartitect_jobs/dartitect_jobs.dart';
import 'package:dartitect_resilience/dartitect_resilience.dart';
import 'package:dartitect_sync/dartitect_sync.dart';
import 'package:dartitect_transfer/dartitect_attachments.dart';
import 'package:dartitect_transfer/dartitect_transfer.dart';
import 'package:dartitect_workmanager/dartitect_workmanager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:thin_consumer_canary/composition/application_module.wiring.dartitect.g.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_mutation.dart';
import 'package:thin_consumer_canary/features/tasks/application/tasks_remote_port.dart';
import 'package:thin_consumer_canary/features/tasks/composition/tasks.wiring.dartitect.g.dart';
import 'package:thin_consumer_canary/features/tasks/composition/tasks_workmanager.wiring.dartitect.g.dart';
import 'package:thin_consumer_canary/features/tasks/composition/tasks_factory.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_model.dart';
import 'package:thin_consumer_canary/features/tasks/domain/tasks_repository.dart';
import 'package:thin_consumer_canary/presentation/thin_consumer_app.dart';

final class _Failure implements Exception {
  const _Failure();
}

void main() {
  testWidgets('generated graph renders Tasks through FeatureHost', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationHost<ApplicationGraph>.create(
          create: ApplicationModule.create,
          loading: (_) => const Text('Bootstrapping'),
          failure: (_, failure, retry) => TextButton(
            onPressed: retry,
            child: const Text('Retry bootstrap'),
          ),
          ready: (_, graph) => ThinConsumerApp(graph: graph),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First Task'), findsOneWidget);
    expect(find.text('Status: open'), findsOneWidget);

    await tester.tap(find.text('First Task'));
    await tester.pumpAndSettle();
    expect(find.text('Status: completed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('strict wiring enables the complete opt-in workflow set', () async {
    expect(TasksFeatureWiring.profile, 'offline-full');
    expect(TasksFeatureWiring.scope, 'application');
    expect(TasksFeatureWiring.storageContext, 'primary');
    expect(TasksFeatureWiring.transport, 'api');
    expect(TasksFeatureWiring.scheduler, 'workmanager');
    expect(TasksFeatureWiring.headlessTargets, <String>[
      'android',
      'ios',
      'macos',
      'linux',
      'web',
    ]);
    expect(TasksFeatureWiring.capabilities, <String>[
      'attachments',
      'credentials',
      'forms',
      'queries',
    ]);

    final credential = CredentialRecord<String>(value: 'redacted');
    expect(credential.expiresAt, isNull);
    final attachment = AttachmentBackgroundRequest(
      protocolVersion: 1,
      attachmentId: 'attachment-1',
      deadline: DateTime.utc(2030),
    );
    expect(attachment.attachmentId, 'attachment-1');

    final form = DartitectFormController<int, _Failure>(
      original: 1,
      equals: (left, right) => left == right,
      submitter: (_, _) async => const Ok<void>(null),
    );
    form.update(2);
    expect(form.snapshot.dirty, isTrue);
    await form.disposeAsync();

    final page = DartitectQueryPage<int>(items: <int>[1], nextCursor: 'next');
    expect(page.items, <int>[1]);
    expect(page.nextCursor, 'next');

    final windows = DartitectWorkmanagerCapability.forPlatform(
      DartitectWorkmanagerPlatform.windows,
    );
    expect(windows.maturity, DartitectWorkmanagerMaturity.unsupported);
    expect(<Type>[JobEnvelope, RateLimiter, TransferChunk], hasLength(3));
  });

  test('generated graph owns offline mutation, restart recovery, sync, and disposal', () async {
    final coordinator = ApplicationModule.create();
    final attempt = await coordinator.run();
    expect(attempt, isA<BootstrapSucceeded<ApplicationGraph>>());
    final application = (attempt as BootstrapSucceeded<ApplicationGraph>).graph;
    addTearDown(coordinator.disposeAsync);

    final first = await ResourceTransaction.create<TasksRuntime>(
      (transaction) => TasksRuntime.create(
        application.root,
        const TasksFactory(),
        transaction,
      ),
    );
    first.root.remotePort.mode = TasksRemoteMode.offline;
    final queued = await first.root.mutationCommand.execute(
      'first',
      const TasksMutation(aggregateId: 'first'),
    );
    expect(
      (queued
              as CommandSucceeded<
                MutationExecution<TasksMutation, String, void, TasksFailure>,
                TasksFailure
              >)
          .value
          .disposition,
      CommitDisposition.queued,
    );
    expect(
      application.root.primary.outbox.single.syncState,
      EntitySyncState.pending,
    );
    final readCancellation = CancellationSource();
    expect(
      (await application.root.primary.read(
        readCancellation.signal,
      ) as Ok<List<Task>>).value.single.status,
      TaskStatus.completed,
    );
    readCancellation.dispose();
    await first.disposeAsync();
    expect(first.root.mutationCommand.isDisposed, isTrue);

    final restarted = await ResourceTransaction.create<TasksRuntime>(
      (transaction) => TasksRuntime.create(
        application.root,
        const TasksFactory(),
        transaction,
      ),
    );
    restarted.root.remotePort.mode = TasksRemoteMode.online;
    final recovered = await restarted.root.mutationCommand.recoverPending();
    expect(recovered, isA<Ok<dynamic>>());
    expect(restarted.root.remotePort.deliveredIdempotencyKeys, hasLength(1));
    expect(
      application.root.primary.outbox.single.syncState,
      EntitySyncState.synced,
    );

    await application.root.primary.addOffline(
      const Task(id: 'conflict', title: 'Conflicting Task'),
    );
    restarted.root.remotePort.mode = TasksRemoteMode.conflict;
    final conflicted = await restarted.root.mutationCommand.execute(
      'conflict',
      const TasksMutation(aggregateId: 'conflict'),
    );
    expect(
      (conflicted
              as CommandSucceeded<
                MutationExecution<TasksMutation, String, void, TasksFailure>,
                TasksFailure
              >)
          .value
          .syncState,
      EntitySyncState.conflicted,
    );

    await application.root.primary.addOffline(
      const Task(id: 'uncertain', title: 'Uncertain Task'),
    );
    restarted.root.remotePort.mode = TasksRemoteMode.uncertain;
    final uncertain = await restarted.root.mutationCommand.execute(
      'uncertain',
      const TasksMutation(aggregateId: 'uncertain'),
    );
    expect(
      (uncertain
              as CommandSucceeded<
                MutationExecution<TasksMutation, String, void, TasksFailure>,
                TasksFailure
              >)
          .value
          .disposition,
      CommitDisposition.uncertain,
    );

    final sync = await restarted.root.syncEngine.start().done;
    expect(sync.succeeded, isTrue);
    final headless = TasksWorkmanagerJob.create(
      jobId: 'tasks-headless',
      deadline: DateTime.utc(2030),
    );
    expect(headless.definition, 'tasks');
    await restarted.disposeAsync();
    expect(restarted.root.mutationCommand.isDisposed, isTrue);
    expect(restarted.root.syncEngine.activeRunCount, 0);
    await application.disposeAsync();
    expect(application.root.primary.closed, isTrue);
  });
}
