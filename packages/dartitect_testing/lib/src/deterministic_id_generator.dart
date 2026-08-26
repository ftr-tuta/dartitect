import 'dart:collection';

import 'package:dartitect/dartitect.dart';

/// Deterministic, instance-owned IDs for tests and reproducible fixtures.
final class DeterministicIdGenerator implements IdGenerator {
  /// Creates a counter generator that returns `prefix-(seed + 1)` first.
  DeterministicIdGenerator({this.prefix = 'id', int seed = 0})
    : _next = seed,
      _sequence = null {
    if (prefix.trim().isEmpty) {
      throw ArgumentError.value(prefix, 'prefix', 'must not be empty');
    }
  }

  /// Creates a finite generator returning [identifiers] in order.
  DeterministicIdGenerator.sequence(Iterable<String> identifiers)
    : prefix = '',
      _next = 0,
      _sequence = Queue<String>.of(identifiers) {
    if (_sequence!.any((identifier) => identifier.trim().isEmpty)) {
      throw ArgumentError.value(
        identifiers,
        'identifiers',
        'must contain only non-empty values',
      );
    }
  }

  /// Static prefix used by counter mode.
  final String prefix;

  int _next;
  final Queue<String>? _sequence;

  @override
  String nextId() {
    final sequence = _sequence;
    if (sequence != null) {
      if (sequence.isEmpty) {
        throw StateError('Deterministic ID sequence is exhausted.');
      }
      return sequence.removeFirst();
    }
    _next += 1;
    return '$prefix-$_next';
  }
}
