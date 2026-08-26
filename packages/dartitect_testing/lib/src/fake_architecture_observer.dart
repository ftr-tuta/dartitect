import 'package:dartitect/dartitect.dart';

/// Captures architecture events in memory without a logging dependency.
final class FakeArchitectureObserver implements ArchitectureObserver {
  /// Captured events in delivery order.
  final List<ArchitectureEvent> events = <ArchitectureEvent>[];

  @override
  void onEvent(ArchitectureEvent event) => events.add(event);

  /// Returns events matching [kind].
  Iterable<ArchitectureEvent> whereKind(ArchitectureEventKind kind) =>
      events.where((event) => event.kind == kind);

  /// Removes every captured event.
  void clear() => events.clear();
}
