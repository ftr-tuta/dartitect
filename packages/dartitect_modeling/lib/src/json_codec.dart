import 'dart:collection';

import 'package:dartitect/dartitect.dart';

import 'value_collections.dart';

/// Stable, payload-free category for an expected JSON failure.
enum DartitectJsonFailureKind {
  /// An object was required.
  expectedObject,

  /// An array was required.
  expectedArray,

  /// A string was required.
  expectedString,

  /// A boolean was required.
  expectedBoolean,

  /// A mathematically integral JSON number was required.
  expectedInteger,

  /// A JSON number was required.
  expectedNumber,

  /// A JSON number safely representable as `double` was required.
  expectedDouble,

  /// JSON `null` was required.
  expectedNull,

  /// An object key was not declared by the codec.
  unknownKey,

  /// A required object key was absent.
  missingKey,

  /// A JSON object retained a non-string key.
  nonStringKey,

  /// An array could not be converted to a set without information loss.
  duplicateSetItem,

  /// A number was `NaN` or infinite and therefore was not JSON.
  nonFiniteNumber,

  /// A value did not belong to the JSON data model.
  unsupportedValue,

  /// The explicitly selected depth limit was exceeded.
  depthLimitExceeded,

  /// The explicitly selected per-collection item limit was exceeded.
  collectionLimitExceeded,

  /// The explicitly selected total-node limit was exceeded.
  nodeLimitExceeded,

  /// A cyclic collection graph was rejected.
  cyclicValue,

  /// A consumer-owned explicit codec rejected the value.
  customCodec,
}

/// One payload-free segment in a JSON failure path.
sealed class DartitectJsonPathSegment extends ValueEquality {
  const DartitectJsonPathSegment();

  /// Stable machine representation.
  Map<String, Object?> toJson();
}

/// A declared or encountered object key.
final class DartitectJsonKeyPathSegment extends DartitectJsonPathSegment {
  /// Creates a key segment.
  const DartitectJsonKeyPathSegment(this.key);

  /// Object key. No associated input value is retained.
  final String key;

  @override
  Iterable<Object?> get equalityFields => <Object?>[key];

  @override
  Map<String, Object?> toJson() => <String, Object?>{'key': key};
}

/// A zero-based array index.
final class DartitectJsonIndexPathSegment extends DartitectJsonPathSegment {
  /// Creates an index segment.
  const DartitectJsonIndexPathSegment(this.index);

  /// Zero-based index. No associated input value is retained.
  final int index;

  @override
  Iterable<Object?> get equalityFields => <Object?>[index];

  @override
  Map<String, Object?> toJson() => <String, Object?>{'index': index};
}

/// Immutable location of a JSON failure.
final class DartitectJsonPath extends ValueEquality {
  DartitectJsonPath._(Iterable<DartitectJsonPathSegment> segments)
    : segments = List<DartitectJsonPathSegment>.unmodifiable(segments);

  /// Root JSON location.
  static final DartitectJsonPath root = DartitectJsonPath._(
    const <DartitectJsonPathSegment>[],
  );

  /// Ordered key/index segments. Input values are never retained.
  final List<DartitectJsonPathSegment> segments;

  /// Returns a child object-key path.
  DartitectJsonPath key(String key) => DartitectJsonPath._(
    <DartitectJsonPathSegment>[...segments, DartitectJsonKeyPathSegment(key)],
  );

  /// Returns a child array-index path.
  DartitectJsonPath index(int index) =>
      DartitectJsonPath._(<DartitectJsonPathSegment>[
        ...segments,
        DartitectJsonIndexPathSegment(index),
      ]);

  /// Stable machine representation.
  List<Map<String, Object?>> toJson() => <Map<String, Object?>>[
    for (final segment in segments) segment.toJson(),
  ];

  @override
  Iterable<Object?> get equalityFields => <Object?>[segments];
}

