// This library is itself the package's explicit Flutter widget boundary.
// ignore_for_file: dartitect_flutter_type_boundary

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../binding_diagnostics.dart';
import 'live_collection.dart';
import 'live_resource.dart';
import 'paged_live_resource.dart';
import 'resource_lifecycle.dart';

/// Builds from one borrowed value while the surrounding ticker is enabled.
final class ReactiveValueBuilder<T> extends StatefulWidget {
  /// Creates a ticker-aware listener without taking ownership of [value].
  const ReactiveValueBuilder({
    required this.value,
    required this.builder,
    this.onBuild,
    this.child,
    super.key,
  });

  /// Borrowed value listenable.
  final ValueListenable<T> value;

  /// Builds from the latest value.
  final ValueWidgetBuilder<T> builder;

  /// Borrowed, payload-free build observer whose failures are isolated.
  final FlutterBindingBuildObserver? onBuild;

  /// Optional subtree that does not depend on [value].
  final Widget? child;

  @override
  State<ReactiveValueBuilder<T>> createState() =>
      _ReactiveValueBuilderState<T>();
}

final class _ReactiveValueBuilderState<T>
    extends State<ReactiveValueBuilder<T>> {
  var _listening = false;
  var _buildCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(ReactiveValueBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value) && _listening) {
      oldWidget.value.removeListener(_changed);
      widget.value.addListener(_changed);
    }
  }

  @override
  void dispose() {
    if (_listening) widget.value.removeListener(_changed);
    super.dispose();
  }

  void _setListening(bool enabled) {
    if (_listening == enabled) return;
    _listening = enabled;
    if (enabled) {
      widget.value.addListener(_changed);
    } else {
      widget.value.removeListener(_changed);
    }
  }

  void _changed() {
    if (mounted && _listening) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stopwatch = Stopwatch()..start();
    try {
      return widget.builder(context, widget.value.value, widget.child);
    } finally {
      stopwatch.stop();
      _reportBuild(
        widget.onBuild,
        FlutterBindingKind.reactiveValue,
        ++_buildCount,
        stopwatch.elapsed,
        _listening ? 1 : 0,
        _listening,
      );
    }
  }
}

/// Builder callback for one lifecycle-aware resource snapshot.
typedef LiveResourceWidgetBuilder<T, F extends Object> = Widget Function(
  BuildContext context,
  ResourceDataState<T, F> state,
  ResourceTemperature temperature,
  bool isStale,
  Widget? child,
);

/// Owns one ticker-aware observation of a borrowed [LiveResource].
final class LiveResourceBuilder<T, F extends Object> extends StatefulWidget {
  /// Creates a builder without taking ownership of [resource].
  const LiveResourceBuilder({
    required this.resource,
    required this.builder,
    this.onBuild,
    this.child,
    super.key,
  });

  /// Borrowed resource whose observation is widget-owned.
  final LiveResource<T, F> resource;

  /// Builds from data and temperature without replaying effects.
  final LiveResourceWidgetBuilder<T, F> builder;

  /// Borrowed, payload-free build observer whose failures are isolated.
  final FlutterBindingBuildObserver? onBuild;

  /// Optional subtree independent from resource state.
  final Widget? child;

  @override
  State<LiveResourceBuilder<T, F>> createState() =>
      _LiveResourceBuilderState<T, F>();
}

final class _LiveResourceBuilderState<T, F extends Object>
    extends State<LiveResourceBuilder<T, F>> {
  late ReactiveObservation<T, F> _observation;
  var _tickerEnabled = false;
  var _buildCount = 0;

  @override
  void initState() {
    super.initState();
    _observation = _createObservation(widget.resource);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled == enabled) return;
    _tickerEnabled = enabled;
    unawaited(_observation.setTickerEnabled(enabled));
  }

  @override
  void didUpdateWidget(LiveResourceBuilder<T, F> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.resource, widget.resource)) return;
    final previous = _observation;
    previous.removeListener(_changed);
    unawaited(previous.close());
    _observation = _createObservation(widget.resource);
    unawaited(_observation.setTickerEnabled(_tickerEnabled));
  }

  @override
  void dispose() {
    _observation.removeListener(_changed);
    unawaited(_observation.close());
    super.dispose();
  }

  ReactiveObservation<T, F> _createObservation(LiveResource<T, F> resource) {
    final observation = resource.observe(tickerEnabled: false);
    observation.addListener(_changed);
    return observation;
  }

  void _changed() {
    if (mounted && _observation.isActive) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stopwatch = Stopwatch()..start();
    try {
      return widget.builder(
        context,
        _observation.state,
        _observation.temperature,
        widget.resource.isStale,
        widget.child,
      );
    } finally {
      stopwatch.stop();
      _reportBuild(
        widget.onBuild,
        FlutterBindingKind.liveResource,
        ++_buildCount,
        stopwatch.elapsed,
        _tickerEnabled ? 1 : 0,
        _tickerEnabled,
      );
    }
  }
}

/// Builder callback for collection structure without implicit item listening.
typedef LiveCollectionWidgetBuilder<K, T> = Widget Function(
  BuildContext context,
  LiveCollection<K, T> collection,
  List<K> keys,
  Widget? child,
);

