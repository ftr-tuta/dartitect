// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'package:flutter/widgets.dart';

import 'query_controller.dart';

/// Material-neutral exhaustive rendering for a borrowed query controller.
final class DartitectQueryStateBuilder<Q, T, F extends Object>
    extends StatefulWidget {
  /// Creates a complete query-state renderer.
  const DartitectQueryStateBuilder({
    required this.controller,
    required this.initial,
    required this.loading,
    required this.empty,
    required this.content,
    required this.failure,
    super.key,
  });

  /// Borrowed controller. This widget never starts or disposes it.
  final DartitectQueryController<Q, T, F> controller;

  /// Renders the initial state.
  final Widget Function(BuildContext, DartitectQueryInitial<T, F>) initial;

  /// Renders loading with optional stale items.
  final Widget Function(BuildContext, DartitectQueryLoading<T, F>) loading;

  /// Renders a successful empty state.
  final Widget Function(BuildContext, DartitectQueryEmpty<T, F>) empty;

  /// Renders successful content, including stale-content metadata.
  final Widget Function(BuildContext, DartitectQueryContent<T, F>) content;

  /// Renders an expected typed failure and optional stale items.
  final Widget Function(BuildContext, DartitectQueryFailure<T, F>) failure;

  @override
  State<DartitectQueryStateBuilder<Q, T, F>> createState() =>
      _DartitectQueryStateBuilderState<Q, T, F>();
}

final class _DartitectQueryStateBuilderState<Q, T, F extends Object>
    extends State<DartitectQueryStateBuilder<Q, T, F>> {
  var _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(DartitectQueryStateBuilder<Q, T, F> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) && _listening) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.controller.state) {
    final DartitectQueryInitial<T, F> state => widget.initial(context, state),
    final DartitectQueryLoading<T, F> state => widget.loading(context, state),
    final DartitectQueryEmpty<T, F> state => widget.empty(context, state),
    final DartitectQueryContent<T, F> state => widget.content(context, state),
    final DartitectQueryFailure<T, F> state => widget.failure(context, state),
  };

  @override
  void dispose() {
    if (_listening) widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _setListening(bool enabled) {
    if (_listening == enabled) return;
    _listening = enabled;
    if (enabled) {
      widget.controller.addListener(_changed);
      setState(() {});
    } else {
      widget.controller.removeListener(_changed);
    }
  }

  void _changed() {
    if (mounted && _listening) setState(() {});
  }
}
