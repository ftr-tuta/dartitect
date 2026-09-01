// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'package:flutter/widgets.dart';

import 'incremental_command.dart';

/// Material-neutral exhaustive rendering for an [IncrementalCommand].
final class IncrementalCommandStateBuilder<
  Item,
  Aggregate,
  Failure extends Object,
  Progress
>
    extends StatelessWidget {
  /// Creates an exhaustive renderer with an optional static [child].
  const IncrementalCommandStateBuilder({
    required this.command,
    required this.idle,
    required this.running,
    required this.succeeded,
    required this.failed,
    required this.cancelled,
    required this.crashed,
    this.child,
    super.key,
  });

  /// Borrowed command; this widget never disposes it.
  final IncrementalCommand<Item, Aggregate, Failure, Progress> command;

  /// Renders idle state.
  final ValueWidgetBuilder<IncrementalCommandIdle<Aggregate, Failure, Progress>>
  idle;

  /// Renders running state.
  final ValueWidgetBuilder<
    IncrementalCommandRunning<Aggregate, Failure, Progress>
  >
  running;

  /// Renders successful state.
  final ValueWidgetBuilder<
    IncrementalCommandSucceeded<Aggregate, Failure, Progress>
  >
  succeeded;

  /// Renders expected failure state.
  final ValueWidgetBuilder<
    IncrementalCommandFailed<Aggregate, Failure, Progress>
  >
  failed;

  /// Renders cancelled state.
  final ValueWidgetBuilder<
    IncrementalCommandCancelled<Aggregate, Failure, Progress>
  >
  cancelled;

  /// Renders crash state.
  final ValueWidgetBuilder<
    IncrementalCommandCrashed<Aggregate, Failure, Progress>
  >
  crashed;

  /// Optional subtree independent from command state.
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<
        IncrementalCommandState<Aggregate, Failure, Progress>
      >(
        valueListenable: command,
        child: child,
        builder: (context, state, child) => state.match<Widget>(
          idle: (state) => idle(context, state, child),
          running: (state) => running(context, state, child),
          succeeded: (state) => succeeded(context, state, child),
          failed: (state) => failed(context, state, child),
          cancelled: (state) => cancelled(context, state, child),
          crashed: (state) => crashed(context, state, child),
        ),
      );
}