/// Expected, typed JSON failure without the rejected input payload.
final class DartitectJsonFailure extends ValueEquality implements Exception {
  /// Creates a failure at [path].
  const DartitectJsonFailure({required this.kind, required this.path});

  /// Typed failure category.
  final DartitectJsonFailureKind kind;

  /// Payload-free structural location.
  final DartitectJsonPath path;

  /// Creates a typed failed result with an empty stack trace.
  static Result<T, DartitectJsonFailure> result<T>(
    DartitectJsonFailureKind kind,
    DartitectJsonPath path,
  ) => Err<DartitectJsonFailure>(
    DartitectJsonFailure(kind: kind, path: path),
    StackTrace.empty,
  );

  /// Stable machine representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'path': path.toJson(),
  };

  @override
  Iterable<Object?> get equalityFields => <Object?>[kind, path];

  @override
  String toString() => 'DartitectJsonFailure(${kind.name}, ${path.toJson()})';
}

/// Explicit traversal limits for JSON input and generated output.
final class DartitectJsonLimits extends ValueEquality {
  /// Standard limits for untrusted data: depth 64, 10,000 collection items,
  /// and 100,000 total nodes.
  const DartitectJsonLimits.untrusted()
    : maxDepth = 64,
      maxCollectionItems = 10000,
      maxTotalNodes = 100000,
      trusted = false;

  /// Explicit custom limits for a reviewed boundary.
  const DartitectJsonLimits.custom({
    required int maxDepth,
    required int maxCollectionItems,
    required int maxTotalNodes,
  }) : assert(maxDepth >= 0),
       assert(maxCollectionItems >= 0),
       assert(maxTotalNodes >= 1),
       maxDepth = maxDepth,
       maxCollectionItems = maxCollectionItems,
       maxTotalNodes = maxTotalNodes,
       trusted = false;

  /// Explicit trusted mode without numeric traversal limits.
  ///
  /// JSON shape, finite-number, and cycle validation remain enabled.
  const DartitectJsonLimits.trusted()
    : maxDepth = null,
      maxCollectionItems = null,
      maxTotalNodes = null,
      trusted = true;

  /// Maximum root-relative collection depth, or `null` in trusted mode.
  final int? maxDepth;

  /// Maximum entries retained by any one list or map.
  final int? maxCollectionItems;

  /// Maximum scalar and collection nodes in the complete graph.
  final int? maxTotalNodes;

  /// Whether numeric limits were explicitly disabled.
  final bool trusted;

  @override
  Iterable<Object?> get equalityFields => <Object?>[
    maxDepth,
    maxCollectionItems,
    maxTotalNodes,
    trusted,
  ];
}

/// Composable, typed codec for one JSON boundary value.
abstract class DartitectJsonCodec<T> {
  /// Allows constant generated and scalar codecs with an explicit default.
  const DartitectJsonCodec({
    this.defaultLimits = const DartitectJsonLimits.untrusted(),
  });

  /// Limits selected when a boundary call does not provide an override.
  final DartitectJsonLimits defaultLimits;

  /// Validates the complete graph and decodes it from the root.
  Result<T, DartitectJsonFailure> decode(
    Object? input, {
    DartitectJsonLimits? limits,
  }) {
    final failure = _validateJsonGraph(input, limits ?? defaultLimits);
    if (failure != null) {
      return Err<DartitectJsonFailure>(failure, StackTrace.empty);
    }
    return decodeValue(input, DartitectJsonPath.root);
  }

  /// Encodes and then validates the complete generated graph.
  Result<Object?, DartitectJsonFailure> encode(
    T value, {
    DartitectJsonLimits? limits,
  }) {
    final encoded = encodeValue(value, DartitectJsonPath.root);
    return switch (encoded) {
      Err<Object>(:final failure, :final stackTrace) =>
        Err<DartitectJsonFailure>(failure as DartitectJsonFailure, stackTrace),
      Ok<dynamic>(:final value) => _validatedEncoded(
        value,
        limits ?? defaultLimits,
      ),
    };
  }

