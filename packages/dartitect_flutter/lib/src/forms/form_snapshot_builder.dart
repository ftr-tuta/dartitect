// This library is the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'package:flutter/widgets.dart';

import 'form_controller.dart';

/// Callback for the current immutable form snapshot.
typedef DartitectFormSnapshotWidgetBuilder<T, F extends Object> =
    Widget Function(
      BuildContext context,
      DartitectFormSnapshot<T, F> snapshot,
      Widget? child,
    );

/// Builds from a borrowed form controller only while ticker-enabled.
///
/// This widget never starts, submits, restores, or disposes [controller].
final class DartitectFormSnapshotBuilder<T, F extends Object>
    extends StatefulWidget {
  /// Creates a material-neutral form snapshot renderer.
  const DartitectFormSnapshotBuilder({
    required this.controller,
    required this.builder,
    this.child,
    super.key,
  });

  /// Borrowed controller.
  final DartitectFormController<T, F> controller;

  /// Renders its current immutable snapshot.
  final DartitectFormSnapshotWidgetBuilder<T, F> builder;

  /// Optional subtree independent from form state.
  final Widget? child;

  @override
  State<DartitectFormSnapshotBuilder<T, F>> createState() =>
      _DartitectFormSnapshotBuilderState<T, F>();
}

final class _DartitectFormSnapshotBuilderState<T, F extends Object>
    extends State<DartitectFormSnapshotBuilder<T, F>> {
  var _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(DartitectFormSnapshotBuilder<T, F> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) && _listening) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.controller.snapshot, widget.child);

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
