// This library is itself the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'package:flutter/widgets.dart';

import 'binding_diagnostics.dart';

/// Builds the selected fragment of a [Listenable].
typedef ListenableSelectorBuilder<R> = Widget Function(
  BuildContext context,
  R value,
  Widget? child,
);

/// Selects a value from a listenable source.
typedef ListenableSelection<S extends Listenable, R> = R Function(S source);

/// Compares two selected values for meaningful equality.
typedef ListenableSelectionEquals<R> = bool Function(R previous, R next);

/// Rebuilds only when a selected value changes.
final class ListenableSelector<S extends Listenable, R> extends StatefulWidget {
  /// Creates a selector.
  const ListenableSelector({
    required this.source,
    required this.select,
    required this.builder,
    this.equals,
    this.onBuild,
    this.child,
    super.key,
  });

  /// Source whose notifications trigger selection.
  final S source;

  /// Reads the selected value from [source].
  final ListenableSelection<S, R> select;

  /// Builds when the selected value changes.
  final ListenableSelectorBuilder<R> builder;

  /// Equality override. Defaults to `previous == next`.
  final ListenableSelectionEquals<R>? equals;

  /// Borrowed, payload-free build observer whose failures are isolated.
  final FlutterBindingBuildObserver? onBuild;

  /// Stable subtree passed back to [builder].
  final Widget? child;

  @override
  State<ListenableSelector<S, R>> createState() =>
      _ListenableSelectorState<S, R>();
}

final class _ListenableSelectorState<S extends Listenable, R>
    extends State<ListenableSelector<S, R>> {
  late R _selected;
  var _listening = false;
  var _buildCount = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.select(widget.source);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(covariant ListenableSelector<S, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      if (_listening) {
        oldWidget.source.removeListener(_sourceChanged);
        widget.source.addListener(_sourceChanged);
      }
    }
    final next = widget.select(widget.source);
    _selected = next;
  }

  @override
  Widget build(BuildContext context) {
    final stopwatch = Stopwatch()..start();
    try {
      return widget.builder(context, _selected, widget.child);
    } finally {
      stopwatch.stop();
      _reportBuild(stopwatch.elapsed);
    }
  }

  @override
  void dispose() {
    if (_listening) widget.source.removeListener(_sourceChanged);
    super.dispose();
  }

  void _setListening(bool enabled) {
    if (_listening == enabled) return;
    _listening = enabled;
    if (enabled) {
      _selected = widget.select(widget.source);
      widget.source.addListener(_sourceChanged);
    } else {
      widget.source.removeListener(_sourceChanged);
    }
  }

  void _sourceChanged() {
    if (!mounted || !_listening) return;
    final next = widget.select(widget.source);
    final equals = widget.equals ?? _defaultEquals;
    if (equals(_selected, next)) {
      return;
    }
    setState(() {
      _selected = next;
    });
  }

  void _reportBuild(Duration duration) {
    final observer = widget.onBuild;
    if (observer == null) return;
    _buildCount += 1;
    try {
      observer(
        FlutterBindingBuildEvent(
          kind: FlutterBindingKind.listenableSelector,
          buildCount: _buildCount,
          duration: duration,
          liveHandleCount: _listening ? 1 : 0,
          tickerEnabled: _listening,
        ),
      );
    } on Object {
      // Diagnostics cannot alter widget lifecycle or rendering.
      return;
    }
  }

  static bool _defaultEquals<R>(R previous, R next) => previous == next;
}