  /// Decodes one already traversal-validated nested value.
  ///
  /// Generated codecs use this method for composition. Boundary callers use
  /// [decode] so limits apply exactly once to the complete graph.
  Result<T, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  );

  /// Encodes one nested value; root validation occurs in [encode].
  Result<Object?, DartitectJsonFailure> encodeValue(
    T value,
    DartitectJsonPath path,
  );
}

Result<Object?, DartitectJsonFailure> _validatedEncoded(
  Object? value,
  DartitectJsonLimits limits,
) {
  final failure = _validateJsonGraph(value, limits);
  return failure == null
      ? Ok<Object?>(value)
      : Err<DartitectJsonFailure>(failure, StackTrace.empty);
}

/// Helpers used by generated object codecs after root traversal validation.
abstract final class DartitectJsonObjectSupport {
  /// Validates object shape, declared keys, and required keys.
  static Result<Map<String, Object?>, DartitectJsonFailure> decodeObject(
    Object? input,
    DartitectJsonPath path, {
    required Set<String> allowedKeys,
    required Set<String> requiredKeys,
    bool rejectUnknownKeys = true,
  }) {
    if (input is! Map<Object?, Object?>) {
      return DartitectJsonFailure.result<Map<String, Object?>>(
        DartitectJsonFailureKind.expectedObject,
        path,
      );
    }
    final object = <String, Object?>{};
    for (final entry in input.entries) {
      final key = entry.key;
      if (key is! String) {
        return DartitectJsonFailure.result<Map<String, Object?>>(
          DartitectJsonFailureKind.nonStringKey,
          path,
        );
      }
      object[key] = entry.value;
    }
    if (rejectUnknownKeys) {
      final ordered =
          object.keys.where((key) => !allowedKeys.contains(key)).toList()
            ..sort();
      if (ordered.isNotEmpty) {
        return DartitectJsonFailure.result<Map<String, Object?>>(
          DartitectJsonFailureKind.unknownKey,
          path.key(ordered.first),
        );
      }
    }
    final orderedMissing =
        requiredKeys.where((key) => !object.containsKey(key)).toList()..sort();
    if (orderedMissing.isNotEmpty) {
      return DartitectJsonFailure.result<Map<String, Object?>>(
        DartitectJsonFailureKind.missingKey,
        path.key(orderedMissing.first),
      );
    }
    return Ok<Map<String, Object?>>(Map<String, Object?>.unmodifiable(object));
  }
}

/// Explicit JSON string codec.
final class DartitectStringJsonCodec extends DartitectJsonCodec<String> {
  /// Creates a string codec.
  const DartitectStringJsonCodec();

  @override
  Result<String, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) => input is String
      ? Ok<String>(input)
      : DartitectJsonFailure.result<String>(
          DartitectJsonFailureKind.expectedString,
          path,
        );

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    String value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value);
}

/// Explicit JSON boolean codec.
final class DartitectBoolJsonCodec extends DartitectJsonCodec<bool> {
  /// Creates a boolean codec.
  const DartitectBoolJsonCodec();

  @override
  Result<bool, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) => input is bool
      ? Ok<bool>(input)
      : DartitectJsonFailure.result<bool>(
          DartitectJsonFailureKind.expectedBoolean,
          path,
        );

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    bool value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value);
}

/// Explicit JSON integer codec.
final class DartitectIntJsonCodec extends DartitectJsonCodec<int> {
  /// Creates an integer codec.
  const DartitectIntJsonCodec();

  @override
  Result<int, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) {
    if (input is int) return Ok<int>(input);
    if (input is double &&
        input.isFinite &&
        input == input.truncateToDouble()) {
      final integer = input.toInt();
      if (integer.toDouble() == input) return Ok<int>(integer);
    }
    return DartitectJsonFailure.result<int>(
      DartitectJsonFailureKind.expectedInteger,
      path,
    );
  }

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    int value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value);
}

