/// Stable finding severity used in human and JSON output.
enum FindingSeverity {
  /// Context that does not affect exit status.
  info,

  /// A concern that makes validation exit with code 1.
  warning,

  /// A definite violation or invalid state.
  error,
}

/// One deterministic scanner or doctor diagnostic.
final class DartitectFinding {
  /// Creates a finding.
  const DartitectFinding({
    required this.code,
    required this.severity,
    required this.message,
    this.path,
    this.line,
    this.column,
    this.evidence,
    this.remediation,
    this.confidence = 1,
  });

  /// Stable machine code.
  final String code;

  /// Finding severity.
  final FindingSeverity severity;

  /// Human-readable description.
  final String message;

  /// Project-relative path, never a home-directory path.
  final String? path;

  /// One-based source line.
  final int? line;

  /// One-based source column.
  final int? column;

  /// Small factual excerpt without secrets.
  final String? evidence;

  /// Actionable next step.
  final String? remediation;

  /// Detector confidence from 0 through 1.
  final double confidence;

  /// JSON representation with stable keys.
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'severity': severity.name,
    'message': message,
    if (path != null) 'path': path,
    if (line != null) 'line': line,
    if (column != null) 'column': column,
    if (evidence != null) 'evidence': evidence,
    if (remediation != null) 'remediation': remediation,
    'confidence': confidence,
  };
}

/// Shared machine-readable command envelope, schema version 1.
final class CommandEnvelope {
  /// Creates an envelope.
  const CommandEnvelope({
    required this.command,
    required this.project,
    this.capabilities = const <String>[],
    this.findings = const <DartitectFinding>[],
    this.violations = const <DartitectFinding>[],
    required this.exitCode,
  });

  /// Envelope schema, versioned independently from package releases.
  static const int schemaVersion = 1;

  /// SDK/tool version.
  static const String sdkVersion = '1.1.0-rc.2';

  /// Command that produced the envelope.
  final String command;

  /// Project facts with relative root.
  final Map<String, Object?> project;

  /// Detected supported capabilities.
  final List<String> capabilities;

  /// Non-rule diagnostics.
  final List<DartitectFinding> findings;

  /// Architecture rule violations.
  final List<DartitectFinding> violations;

  /// Stable process exit code.
  final int exitCode;

  /// Stable JSON representation.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'command': command,
    'sdkVersion': sdkVersion,
    'project': project,
    'capabilities': capabilities,
    'findings': findings.map((finding) => finding.toJson()).toList(),
    'violations': violations.map((finding) => finding.toJson()).toList(),
    'exitCode': exitCode,
  };
}
