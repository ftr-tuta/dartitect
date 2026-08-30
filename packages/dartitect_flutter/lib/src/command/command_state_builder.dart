// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'package:flutter/widgets.dart';

import 'command.dart';

/// Material-neutral exhaustive rendering for a Dartitect command.
///
/// The builder supplies no labels, colors, layout, retry policy, or other
/// presentation defaults. Its listener is detached while the surrounding
/// [TickerMode] is disabled and catches up to the current state on resume.
final class CommandStateBuilder<T, F extends Object> extends StatefulWidget {
  /// Creates an exhaustive command-state renderer.
  const CommandStateBuilder({
    required this.command,
    required this.idle,
    required this.running,
    required this.success,
    required this.failure,
    required this.cancelled,
    required this.crashed,
    super.key,
  });

  /// Borrowed command. This widget never disposes it.
  final DartitectCommand<T, F> command;

  /// Renders the idle state.
  final Widget Function(BuildContext, CommandIdleState<T, F>) idle;

  /// Renders the running state.
  final Widget Function(BuildContext, CommandRunningState<T, F>) running;

  /// Renders a successful state.
  final Widget Function(BuildContext, CommandSuccessState<T, F>) success;

  /// Renders an expected typed failure.
  final Widget Function(BuildContext, CommandFailureState<T, F>) failure;

  /// Renders cooperative cancellation.
  final Widget Function(BuildContext, CommandCancelledState<T, F>) cancelled;

  /// Renders an unexpected crash without erasing its original stack.
  final Widget Function(BuildContext, CommandCrashState<T, F>) crashed;

  @override
  State<CommandStateBuilder<T, F>> createState() =>
      _CommandStateBuilderState<T, F>();
}

final class _CommandStateBuilderState<T, F extends Object>
    extends State<CommandStateBuilder<T, F>> {
  var _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reconcileListener(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(covariant CommandStateBuilder<T, F> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.command, widget.command)) return;
    if (_listening) {
      oldWidget.command.removeListener(_changed);
      widget.command.addListener(_changed);
    }
  }

  @override
  Widget build(BuildContext context) => widget.command.state.match<Widget>(
    idle: (state) => widget.idle(context, state),
    running: (state) => widget.running(context, state),
    success: (state) => widget.success(context, state),
    failure: (state) => widget.failure(context, state),
    cancelled: (state) => widget.cancelled(context, state),
    crashed: (state) => widget.crashed(context, state),
  );

  @override
  void dispose() {
    if (_listening) widget.command.removeListener(_changed);
    super.dispose();
  }

  void _reconcileListener(bool enabled) {
    if (enabled == _listening) return;
    _listening = enabled;
    if (enabled) {
      widget.command.addListener(_changed);
      setState(() {});
    } else {
      widget.command.removeListener(_changed);
    }
  }

  void _changed() {
    if (mounted && _listening) setState(() {});
  }
}