/// Explicit JSON number codec retaining `int` versus `double`.
final class DartitectNumJsonCodec extends DartitectJsonCodec<num> {
  /// Creates a number codec.
  const DartitectNumJsonCodec();

  @override
  Result<num, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) => input is num
      ? Ok<num>(input)
      : DartitectJsonFailure.result<num>(
          DartitectJsonFailureKind.expectedNumber,
          path,
        );

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    num value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value);
}

/// Explicit JSON double codec with only lossless integer widening.
final class DartitectDoubleJsonCodec extends DartitectJsonCodec<double> {
  /// Creates a double codec.
  const DartitectDoubleJsonCodec();

  @override
  Result<double, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) {
    if (input is double) return Ok<double>(input);
    if (input is int) {
      final converted = input.toDouble();
      if (converted.isFinite && converted.toInt() == input) {
        return Ok<double>(converted);
      }
    }
    return DartitectJsonFailure.result<double>(
      DartitectJsonFailureKind.expectedDouble,
      path,
    );
  }

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    double value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value);
}

/// Explicit JSON null codec.
final class DartitectNullJsonCodec extends DartitectJsonCodec<Null> {
  /// Creates a null codec.
  const DartitectNullJsonCodec();

  @override
  Result<Null, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) => input == null
      ? const Ok<Null>(null)
      : DartitectJsonFailure.result<Null>(
          DartitectJsonFailureKind.expectedNull,
          path,
        );

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    Null value,
    DartitectJsonPath path,
  ) => const Ok<Object?>(null);
}

/// Explicit codec for any already validated JSON value.
final class DartitectJsonValueCodec extends DartitectJsonCodec<Object?> {
  /// Creates a JSON-value codec.
  const DartitectJsonValueCodec();

  @override
  Result<Object?, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) => Ok<Object?>(input);

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    Object? value,
    DartitectJsonPath path,
  ) => Ok<Object?>(value);
}

/// Explicit nullable composition; nullability is never inferred at runtime.
final class DartitectNullableJsonCodec<T> extends DartitectJsonCodec<T?> {
  /// Creates a nullable wrapper around [inner].
  const DartitectNullableJsonCodec(this.inner);

  /// Codec used for non-null values.
  final DartitectJsonCodec<T> inner;

  @override
  Result<T?, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) => input == null ? Ok<T?>(null) : inner.decodeValue(input, path);

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    T? value,
    DartitectJsonPath path,
  ) => value == null ? const Ok<Object?>(null) : inner.encodeValue(value, path);
}

/// JSON array codec for [ImmutableValueList].
final class DartitectImmutableValueListJsonCodec<T>
    extends DartitectJsonCodec<ImmutableValueList<T>> {
  /// Creates an immutable-list codec.
  const DartitectImmutableValueListJsonCodec(this.itemCodec);

  /// Explicit item codec.
  final DartitectJsonCodec<T> itemCodec;

  @override
  Result<ImmutableValueList<T>, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) {
    if (input is! List<Object?>) {
      return DartitectJsonFailure.result<ImmutableValueList<T>>(
        DartitectJsonFailureKind.expectedArray,
        path,
      );
    }
    final values = <T>[];
    for (var index = 0; index < input.length; index += 1) {
      final decoded = itemCodec.decodeValue(input[index], path.index(index));
      switch (decoded) {
        case Ok<dynamic>(:final value):
          values.add(value as T);
        case Err<Object>(:final failure, :final stackTrace):
          return Err<DartitectJsonFailure>(
            failure as DartitectJsonFailure,
            stackTrace,
          );
      }
    }
    return Ok<ImmutableValueList<T>>(ImmutableValueList<T>(values));
  }

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    ImmutableValueList<T> value,
    DartitectJsonPath path,
  ) {
    final output = <Object?>[];
    var index = 0;
    for (final item in value) {
      final encoded = itemCodec.encodeValue(item, path.index(index));
      switch (encoded) {
        case Ok<dynamic>(:final value):
          output.add(value);
        case Err<Object>(:final failure, :final stackTrace):
          return Err<DartitectJsonFailure>(
            failure as DartitectJsonFailure,
            stackTrace,
          );
      }
      index += 1;
    }
    return Ok<Object?>(List<Object?>.unmodifiable(output));
  }
}

