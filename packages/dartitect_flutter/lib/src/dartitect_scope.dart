import 'package:flutter/widgets.dart';

/// Marker implemented only by a composition-root facade carried by a scope.
///
/// Repositories, clients, Stores, and arbitrary services must not implement
/// this interface merely to become available through widget context. Expose a
/// narrow facade that creates route or feature ViewModels instead.
abstract interface class DartitectScopeValue {
  /// Stable identity of this composition-root generation.
  Object get scopeIdentity;
}

/// Carries one stable composition-root value through a Flutter subtree.
///
/// Reads are deliberately non-reactive. Mutable state should remain in small
/// listenables or streams owned by the provided runtime.
final class DartitectScope<T extends DartitectScopeValue>
    extends InheritedWidget {
  /// Creates a non-reactive scope.
  const DartitectScope({required this.value, required super.child, super.key});

  /// Stable runtime or composition value.
  final T value;

  /// Reads the nearest value without registering an inherited dependency.
  static T read<T extends DartitectScopeValue>(BuildContext context) {
    final value = maybeRead<T>(context);
    if (value != null) {
      return value;
    }
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('No DartitectScope<$T> found.'),
      ErrorDescription(
        'DartitectScope.read<$T>() was called with a context that does not '
        'contain that scope.',
      ),
      ErrorHint('Place DartitectScope<$T> above this widget.'),
    ]);
  }

  /// Reads the nearest value without registering an inherited dependency.
  static T? maybeRead<T extends DartitectScopeValue>(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DartitectScope<T>>();
    return scope?.value;
  }

  @override
  bool updateShouldNotify(covariant DartitectScope<T> oldWidget) {
    if (!identical(oldWidget.value.scopeIdentity, value.scopeIdentity)) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('DartitectScope identity changed in place.'),
        ErrorDescription(
          'A DartitectScope element cannot be retargeted to another '
          'composition-root generation.',
        ),
        ErrorHint(
          'Create a new owner and use a new Key when the application, '
          'session, feature, or route identity changes.',
        ),
      ]);
    }
    return false;
  }
}
