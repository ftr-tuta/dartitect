import 'dart:async';
import 'dart:collection';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

/// Lifetime category that owns an [EffectChannel].
enum EffectOwnerKind {
  /// The application shell owns the channel.
  application,

  /// One session generation owns the channel.
  session,

  /// One route generation owns the channel.
  route,
}

/// Opaque, immutable owner identity for one effect-channel generation.
final class EffectOwnerIdentity {
  /// Creates an owner identity.
  const EffectOwnerIdentity({required this.kind, required this.generation});

  /// Lifetime category of the owner.
  final EffectOwnerKind kind;

  /// Opaque generation token. It must not contain user or session identity.
  final Object generation;
}

/// Result of publishing one effect into a bounded channel.
enum EffectPublishResult {
  /// The effect was accepted for one FIFO delivery.
  accepted,

  /// The bounded channel has no remaining capacity.
  full,

  /// Channel disposal has begun.
  disposed,
}

/// Write-only effect boundary exposed to a ViewModel.
abstract interface class EffectSink<E extends Object> {
  /// Attempts to accept [effect] without blocking or dropping silently.
  EffectPublishResult emit(E effect);
}

/// Reports an unexpected consumer failure without changing channel state.
abstract interface class EffectErrorReporter {
  /// Reports [error] with its original [stackTrace].
  void report(Object error, StackTrace stackTrace);
}

/// Reporter that deliberately ignores consumer failures.
final class NoOpEffectErrorReporter implements EffectErrorReporter {
  /// Creates a no-op reporter.
  const NoOpEffectErrorReporter();

  @override
  void report(Object error, StackTrace stackTrace) {}
}

/// Exact-once registration for the only logical channel consumer.
final class EffectSubscription implements Disposable {
  EffectSubscription._(this._detach);

  void Function()? _detach;

  /// Whether this registration has detached.
  bool get isDisposed => _detach == null;

  @override
  void dispose() {
    final detach = _detach;
    if (detach == null) return;
    _detach = null;
    detach();
  }
}

/// Owned, bounded, single-consumer FIFO for transient UI reactions.
final class EffectChannel<E extends Object> implements AsyncDisposable {
  /// Creates an effect channel for exactly one owner generation.
  EffectChannel({
    required this.capacity,
    required this.owner,
    EffectErrorReporter reporter = const NoOpEffectErrorReporter(),
  }) : _reporter = reporter {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
    _sink = _ChannelEffectSink<E>(this);
  }

  /// Maximum accepted effects including one delivery in progress.
  final int capacity;

  /// Immutable owner identity.
  final EffectOwnerIdentity owner;

  final EffectErrorReporter _reporter;
  final Queue<E> _pending = Queue<E>();
  final Completer<void> _disposalStarted = Completer<void>();
  late final EffectSink<E> _sink;
  FutureOr<void> Function(E effect)? _consumer;
  Object? _consumerToken;
  Future<void>? _drainFuture;
  Future<void>? _disposeFuture;
  var _delivering = false;
  var _disposed = false;

  /// Write-only boundary intended for ViewModels and operations.
  EffectSink<E> get sink => _sink;

  /// Number of accepted effects not yet terminally delivered or discarded.
  int get pendingCount => _pending.length + (_delivering ? 1 : 0);

  /// Whether one logical consumer is attached.
  bool get hasConsumer => _consumer != null;

  /// Whether terminal disposal has begun.
  bool get isDisposed => _disposed;

  /// Attaches the only logical consumer.
  ///
  /// Widgets normally use [EffectListener]. The headless form exists for tests
  /// and application-shell adapters that do not store a `BuildContext`.
  EffectSubscription listen(FutureOr<void> Function(E effect) onEffect) {
    if (_disposed) throw StateError('EffectChannel is disposed.');
    if (_consumer != null) {
      throw StateError('EffectChannel already has an active consumer.');
    }
    final token = Object();
    _consumerToken = token;
    _consumer = onEffect;
    _startDrain();
    return EffectSubscription._(() {
      if (!identical(_consumerToken, token)) return;
      _consumerToken = null;
      _consumer = null;
    });
  }

  EffectPublishResult _emit(E effect) {
    if (_disposed) return EffectPublishResult.disposed;
    if (pendingCount >= capacity) return EffectPublishResult.full;
    _pending.addLast(effect);
    _startDrain();
    return EffectPublishResult.accepted;
  }

