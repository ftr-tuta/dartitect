import 'dart:async';

import 'package:dartitect/dartitect.dart';
import 'package:objectbox/objectbox.dart';

/// Owns ObjectBox-adjacent subscriptions, timers, queries, and watchers.
///
/// Dispose this registry before closing its Store. Registrations are released
/// in reverse order and share [ResourceOwner]'s aggregate failure semantics.
final class ObjectBoxObservationOwner implements AsyncDisposable {
  /// Creates an observation owner.
  ObjectBoxObservationOwner({
    ArchitectureObserver observer = const NoOpArchitectureObserver(),
  }) : _resources = ResourceOwner(
         observer: observer,
         label: 'ObjectBoxObservationOwner',
       );

  final ResourceOwner _resources;

  /// Whether observation cleanup has finished.
  bool get isDisposed => _resources.isDisposed;

  /// Owns a stream subscription.
  StreamSubscription<T> ownSubscription<T>(
    StreamSubscription<T> subscription, {
    String label = 'ObjectBox subscription',
  }) => _resources.own(subscription, (value) => value.cancel(), label: label);

  /// Owns a timer.
  Timer ownTimer(Timer timer, {String label = 'ObjectBox timer'}) =>
      _resources.own(timer, (value) => value.cancel(), label: label);

  /// Owns a query that must close before its Store.
  Query<T> ownQuery<T>(Query<T> query, {String label = 'ObjectBox query'}) =>
      _resources.own(query, (value) => value.close(), label: label);

  /// Owns any watcher/controller handle with an explicit release callback.
  T own<T>(
    T value,
    FutureOr<void> Function(T value) release, {
    String label = 'ObjectBox observation',
  }) => _resources.own(value, release, label: label);

  @override
  Future<void> disposeAsync() => _resources.disposeAsync();
}
