/// Opt-in capabilities validated for one model.
enum ModelingCapability {
  /// Immutable value semantics.
  value,

  /// Explicit JSON codec generation.
  json,

  /// Record projection and lens generation.
  projection,

  /// Pure boundary mapper generation.
  mapper,
}

/// One generic parameter retained without renderer-specific syntax.
final class ModelingTypeParameterIr {
  /// Creates a validated type parameter.
  const ModelingTypeParameterIr({required this.name, this.bound});

  /// Declared parameter name.
  final String name;

  /// Explicit semantic bound, when present.
  final ModelingTypeIr? bound;
}

/// Semantic type shape retained by the public renderer-neutral IR.
final class ModelingTypeIr {
  /// Creates a canonical type description.
  const ModelingTypeIr({
    required this.displayName,
    required this.libraryUri,
    required this.nullable,
    this.typeArguments = const <ModelingTypeIr>[],
    this.isRecord = false,
  });

  /// Canonical source-facing name.
  final String displayName;

  /// Declaring library identity, or an empty string for structural types.
  final String libraryUri;

  /// Whether the type admits null.
  final bool nullable;

  /// Validated generic arguments.
  final List<ModelingTypeIr> typeArguments;

  /// Whether this is a record type.
  final bool isRecord;
}

/// Validated field and explicit boundary metadata.
final class ModelingFieldIr {
  /// Creates a field IR node.
  const ModelingFieldIr({
    required this.name,
    required this.type,
    this.jsonName,
    this.targetName,
    this.decodeHook,
    this.encodeHook,
    this.mapFromHook,
    this.mapToHook,
    this.isRequiredNamed = false,
    this.hasDefault = false,
    this.defaultCode,
  });

  /// Declared Dart field name.
  final String name;

  /// Resolved semantic type.
  final ModelingTypeIr type;

  /// Explicit JSON key override.
  final String? jsonName;

  /// Explicit mapper target-field override.
  final String? targetName;

  /// Consumer-owned static JSON decode hook.
  final String? decodeHook;

  /// Consumer-owned static JSON encode hook.
  final String? encodeHook;

  /// Consumer-owned static target-to-model hook.
  final String? mapFromHook;

  /// Consumer-owned static model-to-target hook.
  final String? mapToHook;

  /// Whether callers must provide this named constructor field.
  final bool isRequiredNamed;

  /// Whether the primary constructor declares a default.
  final bool hasDefault;

  /// Canonical source spelling of the declared default, when present.
  final String? defaultCode;
}

/// Validated JSON capability.
final class ModelingJsonIr {
  /// Creates validated JSON configuration.
  const ModelingJsonIr({
    required this.rejectUnknownKeys,
    required this.trusted,
  });

  /// Whether undeclared keys are rejected.
  final bool rejectUnknownKeys;

  /// Whether explicit trusted mode disables untrusted limits.
  final bool trusted;
}

/// Validated record projection.
final class ModelingProjectionIr {
  /// Creates one validated projection.
  const ModelingProjectionIr({required this.name, required this.fields});

  /// Stable projection name.
  final String name;

  /// Source field names in record order.
  final List<String> fields;
}

/// Compatibility outcome for one mapper field.
enum ModelingCompatibility {
  /// Source and target are semantically assignable without information loss.
  assignableLossless,

  /// A validated consumer converter makes the boundary explicit.
  explicitConverter,

  /// Automatic mapping is unsafe and no valid converter was supplied.
  rejected,
}

/// Explainable mapper compatibility decision.
final class ModelingCompatibilityDecisionIr {
  /// Creates one explainable compatibility decision.
  const ModelingCompatibilityDecisionIr({
    required this.sourceField,
    required this.targetField,
    required this.compatibility,
    required this.reason,
  });

  /// Source-model field.
  final String sourceField;

  /// Target-boundary field.
  final String targetField;

  /// Validated compatibility class.
  final ModelingCompatibility compatibility;

  /// Stable payload-free explanation.
  final String reason;
}

/// Validated mapper capability.
final class ModelingMapperIr {
  /// Creates a validated mapper capability.
  const ModelingMapperIr({
    required this.targetType,
    required this.bidirectional,
    required this.decisions,
  });

  /// Resolved consumer-owned target type.
  final ModelingTypeIr targetType;

  /// Whether reverse mapping was independently validated.
  final bool bidirectional;

  /// Per-field mapping decisions.
  final List<ModelingCompatibilityDecisionIr> decisions;
}

/// One validated model declaration.
final class ModelingModelIr {
  /// Creates one validated model.
  const ModelingModelIr({
    required this.name,
    required this.sourcePath,
    required this.fields,
    required this.capabilities,
    this.typeParameters = const <ModelingTypeParameterIr>[],
    this.json,
    this.projections = const <ModelingProjectionIr>[],
    this.mappers = const <ModelingMapperIr>[],
    this.isConst = false,
  });

  /// Declared class name.
  final String name;

  /// Workspace-relative unit containing the declaration, including parts.
  final String sourcePath;

  /// Generic declaration in source order.
  final List<ModelingTypeParameterIr> typeParameters;

  /// Primary-constructor fields in stable order.
  final List<ModelingFieldIr> fields;

  /// Independently enabled capabilities.
  final Set<ModelingCapability> capabilities;

  /// JSON configuration, when explicitly enabled.
  final ModelingJsonIr? json;

  /// Validated projections.
  final List<ModelingProjectionIr> projections;

  /// Validated boundary mappers.
  final List<ModelingMapperIr> mappers;

  /// Whether the primary constructor is const.
  final bool isConst;
}

/// One source library and its deterministic generated part.
final class ModelingLibraryIr {
  /// Creates one validated source library.
  const ModelingLibraryIr({
    required this.uri,
    required this.path,
    required this.outputPath,
    required this.models,
  });

  /// Analyzer library identity.
  final String uri;

  /// Workspace-relative defining source path.
  final String path;

  /// Workspace-relative deterministic output part.
  final String outputPath;

  /// Models declared across the defining unit and its parts.
  final List<ModelingModelIr> models;
}

/// Complete validated workspace input for renderers and verification.
final class ModelingWorkspaceIr {
  /// Creates a complete validated workspace IR.
  const ModelingWorkspaceIr({required this.root, required this.libraries});

  /// Canonical workspace root.
  final String root;

  /// Libraries in deterministic path order.
  final List<ModelingLibraryIr> libraries;
}
