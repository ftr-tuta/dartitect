import 'package:dartitect/dartitect.dart';
import 'package:flutter/foundation.dart';

/// Flutter listenable adapter that borrows a [BoundedLocalHistory].
///
/// Disposing this adapter detaches its listeners but never disposes the
/// consumer-owned history.
final class LocalHistoryListenable<T> extends ChangeNotifier
    implements ValueListenable<T> {
  /// Borrows [history].
  LocalHistoryListenable(this.history);

  /// Consumer-owned local history.
  final BoundedLocalHistory<T> history;

  @override
  T get value => history.value;

  /// Whether the borrowed history can undo.
  bool get canUndo => history.canUndo;

  /// Whether the borrowed history can redo.
  bool get canRedo => history.canRedo;

  /// Records [next] and notifies when the value changed.
  bool edit(T next) => _apply(() => history.edit(next));

  /// Restores the previous value and notifies when available.
  bool undo() => _apply(history.undo);

  /// Reapplies the reverted value and notifies when available.
  bool redo() => _apply(history.redo);

  bool _apply(bool Function() operation) {
    final changed = operation();
    if (changed) notifyListeners();
    return changed;
  }
}
