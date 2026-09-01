import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Internal listener storage with O(1) identity removal and tombstoned dispatch.
///
/// A dispatch observes the tail that existed when it started. Listeners added
/// by a callback are therefore deferred until the next dispatch, while a
/// listener removed before its turn is skipped. Tombstones keep nested
/// notifications and removal during callbacks safe without snapshot copies.
final class ListenerRegistry {
  final HashMap<VoidCallback, ListQueue<_ListenerEntry>> _byListener =
      HashMap<VoidCallback, ListQueue<_ListenerEntry>>.identity();
  _ListenerEntry? _head;
  _ListenerEntry? _tail;
  var _length = 0;
  var _dispatchDepth = 0;
  var _needsSweep = false;

  /// Number of active callback registrations.
  int get length => _length;

  /// Whether no callbacks are registered.
  bool get isEmpty => _length == 0;

  /// Whether at least one callback is registered.
  bool get isNotEmpty => _length != 0;

  /// Whether [listener] has at least one active identity registration.
  bool contains(VoidCallback listener) => _byListener.containsKey(listener);

  /// Appends one callback registration.
  void add(VoidCallback listener) {
    final entry = _ListenerEntry(listener);
    final tail = _tail;
    if (tail == null) {
      _head = entry;
    } else {
      tail.next = entry;
      entry.previous = tail;
    }
    _tail = entry;
    (_byListener[listener] ??= ListQueue<_ListenerEntry>()).addLast(entry);
    _length += 1;
  }

  /// Removes the oldest matching identity registration, when present.
  bool remove(VoidCallback listener) {
    final entries = _byListener[listener];
    if (entries == null || entries.isEmpty) return false;
    final entry = entries.removeFirst();
    if (entries.isEmpty) _byListener.remove(listener);
    entry.removed = true;
    _length -= 1;
    if (_dispatchDepth == 0) {
      _unlink(entry);
    } else {
      _needsSweep = true;
    }
    return true;
  }

  /// Removes every callback registration.
  void clear() {
    if (_length == 0) return;
    _byListener.clear();
    _length = 0;
    if (_dispatchDepth == 0) {
      _head = null;
      _tail = null;
      _needsSweep = false;
      return;
    }
    var entry = _head;
    while (entry != null) {
      entry.removed = true;
      entry = entry.next;
    }
    _needsSweep = true;
  }

  /// Calls the registrations present at dispatch start in insertion order.
  void notifySafely({
    bool Function()? shouldContinue,
    void Function(Object error, StackTrace stackTrace)? onFailure,
  }) {
    final stop = _tail;
    if (stop == null) return;
    _dispatchDepth += 1;
    try {
      var entry = _head;
      while (entry != null) {
        final next = entry.next;
        if (shouldContinue != null && !shouldContinue()) break;
        if (!entry.removed) {
          try {
            entry.listener();
          } catch (error, stackTrace) {
            try {
              onFailure?.call(error, stackTrace);
            } on Object catch (reportingError, reportingStackTrace) {
              _discardFailureReportingError(
                reportingError,
                reportingStackTrace,
              );
            }
          }
        }
        if (identical(entry, stop)) break;
        entry = next;
      }
    } finally {
      _dispatchDepth -= 1;
      if (_dispatchDepth == 0 && _needsSweep) _sweep();
    }
  }

  void _unlink(_ListenerEntry entry) {
    final previous = entry.previous;
    final next = entry.next;
    if (previous == null) {
      _head = next;
    } else {
      previous.next = next;
    }
    if (next == null) {
      _tail = previous;
    } else {
      next.previous = previous;
    }
    entry
      ..previous = null
      ..next = null;
  }

  void _sweep() {
    var entry = _head;
    while (entry != null) {
      final next = entry.next;
      if (entry.removed) _unlink(entry);
      entry = next;
    }
    _needsSweep = false;
  }
}

/// Consumes an isolated reporting failure without invoking user code again.
void _discardFailureReportingError(Object error, StackTrace stackTrace) {}

final class _ListenerEntry {
  _ListenerEntry(this.listener);

  final VoidCallback listener;
  _ListenerEntry? previous;
  _ListenerEntry? next;
  var removed = false;
}