/// JSON array codec for [ImmutableValueSet].
final class DartitectImmutableValueSetJsonCodec<T>
    extends DartitectJsonCodec<ImmutableValueSet<T>> {
  /// Creates an immutable-set codec.
  const DartitectImmutableValueSetJsonCodec(this.itemCodec);

  /// Explicit item codec.
  final DartitectJsonCodec<T> itemCodec;

  @override
  Result<ImmutableValueSet<T>, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) {
    if (input is! List<Object?>) {
      return DartitectJsonFailure.result<ImmutableValueSet<T>>(
        DartitectJsonFailureKind.expectedArray,
        path,
      );
    }
    final values = <T>[];
    final hashes = <int, List<T>>{};
    for (var index = 0; index < input.length; index += 1) {
      final decoded = itemCodec.decodeValue(input[index], path.index(index));
      switch (decoded) {
        case Ok<dynamic>(:final value):
          final item = value as T;
          final hash = ValueEquality.hash(item);
          final bucket = hashes.putIfAbsent(hash, () => <T>[]);
          if (bucket.any(
            (candidate) => ValueEquality.equals(candidate, item),
          )) {
            return DartitectJsonFailure.result<ImmutableValueSet<T>>(
              DartitectJsonFailureKind.duplicateSetItem,
              path.index(index),
            );
          }
          bucket.add(item);
          values.add(item);
        case Err<Object>(:final failure, :final stackTrace):
          return Err<DartitectJsonFailure>(
            failure as DartitectJsonFailure,
            stackTrace,
          );
      }
    }
    return Ok<ImmutableValueSet<T>>(ImmutableValueSet<T>(values));
  }

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    ImmutableValueSet<T> value,
    DartitectJsonPath path,
  ) {
    final output = <Object?>[];
    var index = 0;
    for (final item in value) {
      final encoded = itemCodec.encodeValue(item, path.index(index));
      switch (encoded) {
        case Ok<dynamic>(:final value):
          output.add(value);
        case Err<Object>(:final failure, :final stackTrace):
          return Err<DartitectJsonFailure>(
            failure as DartitectJsonFailure,
            stackTrace,
          );
      }
      index += 1;
    }
    return Ok<Object?>(List<Object?>.unmodifiable(output));
  }
}

/// JSON object codec for string-keyed [ImmutableValueMap].
final class DartitectImmutableValueMapJsonCodec<V>
    extends DartitectJsonCodec<ImmutableValueMap<String, V>> {
  /// Creates an immutable-map codec.
  const DartitectImmutableValueMapJsonCodec(this.valueCodec);

  /// Explicit value codec.
  final DartitectJsonCodec<V> valueCodec;

  @override
  Result<ImmutableValueMap<String, V>, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) {
    if (input is! Map<Object?, Object?>) {
      return DartitectJsonFailure.result<ImmutableValueMap<String, V>>(
        DartitectJsonFailureKind.expectedObject,
        path,
      );
    }
    final entries = <String, Object?>{};
    for (final entry in input.entries) {
      final key = entry.key;
      if (key is! String) {
        return DartitectJsonFailure.result<ImmutableValueMap<String, V>>(
          DartitectJsonFailureKind.nonStringKey,
          path,
        );
      }
      entries[key] = entry.value;
    }
    final keys = entries.keys.toList()..sort();
    final output = <String, V>{};
    for (final key in keys) {
      final decoded = valueCodec.decodeValue(entries[key], path.key(key));
      switch (decoded) {
        case Ok<dynamic>(:final value):
          output[key] = value as V;
        case Err<Object>(:final failure, :final stackTrace):
          return Err<DartitectJsonFailure>(
            failure as DartitectJsonFailure,
            stackTrace,
          );
      }
    }
    return Ok<ImmutableValueMap<String, V>>(
      ImmutableValueMap<String, V>(output),
    );
  }

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    ImmutableValueMap<String, V> value,
    DartitectJsonPath path,
  ) {
    final keys = value.keys.toList()..sort();
    final output = <String, Object?>{};
    for (final key in keys) {
      final encoded = valueCodec.encodeValue(value[key] as V, path.key(key));
      switch (encoded) {
        case Ok<dynamic>(:final value):
          output[key] = value;
        case Err<Object>(:final failure, :final stackTrace):
          return Err<DartitectJsonFailure>(
            failure as DartitectJsonFailure,
            stackTrace,
          );
      }
    }
    return Ok<Object?>(Map<String, Object?>.unmodifiable(output));
  }
}

