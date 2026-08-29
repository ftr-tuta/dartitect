import 'package:dartitect/dartitect.dart';

/// Consumer-owned payload accepted by the generated headless composition.
final class TasksHeadlessPayload {
  const TasksHeadlessPayload();
}

/// Composition seam adapted to dartitect_jobs by application wiring.
abstract interface class TasksHeadlessSync {
  Future<void> run(
    TasksHeadlessPayload payload,
    CancellationSignal cancellation,
  );
}