  void _startDrain() {
    if (_disposed || _consumer == null || _drainFuture != null) return;
    final drain = _drain();
    _drainFuture = drain;
    unawaited(
      drain.whenComplete(() {
        _drainFuture = null;
        if (!_disposed && _consumer != null && _pending.isNotEmpty) {
          _startDrain();
        }
      }),
    );
  }

  Future<void> _drain() async {
    while (!_disposed && _consumer != null && _pending.isNotEmpty) {
      final effect = _pending.removeFirst();
      final consumer = _consumer;
      if (consumer == null) {
        _pending.addFirst(effect);
        return;
      }
      _delivering = true;
      try {
        await consumer(effect);
      } catch (error, stackTrace) {
        try {
          _reporter.report(error, stackTrace);
        } on Object {
          // Diagnostics cannot reinsert an already delivered effect.
          continue;
        }
      } finally {
        _delivering = false;
      }
    }
  }

  /// Closes admission, discards pending effects, and drains an active callback.
  @override
  Future<void> disposeAsync() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _disposalStarted.complete();
    _consumer = null;
    _consumerToken = null;
    _pending.clear();
    await _drainFuture;
  }
}

final class _ChannelEffectSink<E extends Object> implements EffectSink<E> {
  const _ChannelEffectSink(this._channel);

  final EffectChannel<E> _channel;

  @override
  EffectPublishResult emit(E effect) => _channel._emit(effect);
}

/// Binds one owned effect channel to the widget subtree's current context.
final class EffectListener<E extends Object> extends StatefulWidget {
  /// Creates a single-consumer effect binding.
  const EffectListener({
    required this.channel,
    required this.onEffect,
    required this.child,
    super.key,
  });

  /// Borrowed channel whose owner outlives this binding.
  final EffectChannel<E> channel;

  /// Handles a delivered effect using the currently mounted context.
  final void Function(BuildContext context, E effect) onEffect;

  /// Non-reactive child subtree.
  final Widget child;

  @override
  State<EffectListener<E>> createState() => _EffectListenerState<E>();
}

final class _EffectListenerState<E extends Object>
    extends State<EffectListener<E>> {
  EffectSubscription? _subscription;
  Completer<void>? _activityChanged;
  var _attachmentGeneration = 0;
  var _contextIsActive = false;

  @override
  void initState() {
    super.initState();
    _scheduleAttach();
  }

  @override
  void didUpdateWidget(covariant EffectListener<E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.channel, widget.channel)) {
      _invalidateAttachment();
      _scheduleAttach();
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final isActive =
        TickerMode.valuesOf(context).enabled && (route?.isCurrent ?? true);
    if (_contextIsActive != isActive) {
      _contextIsActive = isActive;
      _signalActivityChanged();
    }
    return widget.child;
  }

  @override
  void dispose() {
    _invalidateAttachment();
    super.dispose();
  }

  void _scheduleAttach() {
    final generation = ++_attachmentGeneration;
    final channel = widget.channel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _attachmentGeneration ||
          !identical(channel, widget.channel)) {
        return;
      }
      _subscription = channel.listen(
        (effect) => _deliver(generation, channel, effect),
      );
    });
  }

  Future<void> _deliver(
    int generation,
    EffectChannel<E> channel,
    E effect,
  ) async {
    while (_isCurrent(generation, channel)) {
      if (_contextIsActive) {
        widget.onEffect(context, effect);
        return;
      }
      final changed = Completer<void>();
      _activityChanged = changed;
      if (_contextIsActive || !_isCurrent(generation, channel)) {
        _signalActivityChanged();
      }
      await Future.any<void>(<Future<void>>[
        changed.future,
        channel._disposalStarted.future,
      ]);
      if (identical(_activityChanged, changed)) _activityChanged = null;
    }
  }

  bool _isCurrent(int generation, EffectChannel<E> channel) =>
      mounted &&
      !channel.isDisposed &&
      generation == _attachmentGeneration &&
      identical(channel, widget.channel);

  void _invalidateAttachment() {
    _attachmentGeneration += 1;
    _subscription?.dispose();
    _subscription = null;
    _signalActivityChanged();
  }

  void _signalActivityChanged() {
    final changed = _activityChanged;
    _activityChanged = null;
    if (changed != null && !changed.isCompleted) changed.complete();
  }
}
