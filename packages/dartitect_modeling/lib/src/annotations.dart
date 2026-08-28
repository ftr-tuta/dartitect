/// Marks an immutable value model for Dartitect generation.
///
/// Capabilities are independent: this annotation does not enable JSON,
/// projections, or mappers.
final class DartitectValue {
  /// Creates the passive value marker.
  const DartitectValue();
}

/// Unknown-object-key behavior for generated JSON codecs.
enum DartitectUnknownKeys {
  /// Reject keys that are not declared by the model.
  reject,

  /// Ignore unknown keys at this explicitly annotated boundary.
  ignore,
}

/// Opts one model into generated JSON support.
final class DartitectJson {
  /// Creates an explicit JSON capability.
  const DartitectJson({
    this.unknownKeys = DartitectUnknownKeys.reject,
    this.trusted = false,
  });

  /// Policy for object keys not declared by the model.
  final DartitectUnknownKeys unknownKeys;

  /// Whether the generated codec may omit the standard untrusted-data bounds.
  ///
  /// Trusted mode is never inferred and should be reserved for data produced
  /// and consumed within the same reviewed boundary.
  final bool trusted;
}

/// Opts one model into generated record projections and typed lenses.
final class DartitectProjection {
  /// Creates a named projection capability.
  const DartitectProjection({
    this.name = 'default',
    this.fields = const <String>[],
  });

  /// Stable projection name used in generated symbols and metadata.
  final String name;

  /// Ordered model fields selected into the record.
  ///
  /// An empty list explicitly selects all fields.
  final List<String> fields;
}

/// Opts one source model into an explicit boundary mapper.
final class DartitectMapper {
  /// Creates a mapper targeting [target].
  const DartitectMapper(this.target, {this.bidirectional = false});

  /// Consumer-owned target type.
  final Type target;

  /// Whether a separately validated reverse mapping is requested.
  final bool bidirectional;
}

/// Explicit field metadata shared by JSON, projections, and mappers.
///
/// Renames and converter hooks are consumer decisions. Hook names must refer
/// to consumer-owned static functions; the semantic compiler validates their
/// identity and signatures before rendering.
final class DartitectField {
  /// Creates explicit metadata for one field.
  const DartitectField({
    this.jsonName,
    this.targetName,
    this.decodeWith,
    this.encodeWith,
    this.mapFromWith,
    this.mapToWith,
  });

  /// Serialized JSON key, when it differs from the Dart field name.
  final String? jsonName;

  /// Target field name at a mapper boundary.
  final String? targetName;

  /// Static consumer-owned JSON decoder hook name.
  final String? decodeWith;

  /// Static consumer-owned JSON encoder hook name.
  final String? encodeWith;

  /// Static consumer-owned target-to-model converter hook name.
  final String? mapFromWith;

  /// Static consumer-owned model-to-target converter hook name.
  final String? mapToWith;
}
