/// Severity of a stable modeling diagnostic.
enum ModelingDiagnosticSeverity {
  /// Generation cannot safely continue.
  error,

  /// The source is valid but deserves explicit review.
  warning,

  /// Informational evidence with no required source change.
  info,
}

/// A payload-free, source-addressed modeling diagnostic.
final class ModelingDiagnostic {
  /// Creates a deterministic diagnostic.
  const ModelingDiagnostic({
    required this.rule,
    required this.severity,
    required this.message,
    required this.path,
    this.line,
    this.fixId,
    this.sourceOffset,
    this.sourceLength,
  });

  /// Stable `DTnnnn` rule identifier.
  final String rule;

  /// Stable severity.
  final ModelingDiagnosticSeverity severity;

  /// Actionable message without source values or other sensitive payloads.
  final String message;

  /// Workspace-relative normalized source path.
  final String path;

  /// Optional one-based source line.
  final int? line;

  /// Optional stable semantic-fix identifier.
  final String? fixId;

  /// Analyzer source offset used by editor integrations.
  ///
  /// This location is intentionally omitted from the stable JSON schema.
  final int? sourceOffset;

  /// Analyzer source length used by editor integrations.
  ///
  /// This location is intentionally omitted from the stable JSON schema.
  final int? sourceLength;

  /// Stable machine representation shared by CLI, lints, and MCP.
  Map<String, Object?> toJson() => <String, Object?>{
    'rule': rule,
    'severity': severity.name,
    'message': message,
    'path': path,
    if (line != null) 'line': line,
    if (fixId != null) 'fixId': fixId,
  };
}
