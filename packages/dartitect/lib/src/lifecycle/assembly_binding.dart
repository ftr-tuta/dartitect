import 'dart:async';

import 'owned_graph.dart';

/// One typed owned-or-borrowed input consumed by generated assemblies.
///
/// A binding is single-use so one resource cannot be accidentally registered
/// into multiple generated graphs. Owned values are released by the graph in
/// reverse registration order; borrowed values must outlive that graph.
final class DartitectAssemblyBinding<T extends Object> {
  DartitectAssemblyBinding._(this.value, this._release, this._label);

  /// Declares [value] borrowed from a longer-lived provider owner.
  factory DartitectAssemblyBinding.borrowed(T value) =>
      DartitectAssemblyBinding<T>._(value, null, null);

  /// Declares [value] owned by the generated assembly.
  factory DartitectAssemblyBinding.owned(
    T value, {
    required FutureOr<void> Function(T value) release,
    required String label,
  }) {
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'Must not be blank.');
    }
    return DartitectAssemblyBinding<T>._(value, release, label);
  }

  /// Acquired typed value.
  final T value;

  final FutureOr<void> Function(T value)? _release;
  final String? _label;
  bool _consumed = false;

  /// Whether the generated assembly owns teardown for [value].
  bool get isOwned => _release != null;

  /// Registers this input exactly once in [transaction].
  ///
  /// This method is public for generated-code use. Application code should
  /// construct bindings and let its generated assembly consume them.
  T bind(ResourceTransaction transaction) {
    if (_consumed) {
      throw StateError('An assembly binding can be consumed only once.');
    }
    _consumed = true;
    final release = _release;
    return release == null
        ? transaction.borrow(value)
        : transaction.own(value, release, label: _label);
  }
}
