// Best-effort unlock preserves the primary guarded-change result.
// ignore_for_file: dartitect_empty_catch

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:dartitect_cli/dartitect_cli.dart';

import 'catalog/generated_catalog.dart';
import 'policy.dart';

/// A local STDIO-compatible Dartitect MCP server.
///
/// The server exposes a closed set of architecture tools and documentation
/// resources. It does not provide shell execution, arbitrary file reads,
/// scaffolding `create`, HTTP transport, or authorization.
base class DartitectMcpServer extends MCPServer
    with ToolsSupport, ResourcesSupport {
  /// Creates and registers the Dartitect tools and resources.
  DartitectMcpServer(
    super.channel, {
    required this.policy,
    StringSink? diagnosticSink,
    super.protocolLogSink,
  }) : _diagnosticSink = diagnosticSink ?? stderr,
       super.fromStreamChannel(
         implementation: Implementation(
           name: 'dartitect_mcp',
           version: '1.0.0-rc.4',
         ),
         instructions: _instructions,
       ) {
    _registerTools();
    _registerResources();
  }

  /// Security and resource policy applied to every request.
  final DartitectMcpPolicy policy;

  final StringSink _diagnosticSink;
  final Map<String, _StoredPlan> _plans = <String, _StoredPlan>{};
  final Set<String> _activeRoots = <String>{};

  static const String _instructions =
      'Dartitect inspects only configured local roots and is read-only by default. '
      'Use inspect, scan, verify, doctor, explain, conformance, or preview tools first. Never '
      'request secrets or arbitrary file content. A change may be applied only after '
      'the user reviews its preview, the client approves the mutating tool, and '
      '`confirmed` is true. Plans expire after ten minutes and are single-use. '
      'No create/scaffolding, shell, HTTP, OAuth, or remote access is available.';

  void _registerTools() {
    _registerReadTool(
      name: 'dartitect_inspect_project',
      description: 'Inspect safe project facts and architecture capabilities without writing.',
      schema: _projectSchema(),
      handler: (arguments) async {
        final service = DartitectProjectService(
          await _resolveProject(arguments),
        );
        return _ok(
          await service.inspectProject().then((value) => value.toJson()),
        );
      },
    );
    _registerReadTool(
      name: 'dartitect_scan_architecture',
      description: 'Scan architecture rules with optional baseline and bounded pagination.',
      schema: _projectSchema(
        extra: <String, Schema>{
          'baseline': Schema.bool(
            description: 'Apply the reviewed baseline; defaults to true.',
          ),
          'offset': Schema.int(minimum: 0),
          'limit': Schema.int(minimum: 1, maximum: policy.maxResultLimit),
        },
      ),
      handler: (arguments) async {
        final root = await _resolveProject(arguments);
        final report = await DartitectProjectService(
          root,
        ).scanArchitecture(useBaseline: arguments['baseline'] as bool? ?? true);
        return _ok(_paginateReport(report, arguments));
      },
    );
    _registerReadTool(
      name: 'dartitect_doctor_project',
      description: 'Validate Dartitect config and tooling; deep analyzer execution is opt-in.',
      schema: _projectSchema(
        extra: <String, Schema>{
          'deep': Schema.bool(
            description: 'Run dart analyze with a bounded timeout.',
          ),
        },
      ),
      handler: (arguments) async {
        final service = DartitectProjectService(
          await _resolveProject(arguments),
        );
        return _ok(
          await service
              .doctorProject(deep: arguments['deep'] as bool? ?? false)
              .then((value) => value.toJson()),
        );
      },
    );
    _registerReadTool(
      name: 'dartitect_explain_finding',
      description: 'Explain one stable Dartitect diagnostic code from the generated catalog.',
      schema: ObjectSchema(
        properties: <String, Schema>{
          'code': Schema.string(pattern: r'^DT\d{4}$'),
        },
        required: <String>['code'],
        additionalProperties: false,
      ),
      handler: (arguments) {
        final code = (arguments['code']! as String).toUpperCase();
        final diagnostic = DartitectGeneratedCatalog.diagnostics[code];
        if (diagnostic == null) {
          throw const DartitectMcpException(
            'diagnostic_not_found',
            'The requested diagnostic code is not in this SDK catalog.',
          );
        }
        return _ok(<String, Object?>{'code': code, ...diagnostic});
      },
    );
    _registerReadTool(
      name: 'dartitect_audit_conformance',
      description: 'Audit Native Strict conformance without proposing migration or coexistence.',
      schema: _projectSchema(),
      handler: (arguments) async {
        final service = DartitectProjectService(
          await _resolveProject(arguments),
        );
        return _ok(await service.auditConformance());
      },
    );
    _registerReadTool(
      name: 'dartitect_verify_project',
      description: 'Verify architecture, generated models, ecosystem overlap, and provider boundaries without writing.',
      schema: _projectSchema(
        extra: <String, Schema>{
          'offset': Schema.int(minimum: 0),
          'limit': Schema.int(minimum: 1, maximum: policy.maxResultLimit),
        },
      ),
      handler: (arguments) async {
        final report = await DartitectVerificationService(
          await _resolveProject(arguments),
        ).verify();
        return _ok(_paginateReport(report, arguments));
      },
    );
    _registerPreviewTool(
      name: 'dartitect_preview_init',
      description: 'Preview creation of the initial Dartitect configuration.',
      kind: DartitectChangeKind.init,
    );
    _registerPreviewTool(
      name: 'dartitect_preview_baseline',
      description: 'Preview a transactional architecture baseline replacement.',
      kind: DartitectChangeKind.baseline,
    );
    _registerPreviewTool(
      name: 'dartitect_preview_codex_sync',
      description: 'Preview synchronization of managed Dartitect Codex skills.',
      kind: DartitectChangeKind.codexSync,
      allowOverwriteManaged: true,
    );
    _registerPreviewTool(
      name: 'dartitect_preview_model_sync',
      description:
          'Preview deterministic model output and ownership convergence.',
      kind: DartitectChangeKind.modelSync,
    );
    _registerPreviewTool(
      name: 'dartitect_preview_model_primary_migration',
      description: 'Preview semantic primary-constructor source edits and recovery state.',
      kind: DartitectChangeKind.modelPrimaryMigration,
    );
    final schema = ObjectSchema(
      properties: <String, Schema>{
        'planId': Schema.string(minLength: 16, maxLength: 200),
        'confirmed': Schema.bool(
          description: 'Must be true after the user reviews the preview.',
        ),
      },
      required: <String>['planId', 'confirmed'],
      additionalProperties: false,
    );
    _register(
      Tool(
        name: 'dartitect_apply_change',
        title: 'Apply a reviewed Dartitect change',
        description: 'Apply one unexpired, single-use preview after explicit user and client approval.',
        inputSchema: schema,
        outputSchema: _outputSchema,
        annotations: ToolAnnotations(
          readOnlyHint: false,
          destructiveHint: true,
          idempotentHint: false,
          openWorldHint: false,
        ),
      ),
      schema,
      _applyChange,
    );
  }

  void _registerReadTool({
    required String name,
    required String description,
    required ObjectSchema schema,
    required FutureOr<CallToolResult> Function(Map<String, Object?>) handler,
  }) {
    _register(
      Tool(
        name: name,
        description: description,
        inputSchema: schema,
        outputSchema: _outputSchema,
        annotations: ToolAnnotations(
          readOnlyHint: true,
          destructiveHint: false,
          idempotentHint: true,
          openWorldHint: false,
        ),
      ),
      schema,
      handler,
    );
  }

  void _registerPreviewTool({
    required String name,
    required String description,
    required DartitectChangeKind kind,
    bool allowOverwriteManaged = false,
  }) {
    final schema = _projectSchema(
      extra: <String, Schema>{
        if (allowOverwriteManaged)
          'overwriteManaged': Schema.bool(
            description: 'Preview replacing locally changed managed skills; defaults to false.',
          ),
      },
    );
    _registerReadTool(
      name: name,
      description: description,
      schema: schema,
      handler: (arguments) => _previewChange(
        arguments,
        kind,
        overwriteManaged: arguments['overwriteManaged'] as bool? ?? false,
      ),
    );
  }

  void _register(
    Tool tool,
    ObjectSchema schema,
    FutureOr<CallToolResult> Function(Map<String, Object?>) handler,
  ) {
    registerTool(tool, (request) async {
      final arguments = request.arguments ?? const <String, Object?>{};
      final validation = schema.validate(arguments);
      if (validation.isNotEmpty) {
        return _error(
          'invalid_input',
          validation.map((value) => value.toErrorString()).join('; '),
        );
      }
      try {
        return await Future<CallToolResult>.value(handler(arguments))
            .timeout(policy.operationTimeout);
      } on DartitectMcpException catch (error) {
        _diagnosticSink.writeln(
          'Dartitect MCP ${error.code}: ${error.message}',
        );
        return _error(error.code, error.message, retryable: error.retryable);
      } on DartitectChangeException catch (error) {
        _diagnosticSink.writeln(
          'Dartitect MCP ${error.code}: ${error.message}',
        );
        return _error(error.code, error.message, retryable: true);
      } on TimeoutException {
        _diagnosticSink.writeln('Dartitect MCP timeout.');
        return _error(
          'timeout',
          'The operation exceeded the configured local timeout.',
          retryable: true,
        );
      } on FileSystemException {
        _diagnosticSink.writeln('Dartitect MCP filesystem operation failed.');
        return _error(
          'filesystem_error',
          'The local filesystem rejected the operation; no path was disclosed.',
          retryable: true,
        );
      } on FormatException catch (error) {
        return _error('invalid_project_state', _sanitizeString(error.message));
      } on Object {
        _diagnosticSink.writeln('Dartitect MCP internal operation failed.');
        return _error(
          'internal_error',
          'The local operation failed without exposing internal details.',
        );
      }
    }, validateArguments: false);
  }

  Future<CallToolResult> _previewChange(
    Map<String, Object?> arguments,
    DartitectChangeKind kind, {
    required bool overwriteManaged,
  }) async {
    final root = await _resolveProject(arguments);
    final plan = await DartitectProjectService(root)
        .previewChange(kind, overwriteManaged: overwriteManaged);
    final now = policy.now().toUtc();
    _discardExpired(now);
    String? planId;
    for (var attempts = 0; attempts < 100; attempts += 1) {
      final candidate = policy.createPlanId();
      if (RegExp(r'^[A-Za-z0-9_-]{16,200}$').hasMatch(candidate) &&
          !_plans.containsKey(candidate)) {
        planId = candidate;
        break;
      }
    }
    if (planId == null) {
      throw const DartitectMcpException(
        'plan_id_unavailable',
        'A unique opaque plan identifier could not be created.',
        retryable: true,
      );
    }
    final expiresAt = now.add(policy.planTtl);
    _plans[planId] = _StoredPlan(root: root, plan: plan, expiresAt: expiresAt);
    return _ok(<String, Object?>{
      'planId': planId,
      'expiresAt': expiresAt.toIso8601String(),
      'singleUse': true,
      'writesEnabled': policy.allowWrites,
      'plan': plan.toJson(),
    });
  }

  Future<CallToolResult> _applyChange(Map<String, Object?> arguments) async {
    if (!policy.allowWrites) {
      throw const DartitectMcpException(
        'writes_disabled',
        'This server was started without --allow-writes.',
      );
    }
    if (arguments['confirmed'] != true) {
      throw const DartitectMcpException(
        'confirmation_required',
        'Set confirmed to true only after reviewing the complete preview.',
      );
    }
    final planId = arguments['planId']! as String;
    final stored = _plans[planId];
    if (stored == null) {
      throw const DartitectMcpException(
        'plan_not_found',
        'The plan is unknown, expired, or belongs to another server process.',
      );
    }
    final now = policy.now().toUtc();
    if (!now.isBefore(stored.expiresAt)) {
      _plans.remove(planId);
      throw const DartitectMcpException(
        'plan_expired',
        'The plan expired; create and review a new preview.',
      );
    }
    if (stored.used) {
      throw const DartitectMcpException(
        'plan_replayed',
        'The plan is single-use and has already been consumed.',
      );
    }
    stored.used = true;
    if (!_activeRoots.add(stored.root.path)) {
      throw const DartitectMcpException(
        'concurrent_change',
        'Another Dartitect change is active for this root.',
        retryable: true,
      );
    }

    try {
      final receipt = await DartitectProjectService(stored.root)
          .applyChange(stored.plan);
      return _ok(<String, Object?>{
        'planId': planId,
        'appliedAt': policy.now().toUtc().toIso8601String(),
        'receipt': receipt.toJson(),
      });
    } finally {
      _activeRoots.remove(stored.root.path);
    }
  }

  Map<String, Object?> _paginateReport(
    CommandEnvelope report,
    Map<String, Object?> arguments,
  ) {
    final offset = arguments['offset'] as int? ?? 0;
    final limit = arguments['limit'] as int? ?? policy.defaultResultLimit;
    final all = <Map<String, Object?>>[
      for (final finding in report.findings)
        <String, Object?>{'category': 'finding', ...finding.toJson()},
      for (final finding in report.violations)
        <String, Object?>{'category': 'violation', ...finding.toJson()},
    ];
    final start = offset.clamp(0, all.length);
    final end = (start + limit).clamp(start, all.length);
    return <String, Object?>{
      'schemaVersion': CommandEnvelope.schemaVersion,
      'command': report.command,
      'sdkVersion': CommandEnvelope.sdkVersion,
      'project': report.project,
      'capabilities': report.capabilities,
      'results': all.sublist(start, end),
      'page': <String, Object?>{
        'offset': start,
        'limit': limit,
        'returned': end - start,
        'total': all.length,
        if (end < all.length) 'nextOffset': end,
      },
      'exitCode': report.exitCode,
    };
  }

  Future<Directory> _resolveProject(Map<String, Object?> arguments) =>
      policy.resolveProject(
        rootName: arguments['root'] as String?,
        path: arguments['path'] as String?,
      );

  void _discardExpired(DateTime now) {
    _plans.removeWhere((_, value) => !now.isBefore(value.expiresAt));
  }

  CallToolResult _ok(Map<String, Object?> value) {
    final output = _sanitize(<String, Object?>{'ok': true, ...value});
    return CallToolResult(
      structuredContent: output,
      content: <Content>[TextContent(text: jsonEncode(output))],
    );
  }

  CallToolResult _error(String code, String message, {bool retryable = false}) {
    final output = <String, Object?>{
      'ok': false,
      'error': <String, Object?>{
        'code': code,
        'message': _sanitizeString(message),
        'retryable': retryable,
      },
    };
    return CallToolResult(
      isError: true,
      structuredContent: output,
      content: <Content>[TextContent(text: jsonEncode(output))],
    );
  }

  Map<String, Object?> _sanitize(Map<String, Object?> input) =>
      _sanitizeValue(input) as Map<String, Object?>;

  Object? _sanitizeValue(Object? value) => switch (value) {
    String() => _sanitizeString(value),
    List<Object?>() => <Object?>[
      for (final item in value) _sanitizeValue(item),
    ],
    Map<String, Object?>() => <String, Object?>{
      for (final entry in value.entries) entry.key: _sanitizeValue(entry.value),
    },
    _ => value,
  };

  String _sanitizeString(String input) {
    var value = input;
    for (final root in policy.allowedRoots) {
      value = value.replaceAll(root.path, '.');
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) value = value.replaceAll(home, '~');
    value = value.replaceAll(
      RegExp(
        r'(authorization|cookie|token|password|secret|dsn)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      r'$1=<redacted>',
    );
    return value.length <= 2000 ? value : '${value.substring(0, 2000)}…';
  }

  void _registerResources() {
    addResource(
      Resource(
        uri: 'dartitect://packages',
        name: 'Dartitect package catalog',
        description:
            'Generated package versions, stability, platforms, and purpose.',
        mimeType: 'application/json',
      ),
      (request) => _jsonResource(request.uri, <String, Object?>{
        'schemaVersion': 1,
        'apiSnapshotHash': DartitectGeneratedCatalog.apiSnapshotHash,
        'packages': DartitectGeneratedCatalog.packages,
      }),
    );
    addResource(
      Resource(
        uri: 'dartitect://config/v1',
        name: 'Dartitect config v1',
        description: 'Credential-free canonical configuration shape.',
        mimeType: 'application/json',
      ),
      (request) =>
          _jsonResource(request.uri, DartitectGeneratedCatalog.configV1),
    );
    addResourceTemplate(
      ResourceTemplate(
        uriTemplate: 'dartitect://packages/{name}',
        name: 'Dartitect package',
        mimeType: 'application/json',
      ),
      _readPackageResource,
    );
    addResourceTemplate(
      ResourceTemplate(
        uriTemplate: 'dartitect://diagnostics/{code}',
        name: 'Dartitect diagnostic',
        mimeType: 'application/json',
      ),
      _readDiagnosticResource,
    );
    addResourceTemplate(
      ResourceTemplate(
        uriTemplate: 'dartitect://guides/{slug}',
        name: 'Dartitect public guide',
        mimeType: 'text/markdown',
      ),
      _readGuideResource,
    );
  }

  ReadResourceResult? _readPackageResource(ReadResourceRequest request) {
    final name = _templateValue(request.uri, 'packages');
    if (name == null) return null;
    final package = DartitectGeneratedCatalog.packages[name];
    if (package == null) return null;
    return _jsonResource(request.uri, <String, Object?>{
      'name': name,
      ...package,
    });
  }

  ReadResourceResult? _readDiagnosticResource(ReadResourceRequest request) {
    final code = _templateValue(request.uri, 'diagnostics')?.toUpperCase();
    if (code == null || !RegExp(r'^DT\d{4}$').hasMatch(code)) return null;
    final diagnostic = DartitectGeneratedCatalog.diagnostics[code];
    if (diagnostic == null) return null;
    return _jsonResource(request.uri, <String, Object?>{
      'code': code,
      ...diagnostic,
    });
  }

  ReadResourceResult? _readGuideResource(ReadResourceRequest request) {
    final slug = _templateValue(request.uri, 'guides');
    if (slug == null || !RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) return null;
    final guide = DartitectGeneratedCatalog.guides[slug];
    if (guide == null) return null;
    return ReadResourceResult(
      contents: <ResourceContents>[
        TextResourceContents(
          uri: request.uri,
          text: guide,
          mimeType: 'text/markdown',
        ),
      ],
    );
  }

  ReadResourceResult _jsonResource(String uri, Map<String, Object?> value) =>
      ReadResourceResult(
        contents: <ResourceContents>[
          TextResourceContents(
            uri: uri,
            text: jsonEncode(_sanitize(value)),
            mimeType: 'application/json',
          ),
        ],
      );

  static String? _templateValue(String source, String host) {
    final uri = Uri.tryParse(source);
    if (uri == null || uri.scheme != 'dartitect' || uri.host != host) {
      return null;
    }
    if (uri.pathSegments.length != 1 || uri.hasQuery || uri.hasFragment) {
      return null;
    }
    final value = uri.pathSegments.single;
    return value.isEmpty ? null : value;
  }

  static ObjectSchema _projectSchema({
    Map<String, Schema>? extra,
  }) => ObjectSchema(
    properties: <String, Schema>{
      'root': Schema.string(
        description:
            'Configured root name; required only when multiple roots exist.',
        maxLength: 200,
      ),
      'path': Schema.string(
        description: 'Relative project path inside the configured root.',
        maxLength: 1000,
      ),
      ...?extra,
    },
    additionalProperties: false,
  );

  static final ObjectSchema _outputSchema = ObjectSchema(
    properties: <String, Schema>{'ok': Schema.bool()},
    required: <String>['ok'],
    additionalProperties: true,
  );
}

final class _StoredPlan {
  _StoredPlan({
    required this.root,
    required this.plan,
    required this.expiresAt,
  });

  final Directory root;
  final DartitectChangePlan plan;
  final DateTime expiresAt;
  bool used = false;
}
