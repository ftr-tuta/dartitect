// Best-effort unlock preserves the primary guarded-change result.
// ignore_for_file: dartitect_empty_catch

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
           version: '1.0.0-rc.8',
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
      'Create-feature and wiring changes require their dedicated preview tools. '
      'No shell, HTTP, OAuth, or remote access is available.';

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
      description: 'Scan strict architecture rules with bounded pagination.',
      schema: _projectSchema(
        extra: <String, Schema>{
          'offset': Schema.int(minimum: 0),
          'limit': Schema.int(minimum: 1, maximum: policy.maxResultLimit),
        },
      ),
      handler: (arguments) async {
        final root = await _resolveProject(arguments);
        final report = await DartitectProjectService(root).scanArchitecture();
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
      description:
          'Audit Native Strict conformance without proposing migration.',
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
      description: 'Verify architecture, generated models, ecosystem policy, and provider boundaries without writing.',
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
    _registerCreateFeaturePreview();
    _registerWiringPreview();
    _registerReadTool(
      name: 'dartitect_explain_feature_graph',
      description: 'Explain one strict feature declaration and its managed graph outputs.',
      schema: _featureReadSchema(),
      handler: _explainFeatureGraph,
    );
    _registerReadTool(
      name: 'dartitect_list_consumer_owned_seams',
      description: 'List paginated consumer-owned seams that wiring sync never overwrites.',
      schema: _featureReadSchema(paginated: true),
      handler: _listConsumerOwnedSeams,
    );
    _registerReadTool(
      name: 'dartitect_verify_primary_constructor_policy',
      description: 'Verify primary constructors and explicit data-carrier markers without writes.',
      schema: _projectSchema(
        extra: <String, Schema>{
          'offset': Schema.int(minimum: 0),
          'limit': Schema.int(minimum: 1, maximum: policy.maxResultLimit),
        },
      ),
      handler: _verifyPrimaryConstructorPolicy,
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

  void _registerCreateFeaturePreview() {
    final schema = _projectSchema(
      extra: <String, Schema>{
        'name': Schema.string(pattern: r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
        'profile': Schema.string(
          enumValues: const <String>[
            'local',
            'online',
            'cache',
            'replica',
            'offline-full',
          ],
        ),
        'scope': Schema.string(
          enumValues: const <String>['application', 'session'],
        ),
        'storageContext': Schema.string(
          pattern: r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$',
        ),
        'transport': Schema.string(pattern: r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
        'targets': Schema.string(),
        'pagination': Schema.string(
          enumValues: const <String>['none', 'cursor'],
        ),
        'headlessTargets': Schema.string(),
        'diagnostics': Schema.string(
          enumValues: const <String>['off', 'basic', 'full'],
        ),
        'capabilities': Schema.string(
          pattern: r'^(?:credentials|attachments|forms|queries)(?:,(?:credentials|attachments|forms|queries))*$',
        ),
      },
      required: const <String>['name', 'profile'],
    );
    _registerReadTool(
      name: 'dartitect_preview_create_feature',
      description: 'Preview strict feature registration, consumer seams, and managed wiring.',
      schema: schema,
      handler: _previewCreateFeature,
    );
  }

  void _registerWiringPreview() {
    _registerReadTool(
      name: 'dartitect_preview_wiring_sync',
      description: 'Preview deterministic managed wiring convergence and orphan removal.',
      schema: _projectSchema(),
      handler: _previewWiringSync,
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
    final planId = _newPlanId();
    final expiresAt = now.add(policy.planTtl);
    _plans[planId] = _StoredPlan.project(
      root: root,
      plan: plan,
      expiresAt: expiresAt,
    );
    return _ok(<String, Object?>{
      'planId': planId,
      'expiresAt': expiresAt.toIso8601String(),
      'singleUse': true,
      'writesEnabled': policy.allowWrites,
      'plan': plan.toJson(),
    });
  }

  Future<CallToolResult> _previewCreateFeature(
    Map<String, Object?> arguments,
  ) async {
    final root = await _resolveProject(arguments);
    final name = arguments['name']! as String;
    final options = FeatureScaffoldOptions(
      profile: FeatureProfile.parse(arguments['profile']! as String),
      scope: FeatureScope.parse(
        arguments['scope'] as String? ?? FeatureScope.application.wireName,
      ),
      storageContext: arguments['storageContext'] as String?,
      transport: arguments['transport'] as String?,
      targets: _parseTargets(arguments['targets'] as String?),
      pagination: FeaturePagination.parse(
        arguments['pagination'] as String? ?? FeaturePagination.none.wireName,
      ),
      headlessTargets: _parseTargets(arguments['headlessTargets'] as String?),
      diagnostics: FeatureDiagnosticsLevel.parse(
        arguments['diagnostics'] as String? ??
            FeatureDiagnosticsLevel.basic.wireName,
      ),
      capabilities: _parseCapabilities(arguments['capabilities'] as String?),
    );
    final configFile = File(_join(root.path, 'dartitect.json'));
    final prior = await configFile.exists()
        ? await DartitectConfig.load(configFile)
        : DartitectConfig();
    final declaration = _featureDeclaration(name, options);
    final existing = prior.features.declarations[name];
    if (existing != null &&
        jsonEncode(existing.toJson()) != jsonEncode(declaration.toJson())) {
      throw DartitectConfigException(
        '/features/declarations/$name',
        'feature already exists with a different declaration',
      );
    }
    final next = _withFeature(prior, name, declaration);
    final packageName =
        (await ProjectScanner(root).scan()).packageName ?? 'application';
    final seamPlan = await GenerationEngine(
      root,
      namespace: GenerationNamespace.scaffolding,
    ).plan(ScaffoldFactory(packageName: packageName).profile(options, name));
    final wiring = await DartitectWiringService(root).inspect(config: next);
    if (seamPlan.hasConflicts || wiring.plan.hasConflicts) {
      throw const DartitectMcpException(
        'generation_conflict',
        'Consumer-owned seams or managed wiring conflict with the preview.',
      );
    }
    final cliArguments = _createFeatureArguments(name, options);
    final token = await _projectStateToken(root);
    final preview = <String, Object?>{
      'command': 'create feature',
      'feature': name,
      'declaration': declaration.toJson(),
      'operations': <Object?>[
        <String, Object?>{
          'path': 'dartitect.json',
          'disposition': existing == null ? 'update' : 'noOp',
        },
        ..._generationOperations(seamPlan),
        ..._generationOperations(wiring.plan),
      ],
    };
    return _storeCustomPlan(
      root: root,
      expectedStateToken: token,
      preview: preview,
      apply: () async {
        final output = StringBuffer();
        final errors = StringBuffer();
        final exitCode = await DartitectCliRunner(
          stdoutSink: output,
          stderrSink: errors,
          currentDirectory: root,
        ).run(cliArguments);
        if (exitCode != DartitectExitCode.success.code) {
          throw DartitectMcpException(
            'apply_failed',
            errors.isEmpty
                ? 'Feature creation failed during revalidation.'
                : errors.toString(),
            retryable: true,
          );
        }
        return <String, Object?>{
          'command': 'create feature',
          'feature': name,
          'exitCode': exitCode,
          'summary': output.toString(),
        };
      },
    );
  }

  Future<CallToolResult> _previewWiringSync(
    Map<String, Object?> arguments,
  ) async {
    final root = await _resolveProject(arguments);
    final service = DartitectWiringService(root);
    final report = await service.inspect();
    if (report.plan.hasConflicts) {
      throw const DartitectMcpException(
        'generation_conflict',
        'Managed wiring conflicts with consumer-owned bytes.',
      );
    }
    final token = await _projectStateToken(root);
    return _storeCustomPlan(
      root: root,
      expectedStateToken: token,
      preview: report.toJson(),
      apply: () async => (await service.apply()).toJson(),
    );
  }

  Future<CallToolResult> _storeCustomPlan({
    required Directory root,
    required String expectedStateToken,
    required Map<String, Object?> preview,
    required Future<Map<String, Object?>> Function() apply,
  }) async {
    final now = policy.now().toUtc();
    _discardExpired(now);
    final planId = _newPlanId();
    final expiresAt = now.add(policy.planTtl);
    _plans[planId] = _StoredPlan.custom(
      root: root,
      expectedStateToken: expectedStateToken,
      currentStateToken: () => _projectStateToken(root),
      apply: apply,
      expiresAt: expiresAt,
    );
    return _ok(<String, Object?>{
      'planId': planId,
      'expiresAt': expiresAt.toIso8601String(),
      'singleUse': true,
      'writesEnabled': policy.allowWrites,
      'plan': preview,
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
    if (!_activeRoots.add(stored.root.path)) {
      throw const DartitectMcpException(
        'concurrent_change',
        'Another Dartitect change is active for this root.',
        retryable: true,
      );
    }
    stored.used = true;

    try {
      final Map<String, Object?> receipt;
      final projectPlan = stored.projectPlan;
      if (projectPlan != null) {
        receipt = (await DartitectProjectService(
          stored.root,
        ).applyChange(projectPlan)).toJson();
      } else {
        final stateToken = await stored.currentStateToken!();
        if (stateToken != stored.expectedStateToken) {
          throw const DartitectMcpException(
            'stale_plan',
            'Project state changed after preview; create and review a new plan.',
            retryable: true,
          );
        }
        receipt = await stored.applyCustom!();
      }
      return _ok(<String, Object?>{
        'planId': planId,
        'appliedAt': policy.now().toUtc().toIso8601String(),
        'receipt': receipt,
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

  Future<CallToolResult> _explainFeatureGraph(
    Map<String, Object?> arguments,
  ) async {
    final root = await _resolveProject(arguments);
    final config = await DartitectConfig.load(
      File(_join(root.path, 'dartitect.json')),
    );
    final name = arguments['feature']! as String;
    final declaration = config.features.declarations[name];
    if (declaration == null) {
      throw const DartitectMcpException(
        'feature_not_found',
        'The requested feature is not declared in strict config v2.',
      );
    }
    final wiring = await DartitectWiringService(root).inspect(config: config);
    final prefix = 'lib/features/$name/';
    return _ok(<String, Object?>{
      'feature': name,
      'declaration': declaration.toJson(),
      'scheduler': config.scheduler.toJson(),
      'managedGraph': <Object?>[
        for (final operation in wiring.plan.operations)
          if (operation.operation.relativePath.startsWith(prefix))
            <String, Object?>{
              'path': operation.operation.relativePath,
              'disposition': operation.disposition.name,
              'ownership': 'dartitect_managed',
            },
      ],
      'composition': 'direct_constructors',
      'runtimeContainer': false,
    });
  }

  Future<CallToolResult> _listConsumerOwnedSeams(
    Map<String, Object?> arguments,
  ) async {
    final root = await _resolveProject(arguments);
    final config = await DartitectConfig.load(
      File(_join(root.path, 'dartitect.json')),
    );
    final name = arguments['feature']! as String;
    final declaration = config.features.declarations[name];
    if (declaration == null) {
      throw const DartitectMcpException(
        'feature_not_found',
        'The requested feature is not declared in strict config v2.',
      );
    }
    final packageName =
        (await ProjectScanner(root).scan()).packageName ?? 'application';
    final options = FeatureScaffoldOptions(
      profile: declaration.profile,
      scope: declaration.scope,
      storageContext: declaration.storageContext,
      dataset: declaration.dataset,
      transport: declaration.transport,
      targets: declaration.targets.toSet(),
      pagination: declaration.pagination,
      headlessTargets: declaration.headlessTargets.toSet(),
      diagnostics: declaration.diagnostics,
      capabilities: declaration.capabilities.toSet(),
    );
    final seams =
        ScaffoldFactory(packageName: packageName)
            .profile(options, name)
            .where(
              (operation) =>
                  operation.ownership == GeneratedOwnership.generatedOnce,
            )
            .map(
              (operation) => <String, Object?>{
                'path': operation.relativePath,
                'ownership': 'consumer',
                'overwritePolicy': 'create_once',
              },
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                (left['path']! as String).compareTo(right['path']! as String),
          );
    return _ok(<String, Object?>{
      'feature': name,
      ..._paginateValues(seams, arguments),
    });
  }

  Future<CallToolResult> _verifyPrimaryConstructorPolicy(
    Map<String, Object?> arguments,
  ) async {
    final root = await _resolveProject(arguments);
    final report = await DartitectModelGenerator(root).inspect();
    final results = <Map<String, Object?>>[
      for (final diagnostic in report.findings)
        <String, Object?>{'category': 'diagnostic', ...diagnostic.toJson()},
    ];
    return _ok(<String, Object?>{
      'command': 'verify primary constructor policy',
      'pendingRecovery': report.plan?.pendingRecovery ?? false,
      'modelCount': report.operations.length,
      ..._paginateValues(results, arguments),
    });
  }

  Map<String, Object?> _paginateValues(
    List<Map<String, Object?>> values,
    Map<String, Object?> arguments,
  ) {
    final offset = arguments['offset'] as int? ?? 0;
    final limit = arguments['limit'] as int? ?? policy.defaultResultLimit;
    final start = offset.clamp(0, values.length);
    final end = (start + limit).clamp(start, values.length);
    return <String, Object?>{
      'results': values.sublist(start, end),
      'page': <String, Object?>{
        'offset': start,
        'limit': limit,
        'returned': end - start,
        'total': values.length,
        if (end < values.length) 'nextOffset': end,
      },
    };
  }

  Future<String> _projectStateToken(Directory root) async {
    const maxFiles = 20000;
    const maxBytes = 128 * 1024 * 1024;
    final entries = <String, File>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relative = _relative(root.path, entity.path);
      if (_excludedStatePath(relative) || entity is! File) continue;
      entries[relative] = entity;
      if (entries.length > maxFiles) {
        throw const DartitectMcpException(
          'project_too_large',
          'The project exceeds the bounded MCP state-validation file count.',
        );
      }
    }
    final paths = entries.keys.toList()..sort();
    var bytesRead = 0;
    final state = BytesBuilder(copy: false);
    for (final path in paths) {
      final bytes = await entries[path]!.readAsBytes();
      bytesRead += bytes.length;
      if (bytesRead > maxBytes) {
        throw const DartitectMcpException(
          'project_too_large',
          'The project exceeds the bounded MCP state-validation byte count.',
        );
      }
      state
        ..add(utf8.encode(path))
        ..addByte(0)
        ..add(sha256.convert(bytes).bytes)
        ..addByte(0);
    }
    return sha256.convert(state.takeBytes()).toString();
  }

  static bool _excludedStatePath(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    return normalized == '.git' ||
        normalized.startsWith('.git/') ||
        normalized == '.dart_tool' ||
        normalized.startsWith('.dart_tool/') ||
        normalized == 'build' ||
        normalized.startsWith('build/') ||
        normalized.endsWith('/project.lock') ||
        normalized.endsWith('/fleet.lock');
  }

  static Iterable<Map<String, Object?>> _generationOperations(
    GenerationPlan plan,
  ) => plan.operations.map(
    (operation) => <String, Object?>{
      'path': operation.operation.relativePath,
      'disposition': operation.disposition.name,
      'ownership':
          operation.operation.ownership == GeneratedOwnership.fullyGenerated
          ? 'dartitect_managed'
          : 'consumer',
    },
  );

  static Set<DartitectCapability> _parseCapabilities(String? value) =>
      value == null || value.isEmpty
      ? const <DartitectCapability>{}
      : value.split(',').map(DartitectCapability.parse).toSet();

  static Set<DartitectPlatform> _parseTargets(String? value) =>
      value == null || value.isEmpty
      ? const <DartitectPlatform>{}
      : value.split(',').map(DartitectPlatform.parse).toSet();

  static DartitectFeatureDeclaration _featureDeclaration(
    String name,
    FeatureScaffoldOptions options,
  ) => DartitectFeatureDeclaration(
    profile: options.profile,
    scope: options.scope,
    storageContext: options.storageContext,
    dataset: options.storageContext == null
        ? null
        : options.dataset ?? DartitectStorageDatasetConfig.forFeature(name),
    transport: options.transport,
    targets: options.targets,
    pagination: options.pagination,
    diagnostics: options.diagnostics,
    headlessTargets: options.headlessTargets,
    capabilities: options.capabilities,
  );

  static DartitectConfig _withFeature(
    DartitectConfig prior,
    String name,
    DartitectFeatureDeclaration declaration,
  ) => DartitectConfig(
    configVersion: prior.configVersion,
    profile: prior.profile,
    layers: prior.layers,
    compositionRoots: prior.compositionRoots,
    generatedInfrastructure: prior.generatedInfrastructure,
    generatedSuffixes: prior.generatedSuffixes,
    suppressions: prior.suppressions,
    modeling: prior.modeling,
    features: DartitectFeaturesConfig(
      declarations: <String, DartitectFeatureDeclaration>{
        ...prior.features.declarations,
        name: declaration,
      },
    ),
    targets: prior.targets,
    storageContexts: prior.storageContexts,
    transports: prior.transports,
    observability: prior.observability,
    scheduler: prior.scheduler,
    extensionSources: prior.extensionSources,
  );

  static List<String> _createFeatureArguments(
    String name,
    FeatureScaffoldOptions options,
  ) => <String>[
    'create',
    'feature',
    name,
    '--profile=${options.profile.wireName}',
    '--scope=${options.scope.wireName}',
    if (options.storageContext != null)
      '--storage-context=${options.storageContext}',
    if (options.transport != null) '--transport=${options.transport}',
    if (options.targets.isNotEmpty)
      '--targets=${options.targets.map((target) => target.wireName).join(',')}',
    '--pagination=${options.pagination.wireName}',
    '--diagnostics=${options.diagnostics.wireName}',
    if (options.headlessTargets.isNotEmpty)
      '--headless-targets=${options.headlessTargets.map((target) => target.wireName).join(',')}',
    if (options.capabilities.isNotEmpty)
      '--capabilities=${(options.capabilities.map((value) => value.wireName).toList()..sort()).join(',')}',
  ];

  Future<Directory> _resolveProject(Map<String, Object?> arguments) =>
      policy.resolveProject(
        rootName: arguments['root'] as String?,
        path: arguments['path'] as String?,
      );

  void _discardExpired(DateTime now) {
    _plans.removeWhere((_, value) => !now.isBefore(value.expiresAt));
  }

  String _newPlanId() {
    for (var attempts = 0; attempts < 100; attempts += 1) {
      final candidate = policy.createPlanId();
      if (RegExp(r'^[A-Za-z0-9_-]{16,200}$').hasMatch(candidate) &&
          !_plans.containsKey(candidate)) {
        return candidate;
      }
    }
    throw const DartitectMcpException(
      'plan_id_unavailable',
      'A unique opaque plan identifier could not be created.',
      retryable: true,
    );
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
        uri: 'dartitect://config/v2',
        name: 'Dartitect config v2',
        description: 'Credential-free canonical configuration shape.',
        mimeType: 'application/json',
      ),
      (request) =>
          _jsonResource(request.uri, DartitectGeneratedCatalog.configV2),
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
    List<String> required = const <String>[],
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
    required: required,
    additionalProperties: false,
  );

  static ObjectSchema _featureReadSchema({bool paginated = false}) =>
      _projectSchema(
        extra: <String, Schema>{
          'feature': Schema.string(pattern: r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
          if (paginated) ...<String, Schema>{
            'offset': Schema.int(minimum: 0),
            'limit': Schema.int(minimum: 1, maximum: 5000),
          },
        },
        required: const <String>['feature'],
      );

  static String _relative(String root, String path) {
    if (path == root) return '.';
    return path.substring(root.length + 1).replaceAll('\\', '/');
  }

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

  static final ObjectSchema _outputSchema = ObjectSchema(
    properties: <String, Schema>{'ok': Schema.bool()},
    required: <String>['ok'],
    additionalProperties: true,
  );
}

final class _StoredPlan {
  _StoredPlan.project({
    required this.root,
    required DartitectChangePlan plan,
    required this.expiresAt,
  }) : projectPlan = plan,
       expectedStateToken = null,
       currentStateToken = null,
       applyCustom = null;

  _StoredPlan.custom({
    required this.root,
    required this.expectedStateToken,
    required this.currentStateToken,
    required Future<Map<String, Object?>> Function() apply,
    required this.expiresAt,
  }) : projectPlan = null,
       applyCustom = apply;

  final Directory root;
  final DartitectChangePlan? projectPlan;
  final String? expectedStateToken;
  final Future<String> Function()? currentStateToken;
  final Future<Map<String, Object?>> Function()? applyCustom;
  final DateTime expiresAt;
  bool used = false;
}