/// Consumer-owned explicit JSON decoder hook.
typedef DartitectJsonDecodeHook<T> = Result<T, DartitectJsonFailure> Function(
  Object? input,
  DartitectJsonPath path,
);

/// Consumer-owned explicit JSON encoder hook.
typedef DartitectJsonEncodeHook<T> =
    Result<Object?, DartitectJsonFailure> Function(
      T value,
      DartitectJsonPath path,
    );

/// Codec backed only by explicit consumer-owned hooks.
final class DartitectHookJsonCodec<T> extends DartitectJsonCodec<T> {
  /// Creates a codec from a reviewed decoder/encoder pair.
  const DartitectHookJsonCodec({
    required DartitectJsonDecodeHook<T> decode,
    required DartitectJsonEncodeHook<T> encode,
  }) : _decode = decode,
       _encode = encode;

  final DartitectJsonDecodeHook<T> _decode;
  final DartitectJsonEncodeHook<T> _encode;

  @override
  Result<T, DartitectJsonFailure> decodeValue(
    Object? input,
    DartitectJsonPath path,
  ) => _decode(input, path);

  @override
  Result<Object?, DartitectJsonFailure> encodeValue(
    T value,
    DartitectJsonPath path,
  ) => _encode(value, path);
}

/// Explicit scalar and immutable-collection codec constructors.
abstract final class DartitectJsonCodecs {
  /// JSON string codec.
  static const DartitectStringJsonCodec string = DartitectStringJsonCodec();

  /// JSON boolean codec.
  static const DartitectBoolJsonCodec boolean = DartitectBoolJsonCodec();

  /// JSON integer codec.
  static const DartitectIntJsonCodec integer = DartitectIntJsonCodec();

  /// JSON number codec retaining the numeric value.
  static const DartitectNumJsonCodec number = DartitectNumJsonCodec();

  /// JSON double codec with lossless integer widening.
  static const DartitectDoubleJsonCodec doubleValue =
      DartitectDoubleJsonCodec();

  /// JSON null codec.
  static const DartitectNullJsonCodec nullValue = DartitectNullJsonCodec();

  /// Codec accepting any already validated JSON value.
  static const DartitectJsonValueCodec jsonValue = DartitectJsonValueCodec();

  /// Explicit nullable composition.
  static DartitectNullableJsonCodec<T> nullable<T>(
    DartitectJsonCodec<T> inner,
  ) => DartitectNullableJsonCodec<T>(inner);

  /// Explicit immutable-list composition.
  static DartitectImmutableValueListJsonCodec<T> immutableList<T>(
    DartitectJsonCodec<T> item,
  ) => DartitectImmutableValueListJsonCodec<T>(item);

  /// Explicit immutable-set composition.
  static DartitectImmutableValueSetJsonCodec<T> immutableSet<T>(
    DartitectJsonCodec<T> item,
  ) => DartitectImmutableValueSetJsonCodec<T>(item);