/// Listens only to borrowed collection structure while ticker-enabled.
///
/// Item-specific rebuilds remain explicit through [ReactiveValueBuilder] and
/// [LiveCollection.item], avoiding whole-list rebuilds for one changed value.
final class LiveCollectionBuilder<K, T> extends StatefulWidget {
  /// Creates a structural collection builder.
  const LiveCollectionBuilder({
    required this.collection,
    required this.builder,
    this.onBuild,
    this.child,
    super.key,
  });

  /// Borrowed collection.
  final LiveCollection<K, T> collection;

  /// Builds from the latest stable key order.
  final LiveCollectionWidgetBuilder<K, T> builder;

  /// Borrowed, payload-free build observer whose failures are isolated.
  final FlutterBindingBuildObserver? onBuild;

  /// Optional subtree independent from collection structure.
  final Widget? child;

  @override
  State<LiveCollectionBuilder<K, T>> createState() =>
      _LiveCollectionBuilderState<K, T>();
}

final class _LiveCollectionBuilderState<K, T>
    extends State<LiveCollectionBuilder<K, T>> {
  var _listening = false;
  var _buildCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(LiveCollectionBuilder<K, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.collection, widget.collection) && _listening) {
      oldWidget.collection.keys.removeListener(_changed);
      widget.collection.keys.addListener(_changed);
    }
  }

  @override
  void dispose() {
    if (_listening) widget.collection.keys.removeListener(_changed);
    super.dispose();
  }

  void _setListening(bool enabled) {
    if (_listening == enabled) return;
    _listening = enabled;
    if (enabled) {
      widget.collection.keys.addListener(_changed);
    } else {
      widget.collection.keys.removeListener(_changed);
    }
  }

  void _changed() {
    if (mounted && _listening) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stopwatch = Stopwatch()..start();
    try {
      return widget.builder(
        context,
        widget.collection,
        widget.collection.keys.value,
        widget.child,
      );
    } finally {
      stopwatch.stop();
      _reportBuild(
        widget.onBuild,
        FlutterBindingKind.liveCollection,
        ++_buildCount,
        stopwatch.elapsed,
        _listening ? 1 : 0,
        _listening,
      );
    }
  }
}

/// Builder callback for paged operation state and local collection structure.
typedef PagedLiveWidgetBuilder<C, K, T, F extends Object> = Widget Function(
  BuildContext context,
  PagedLiveResource<C, K, T, F> resource,
  List<K> keys,
  Widget? child,
);

/// Observes a borrowed paged resource only while ticker-enabled.
final class PagedLiveBuilder<C, K, T, F extends Object> extends StatefulWidget {
  /// Creates a paged builder without taking resource ownership.
  const PagedLiveBuilder({
    required this.resource,
    required this.builder,
    this.onBuild,
    this.child,
    super.key,
  });

  /// Borrowed paged resource; commands/effects remain route-owned.
  final PagedLiveResource<C, K, T, F> resource;

  /// Builds from operation state and the authoritative local key order.
  final PagedLiveWidgetBuilder<C, K, T, F> builder;

  /// Borrowed, payload-free build observer whose failures are isolated.
  final FlutterBindingBuildObserver? onBuild;

  /// Optional subtree independent from paged state.
  final Widget? child;

  @override
  State<PagedLiveBuilder<C, K, T, F>> createState() =>
      _PagedLiveBuilderState<C, K, T, F>();
}

final class _PagedLiveBuilderState<C, K, T, F extends Object>
    extends State<PagedLiveBuilder<C, K, T, F>> {
  var _listening = false;
  var _buildCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(PagedLiveBuilder<C, K, T, F> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.resource, widget.resource) && _listening) {
      _detach(oldWidget.resource);
      _attach(widget.resource);
    }
  }

  @override
  void dispose() {
    if (_listening) _detach(widget.resource);
    super.dispose();
  }

  void _setListening(bool enabled) {
    if (_listening == enabled) return;
    _listening = enabled;
    if (enabled) {
      _attach(widget.resource);
    } else {
      _detach(widget.resource);
    }
  }

  void _attach(PagedLiveResource<C, K, T, F> resource) {
    resource
      ..addListener(_changed)
      ..collection.keys.addListener(_changed);
  }

  void _detach(PagedLiveResource<C, K, T, F> resource) {
    resource
      ..removeListener(_changed)
      ..collection.keys.removeListener(_changed);
  }

  void _changed() {
    if (mounted && _listening) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stopwatch = Stopwatch()..start();
    try {
      return widget.builder(
        context,
        widget.resource,
        widget.resource.collection.keys.value,
        widget.child,
      );
    } finally {
      stopwatch.stop();
      _reportBuild(
        widget.onBuild,
        FlutterBindingKind.pagedLive,
        ++_buildCount,
        stopwatch.elapsed,
        _listening ? 2 : 0,
        _listening,
      );
    }
  }
}

void _reportBuild(
  FlutterBindingBuildObserver? observer,
  FlutterBindingKind kind,
  int buildCount,
  Duration duration,
  int liveHandleCount,
  bool tickerEnabled,
) {
  if (observer == null) return;
  try {
    observer(
      FlutterBindingBuildEvent(
        kind: kind,
        buildCount: buildCount,
        duration: duration,
        liveHandleCount: liveHandleCount,
        tickerEnabled: tickerEnabled,
      ),
    );
  } on Object {
    // Diagnostics cannot alter widget lifecycle or rendering.
    return;
  }
}
