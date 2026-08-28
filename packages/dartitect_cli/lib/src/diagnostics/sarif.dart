import 'models.dart';

/// Stable SARIF 2.1.0 projection of one Dartitect command envelope.
final class DartitectSarifReport {
  /// Creates a sanitized report from scanner findings and violations.
  DartitectSarifReport.fromEnvelope(CommandEnvelope envelope)
    : _envelope = envelope;

  final CommandEnvelope _envelope;

  /// Exact SARIF 2.1.0 JSON representation.
  Map<String, Object?> toJson() {
    final findings = <DartitectFinding>[
      ..._envelope.findings,
      ..._envelope.violations,
    ];
    final rulesByCode = <String, DartitectFinding>{};
    for (final finding in findings) {
      rulesByCode.putIfAbsent(finding.code, () => finding);
    }
    final codes = rulesByCode.keys.toList()..sort();
    return <String, Object?>{
      r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
      'version': '2.1.0',
      'runs': <Object?>[
        <String, Object?>{
          'automationDetails': <String, Object?>{
            'id': 'dartitect/${_envelope.command}',
          },
          'tool': <String, Object?>{
            'driver': <String, Object?>{
              'name': 'dartitect',
              'semanticVersion': CommandEnvelope.sdkVersion,
              'informationUri': 'https://github.com/ftr-tuta/dartitect',
              'rules': <Object?>[
                for (final code in codes)
                  _rule(code, rulesByCode[code]!.severity),
              ],
            },
          },
          'results': <Object?>[
            for (final finding in findings) _result(finding),
          ],
        },
      ],
    };
  }

  static Map<String, Object?> _rule(
    String code,
    FindingSeverity severity,
  ) => <String, Object?>{
    'id': code,
    'name': code,
    'shortDescription': <String, Object?>{'text': 'Dartitect diagnostic $code'},
    'defaultConfiguration': <String, Object?>{'level': _level(severity)},
  };

  static Map<String, Object?> _result(DartitectFinding finding) {
    final uri = _relativeUri(finding.path);
    return <String, Object?>{
      'ruleId': finding.code,
      'level': _level(finding.severity),
      'message': <String, Object?>{'text': _message(finding.message)},
      if (uri != null)
        'locations': <Object?>[
          <String, Object?>{
            'physicalLocation': <String, Object?>{
              'artifactLocation': <String, Object?>{'uri': uri},
              if (finding.line != null)
                'region': <String, Object?>{
                  'startLine': finding.line,
                  if (finding.column != null) 'startColumn': finding.column,
                },
            },
          },
        ],
    };
  }

  static String? _relativeUri(String? path) {
    if (path == null) return null;
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      return null;
    }
    final segments = normalized.split('/');
    if (segments.any((segment) => segment.isEmpty || segment == '..')) {
      return null;
    }
    return Uri(pathSegments: segments).toString();
  }

  static String _message(String value) {
    final singleLine = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return singleLine.length <= 500
        ? singleLine
        : '${singleLine.substring(0, 500)}…';
  }

  static String _level(FindingSeverity severity) => switch (severity) {
    FindingSeverity.info => 'note',
    FindingSeverity.warning => 'warning',
    FindingSeverity.error => 'error',
  };
}