  /// Explicit string-keyed immutable-map composition.
  static DartitectImmutableValueMapJsonCodec<V> immutableMap<V>(
    DartitectJsonCodec<V> value,
  ) => DartitectImmutableValueMapJsonCodec<V>(value);
}

DartitectJsonFailure? _validateJsonGraph(
  Object? root,
  DartitectJsonLimits limits,
) {
  final active = HashSet<Object>.identity();
  final stack = <_JsonTraversalFrame>[
    _JsonTraversalFrame.enter(root, DartitectJsonPath.root, 0),
  ];
  var nodes = 0;
  while (stack.isNotEmpty) {
    final frame = stack.removeLast();
    if (frame.exit) {
      active.remove(frame.value);
      continue;
    }
    nodes += 1;
    final totalLimit = limits.maxTotalNodes;
    if (totalLimit != null && nodes > totalLimit) {
      return DartitectJsonFailure(
        kind: DartitectJsonFailureKind.nodeLimitExceeded,
        path: frame.path,
      );
    }
    final depthLimit = limits.maxDepth;
    if (depthLimit != null && frame.depth > depthLimit) {
      return DartitectJsonFailure(
        kind: DartitectJsonFailureKind.depthLimitExceeded,
        path: frame.path,
      );
    }
    final value = frame.value;
    if (value == null || value is String || value is bool) continue;
    if (value is num) {
      if (!value.isFinite) {
        return DartitectJsonFailure(
          kind: DartitectJsonFailureKind.nonFiniteNumber,
          path: frame.path,
        );
      }
      continue;
    }
    if (value is List<Object?>) {
      final failure = _enterCollection(
        value,
        value.length,
        frame,
        limits,
        active,
        stack,
      );
      if (failure != null) return failure;
      for (var index = value.length - 1; index >= 0; index -= 1) {
        stack.add(
          _JsonTraversalFrame.enter(
            value[index],
            frame.path.index(index),
            frame.depth + 1,
          ),
        );
      }
      continue;
    }
    if (value is Map<Object?, Object?>) {
      final failure = _enterCollection(
        value,
        value.length,
        frame,
        limits,
        active,
        stack,
      );
      if (failure != null) return failure;
      final entries = value.entries.toList(growable: false);
      for (var index = entries.length - 1; index >= 0; index -= 1) {
        final key = entries[index].key;
        if (key is! String) {
          return DartitectJsonFailure(
            kind: DartitectJsonFailureKind.nonStringKey,
            path: frame.path,
          );
        }
        stack.add(
          _JsonTraversalFrame.enter(
            entries[index].value,
            frame.path.key(key),
            frame.depth + 1,
          ),
        );
      }
      continue;
    }
    return DartitectJsonFailure(
      kind: DartitectJsonFailureKind.unsupportedValue,
      path: frame.path,
    );
  }
  return null;
}

DartitectJsonFailure? _enterCollection(
  Object value,
  int length,
  _JsonTraversalFrame frame,
  DartitectJsonLimits limits,
  Set<Object> active,
  List<_JsonTraversalFrame> stack,
) {
  final itemLimit = limits.maxCollectionItems;
  if (itemLimit != null && length > itemLimit) {
    return DartitectJsonFailure(
      kind: DartitectJsonFailureKind.collectionLimitExceeded,
      path: frame.path,
    );
  }
  if (!active.add(value)) {
    return DartitectJsonFailure(
      kind: DartitectJsonFailureKind.cyclicValue,
      path: frame.path,
    );
  }
  stack.add(_JsonTraversalFrame.exit(value, frame.path, frame.depth));
  return null;
}

final class _JsonTraversalFrame {
  const _JsonTraversalFrame.enter(this.value, this.path, this.depth)
    : exit = false;

  const _JsonTraversalFrame.exit(this.value, this.path, this.depth)
    : exit = true;

  final Object? value;
  final DartitectJsonPath path;
  final int depth;
  final bool exit;
}
