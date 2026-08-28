import 'dart:typed_data';

import 'package:dartitect/dartitect.dart';
import 'package:flutter/widgets.dart';

/// Closed structural failures detected before a consumer payload decoder.
enum VersionedRestorationIssue {
  /// The value is not the exact `version` and `payload` envelope.
  invalidEnvelope,

  /// The envelope version is non-positive or newer than the codec.
  unsupportedVersion,

  /// A required one-version migration was not supplied.
  missingMigration,

  /// Encoded output is not supported by Flutter restoration buckets.
  nonRestorablePayload,
}

/// One consumer-owned migration from version `n` to version `n + 1`.
typedef VersionedRestorationMigration<F extends Object> =
    Result<Object?, F> Function(Object? payload);

/// Consumer codecs and migrations for ephemeral Flutter UI restoration.
///
/// This codec is not durable storage. Payloads must not contain credentials,
/// complete domain entities, outbox operations, or repository state.
final class VersionedRestorationCodec<T, F extends Object> {
  /// Creates a codec for a positive [currentVersion].
  VersionedRestorationCodec({
    required this.currentVersion,
    required Object? Function(T value) encodePayload,
    required Result<T, F> Function(Object? payload) decodePayload,
    required F Function(VersionedRestorationIssue issue) mapIssue,
    Map<int, VersionedRestorationMigration<F>>? migrations,
  }) : _encodePayload = encodePayload,
       _decodePayload = decodePayload,
       _mapIssue = mapIssue,
       _migrations = Map<int, VersionedRestorationMigration<F>>.unmodifiable(
         migrations ?? <int, VersionedRestorationMigration<F>>{},
       ) {
    if (currentVersion <= 0) {
      throw ArgumentError.value(
        currentVersion,
        'currentVersion',
        'Must be positive.',
      );
    }
    for (final version in _migrations.keys) {
      if (version <= 0 || version >= currentVersion) {
        throw ArgumentError.value(
          version,
          'migrations',
          'Migration keys must be supported versions below currentVersion.',
        );
      }
    }
  }

  /// Current envelope version written by [encode].
  final int currentVersion;

  final Object? Function(T value) _encodePayload;
  final Result<T, F> Function(Object? payload) _decodePayload;
  final F Function(VersionedRestorationIssue issue) _mapIssue;
  final Map<int, VersionedRestorationMigration<F>> _migrations;

  /// Encodes [value] into the exact restoration envelope.
  Map<String, Object?> encode(T value) {
    final payload = _encodePayload(value);
    if (!_isRestorable(payload)) {
      throw VersionedRestorationEncodingException(
        VersionedRestorationIssue.nonRestorablePayload,
      );
    }
    return <String, Object?>{'version': currentVersion, 'payload': payload};
  }

  /// Decodes an envelope, applying every explicit migration in order.
  Result<T, F> decode(Object? encoded) {
    if (encoded is! Map<Object?, Object?> ||
        encoded.length != 2 ||
        !encoded.containsKey('version') ||
        !encoded.containsKey('payload')) {
      return Err<F>(
        _mapIssue(VersionedRestorationIssue.invalidEnvelope),
        StackTrace.empty,
      );
    }
    final rawVersion = encoded['version'];
    if (rawVersion is! int || rawVersion <= 0 || rawVersion > currentVersion) {
      return Err<F>(
        _mapIssue(VersionedRestorationIssue.unsupportedVersion),
        StackTrace.empty,
      );
    }
    var version = rawVersion;
    var payload = encoded['payload'];
    while (version < currentVersion) {
      final migration = _migrations[version];
      if (migration == null) {
        return Err<F>(
          _mapIssue(VersionedRestorationIssue.missingMigration),
          StackTrace.empty,
        );
      }
      final migrated = migration(payload);
      switch (migrated) {
        case Ok<dynamic>(:final value):
          payload = value;
        case Err<Object>(:final failure, :final stackTrace):
          return Err<F>(failure as F, stackTrace);
      }
      version += 1;
    }
    return _decodePayload(payload);
  }

  static bool _isRestorable(Object? value, [Set<Object>? seen]) {
    if (value == null ||
        value is bool ||
        value is int ||
        value is double ||
        value is String ||
        value is Uint8List) {
      return true;
    }
    final active = seen ?? <Object>{};
    if (value is List<Object?>) {
      if (!active.add(value)) return false;
      final valid = value.every((item) => _isRestorable(item, active));
      active.remove(value);
      return valid;
    }
    if (value is Map<Object?, Object?>) {
      if (!active.add(value)) return false;
      final valid = value.entries.every(
        (entry) => entry.key is String && _isRestorable(entry.value, active),
      );
      active.remove(value);
      return valid;
    }
    return false;
  }
}

/// Encoding failure for a value Flutter cannot place in a restoration bucket.
final class VersionedRestorationEncodingException implements Exception {
  /// Creates an encoding failure for [issue].
  const VersionedRestorationEncodingException(this.issue);

  /// Closed structural encoding issue.
  final VersionedRestorationIssue issue;

  @override
  String toString() => 'VersionedRestorationEncodingException(${issue.name})';
}

/// Flutter restoration property backed by [VersionedRestorationCodec].
///
/// Decode failures retain [lastFailure] and restore [initialValue]. The
/// enclosing [RestorationMixin] remains the owner of bucket registration.
final class RestorableVersionedValue<T, F extends Object>
    extends RestorableValue<T> {
  /// Creates a property with a safe consumer-owned fallback.
  RestorableVersionedValue({
    required this.initialValue,
    required this.codec,
    bool Function(T previous, T next)? equality,
  }) : _equality = equality ?? _defaultEquality;

  /// State used when no bucket exists or decoding fails.
  final T initialValue;

  /// Consumer-owned codec and migration registry.
  final VersionedRestorationCodec<T, F> codec;

  final bool Function(T previous, T next) _equality;

  /// Latest typed restoration failure, cleared after a successful decode.
  F? lastFailure;

  @override
  T createDefaultValue() => initialValue;

  @override
  T fromPrimitives(Object? data) {
    final decoded = codec.decode(data);
    return switch (decoded) {
      Ok<dynamic>(:final value) => _success(value as T),
      Err<Object>(:final failure) => _fallback(failure as F),
    };
  }

  @override
  Object toPrimitives() => codec.encode(value);

  @override
  void didUpdateValue(T? oldValue) {
    if (oldValue == null || !_equality(oldValue, value)) notifyListeners();
  }

  T _success(T value) {
    lastFailure = null;
    return value;
  }

  T _fallback(F failure) {
    lastFailure = failure;
    return initialValue;
  }

  static bool _defaultEquality<T>(T previous, T next) => previous == next;
}
