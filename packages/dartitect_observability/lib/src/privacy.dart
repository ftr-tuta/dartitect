import 'dart:collection';

/// Schema emitted by the payload-free observability privacy diagnostics view.
const int observabilityPrivacyPolicySchemaVersion = 1;

/// Security boundary applied to one observability destination.
enum ObservabilityDestinationKind {
  /// A destination controlled by the current device or process.
  local,

  /// A destination that exports telemetry outside the current device.
  remote,
}

/// Privacy action selected for one classified value.
enum ObservabilityPrivacyAction {
  /// Preserve a bounded value while continuing to inspect descendants.
  allow,

  /// Preserve the field but transform its value.
  mask,

  /// Remove the value or replace it with a data-free structural marker.
  deny,
}

/// Built-in privacy posture for observability data.
enum ObservabilityPrivacyProfile {
  /// Minimal data for sensitive production environments.
  strict,

  /// Safe operational context with masked local identifiers.
  balanced,

  /// Explicitly classified bounded diagnostics for controlled investigation.
  diagnostic,
}

/// Source that supplied the effective privacy action.
enum ObservabilityPrivacyDecisionSource {
  /// A rule for the concrete named destination.
  namedDestinationOverride,

  /// A local or remote destination-class rule.
  destinationOverride,

  /// A rule shared by all destinations.
  globalOverride,

  /// A built-in profile rule.
  profile,

  /// The profile fallback for unknown values.
  defaultRule,
}

/// Extensible dotted classification for observability data.
final class ObservabilityDataClass {
  const ObservabilityDataClass._(this.wireName);

  /// Creates an application-owned class such as
  /// `business.customer.contract_number`.
  factory ObservabilityDataClass.custom(String wireName) {
    if (wireName.length > 120 ||
        wireName.split('.').length > 16 ||
        !_pattern.hasMatch(wireName)) {
      throw ArgumentError.value(
        wireName,
        'wireName',
        'must contain 2-16 lowercase dotted ASCII segments and at most '
            '120 characters',
      );
    }
    return ObservabilityDataClass._(wireName);
  }

  /// Stable category name. It is configuration, never an observed value.
  final String wireName;

  /// This class followed by its dotted ancestors, most specific first.
  Iterable<ObservabilityDataClass> get hierarchy sync* {
    var candidate = wireName;
    while (true) {
      yield ObservabilityDataClass._(candidate);
      final separator = candidate.lastIndexOf('.');
      if (separator < 0) return;
      candidate = candidate.substring(0, separator);
    }
  }

  /// Whether remotely allowing this class requires explicit risk acceptance.
  bool get isHighRisk =>
      wireName == 'credential' ||
      wireName.startsWith('credential.') ||
      wireName == 'identity' ||
      wireName.startsWith('identity.') ||
      wireName == fileContent.wireName ||
      wireName == httpAuthorization.wireName;

  @override
  bool operator ==(Object other) =>
      other is ObservabilityDataClass && other.wireName == wireName;

  @override
  int get hashCode => wireName.hashCode;

  @override
  String toString() => wireName;

  static final RegExp _pattern = RegExp(
    r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$',
  );

  /// Root for safely bounded metadata.
  static const safe = ObservabilityDataClass._('safe');

  /// Generic safely bounded metadata.
  static const safeMetadata = ObservabilityDataClass._('safe.metadata');

  /// Closed low-cardinality enum value.
  static const safeEnum = ObservabilityDataClass._('safe.enum');

  /// Bounded numeric count.
  static const safeCount = ObservabilityDataClass._('safe.count');

  /// Bounded duration.
  static const safeDuration = ObservabilityDataClass._('safe.duration');

  /// Closed low-cardinality status.
  static const safeStatus = ObservabilityDataClass._('safe.status');

  /// Validated static route template.
  static const safeRouteTemplate = ObservabilityDataClass._(
    'safe.route_template',
  );

  /// Runtime type name obtained without projecting an object.
  static const safeRuntimeType = ObservabilityDataClass._('safe.runtime_type');

  /// Static protocol version.
  static const safeProtocolVersion = ObservabilityDataClass._(
    'safe.protocol_version',
  );

  /// Root for HTTP data.
  static const http = ObservabilityDataClass._('http');

  /// HTTP method.
  static const httpMethod = ObservabilityDataClass._('http.method');

  /// Validated HTTP route template.
  static const httpRouteTemplate = ObservabilityDataClass._(
    'http.route_template',
  );

  /// HTTP response status.
  static const httpStatus = ObservabilityDataClass._('http.status');

  /// Closed HTTP transport error type.
  static const httpErrorType = ObservabilityDataClass._('http.error_type');

  /// Raw HTTP path.
  static const httpPath = ObservabilityDataClass._('http.path');

  /// HTTP query data.
  static const httpQuery = ObservabilityDataClass._('http.query');

  /// Root for HTTP body data.
  static const httpBody = ObservabilityDataClass._('http.body');

  /// HTTP request body.
  static const httpRequestBody = ObservabilityDataClass._('http.body.request');

  /// HTTP response body.
  static const httpResponseBody = ObservabilityDataClass._(
    'http.body.response',
  );

  /// Root for HTTP header data.
  static const httpHeader = ObservabilityDataClass._('http.header');

  /// HTTP Authorization header.
  static const httpAuthorization = ObservabilityDataClass._(
    'http.header.authorization',
  );

  /// HTTP Cookie or Set-Cookie header.
  static const httpCookie = ObservabilityDataClass._('http.header.cookie');

  /// W3C tracing header.
  static const httpTraceHeader = ObservabilityDataClass._('http.header.trace');

  /// HTTP Content-Type header.
  static const httpContentType = ObservabilityDataClass._(
    'http.header.content_type',
  );

  /// Multipart HTTP content.
  static const httpMultipart = ObservabilityDataClass._('http.multipart');

  /// Binary HTTP content.
  static const httpBinary = ObservabilityDataClass._('http.binary');

  /// Root for credentials and authentication material.
  static const credential = ObservabilityDataClass._('credential');

  /// Password value.
  static const password = ObservabilityDataClass._('credential.password');

  /// Generic secret value.
  static const secret = ObservabilityDataClass._('credential.secret');

  /// API key.
  static const apiKey = ObservabilityDataClass._('credential.api_key');

  /// Session identifier or secret.
  static const session = ObservabilityDataClass._('credential.session');

  /// Cookie credential.
  static const cookie = ObservabilityDataClass._('credential.cookie');

  /// Root for token credentials.
  static const token = ObservabilityDataClass._('credential.token');

  /// Token carried by HTTP.
  static const httpToken = ObservabilityDataClass._('credential.token.http');

  /// Access token.
  static const accessToken = ObservabilityDataClass._(
    'credential.token.access',
  );

  /// Refresh token.
  static const refreshToken = ObservabilityDataClass._(
    'credential.token.refresh',
  );

  /// JSON Web Token.
  static const jwt = ObservabilityDataClass._('credential.token.jwt');

  /// Provider data-source name containing credentials.
  static const dsn = ObservabilityDataClass._('credential.dsn');

  /// Root for identity and personal data.
  static const identity = ObservabilityDataClass._('identity');

  /// Person or organization name.
  static const name = ObservabilityDataClass._('identity.name');

  /// Email address.
  static const email = ObservabilityDataClass._('identity.email');

  /// Phone number.
  static const phone = ObservabilityDataClass._('identity.phone');

  /// Brazilian CPF identifier.
  static const cpf = ObservabilityDataClass._('identity.cpf');

  /// Brazilian CNPJ identifier.
  static const cnpj = ObservabilityDataClass._('identity.cnpj');

  /// Postal or physical address.
  static const address = ObservabilityDataClass._('identity.address');

  /// User identifier.
  static const userId = ObservabilityDataClass._('identity.user_id');

  /// Device identifier.
  static const deviceId = ObservabilityDataClass._('identity.device_id');

  /// IP address.
  static const ipAddress = ObservabilityDataClass._('identity.ip_address');

  /// UUID identity value.
  static const uuid = ObservabilityDataClass._('identity.uuid');

  /// Geographic location.
  static const location = ObservabilityDataClass._('identity.location');

  /// Root for storage data.
  static const storage = ObservabilityDataClass._('storage');

  /// Storage query.
  static const storageQuery = ObservabilityDataClass._('storage.query');

  /// Storage statement.
  static const storageStatement = ObservabilityDataClass._('storage.statement');

  /// Storage table name.
  static const storageTable = ObservabilityDataClass._('storage.table');

  /// Stored value.
  static const storageValue = ObservabilityDataClass._('storage.value');

  /// Storage path.
  static const storagePath = ObservabilityDataClass._('storage.path');

  /// Root for file data.
  static const file = ObservabilityDataClass._('file');

  /// File path.
  static const filePath = ObservabilityDataClass._('file.path');

  /// File name.
  static const fileName = ObservabilityDataClass._('file.name');

  /// File content.
  static const fileContent = ObservabilityDataClass._('file.content');

  /// Root for distributed operation data.
  static const operation = ObservabilityDataClass._('operation');

  /// Idempotency key.
  static const idempotencyKey = ObservabilityDataClass._(
    'operation.idempotency_key',
  );

  /// Request identifier.
  static const requestId = ObservabilityDataClass._('operation.request_id');

  /// Runtime or job run identifier.
  static const runId = ObservabilityDataClass._('operation.run_id');

  /// Dataset key.
  static const datasetKey = ObservabilityDataClass._('operation.dataset_key');

  /// Synchronization checkpoint.
  static const checkpoint = ObservabilityDataClass._('operation.checkpoint');

  /// Work partition.
  static const partition = ObservabilityDataClass._('operation.partition');

  /// Lease owner identifier.
  static const leaseOwner = ObservabilityDataClass._('operation.lease_owner');

  /// Root for error data.
  static const error = ObservabilityDataClass._('error');

  /// Error runtime type.
  static const errorType = ObservabilityDataClass._('error.type');

  /// Error message.
  static const errorMessage = ObservabilityDataClass._('error.message');

  /// Error stack trace.
  static const errorStackTrace = ObservabilityDataClass._('error.stack_trace');

  /// Error grouping fingerprint.
  static const errorFingerprint = ObservabilityDataClass._('error.fingerprint');
}

/// Raw value with explicit, immutable privacy classifications.
final class ObservabilityClassifiedValue<T> {
  /// Creates an explicitly classified value.
  ObservabilityClassifiedValue(
    this.value, {
    required Iterable<ObservabilityDataClass> classes,
  }) : classes = Set<ObservabilityDataClass>.unmodifiable(classes) {
    if (this.classes.isEmpty) {
      throw ArgumentError.value(classes, 'classes', 'must not be empty');
    }
  }

  /// Original value. A sanitizer must consume it synchronously.
  final T value;

  /// Explicit categories, supplemented rather than replaced by classifiers.
  final Set<ObservabilityDataClass> classes;
}

/// One conflict-checked set of privacy overrides.
final class ObservabilityPrivacyOverrides {
  /// Creates overrides for one scope.
  const ObservabilityPrivacyOverrides({
    this.allow = const <ObservabilityDataClass>{},
    this.mask = const <ObservabilityDataClass>{},
    this.deny = const <ObservabilityDataClass>{},
  });

  /// Classes explicitly allowed at this scope.
  final Set<ObservabilityDataClass> allow;

  /// Classes explicitly masked at this scope.
  final Set<ObservabilityDataClass> mask;

  /// Classes explicitly denied at this scope.
  final Set<ObservabilityDataClass> deny;
}

/// Overrides attached to one validated destination name and kind.
final class ObservabilityDestinationPrivacyOverrides {
  /// Creates named overrides.
  ObservabilityDestinationPrivacyOverrides({
    required this.name,
    required this.kind,
    required this.rules,
  }) {
    _validateDestinationName(name);
  }

  /// Stable low-cardinality destination name.
  final String name;

  /// Destination security boundary.
  final ObservabilityDestinationKind kind;

  /// Rules applied before kind-wide and global overrides.
  final ObservabilityPrivacyOverrides rules;
}

/// Auditable acknowledgement required for high-risk remote allow rules.
final class ObservabilityRiskAcceptance {
  /// Acknowledges a narrowly controlled high-risk configuration.
  const ObservabilityRiskAcceptance.explicit({required this.reason});

  /// Configuration-only explanation. It is never emitted as telemetry.
  final String reason;
}

/// Global masking transformation selected after policy resolution.
enum ObservabilityMaskingMode {
  /// Replace the complete value with one constant marker.
  full,

  /// Preserve a configured prefix and suffix.
  preserveEdges,

  /// Preserve a configured number of center code points.
  preserveCenter,
}

/// Unicode-safe masking rules for values whose action is [ObservabilityPrivacyAction.mask].
final class ObservabilityMaskingPolicy {
  /// Replaces the complete value with [replacement].
  const ObservabilityMaskingPolicy.full({this.replacement = '[REDACTED]'})
    : mode = ObservabilityMaskingMode.full,
      visibleStart = 0,
      visibleEnd = 0,
      visibleCenter = 0,
      maskedStartUnits = 0,
      maskedEndUnits = 0,
      maskCharacter = '•',
      minimumMaskedUnits = 0;

  /// Preserves [visibleStart] leading and [visibleEnd] trailing code points.
  const ObservabilityMaskingPolicy.preserveEdges({
    required this.visibleStart,
    required this.visibleEnd,
    this.maskCharacter = '•',
    this.minimumMaskedUnits = 3,
    this.replacement = '[REDACTED]',
  }) : mode = ObservabilityMaskingMode.preserveEdges,
       visibleCenter = 0,
       maskedStartUnits = 0,
       maskedEndUnits = 0;

  /// Preserves [visibleCenter] code points surrounded by constant masks.
  const ObservabilityMaskingPolicy.preserveCenter({
    required this.visibleCenter,
    this.maskedStartUnits = 3,
    this.maskedEndUnits = 3,
    this.maskCharacter = '•',
    this.replacement = '[REDACTED]',
  }) : mode = ObservabilityMaskingMode.preserveCenter,
       visibleStart = 0,
       visibleEnd = 0,
       minimumMaskedUnits = 0;

  /// Selected masking shape.
  final ObservabilityMaskingMode mode;

  /// Constant full-mask replacement.
  final String replacement;

  /// Visible prefix size for [ObservabilityMaskingMode.preserveEdges].
  final int visibleStart;

  /// Visible suffix size for [ObservabilityMaskingMode.preserveEdges].
  final int visibleEnd;

  /// Visible center size for [ObservabilityMaskingMode.preserveCenter].
  final int visibleCenter;

  /// Constant leading mask size for center-preserving masks.
  final int maskedStartUnits;

  /// Constant trailing mask size for center-preserving masks.
  final int maskedEndUnits;

  /// One Unicode code point repeated by partial masks.
  final String maskCharacter;

  /// Minimum hidden portion required before preserving edges.
  final int minimumMaskedUnits;

  /// Masks [input] without splitting UTF-16 surrogate pairs.
  String mask(String input) {
    _validate();
    if (mode == ObservabilityMaskingMode.full) return replacement;
    final points = input.runes.toList(growable: false);
    if (mode == ObservabilityMaskingMode.preserveEdges) {
      final hidden = points.length - visibleStart - visibleEnd;
      if (hidden < minimumMaskedUnits || hidden <= 0) return replacement;
      return '${String.fromCharCodes(points.take(visibleStart))}'
          '${maskCharacter * hidden}'
          '${String.fromCharCodes(points.skip(points.length - visibleEnd))}';
    }
    if (points.length <= visibleCenter ||
        maskedStartUnits + maskedEndUnits <= 0) {
      return replacement;
    }
    final centerStart = (points.length - visibleCenter) ~/ 2;
    final center = points.skip(centerStart).take(visibleCenter);
    return '${maskCharacter * maskedStartUnits}'
        '${String.fromCharCodes(center)}'
        '${maskCharacter * maskedEndUnits}';
  }

  void _validate() {
    if (replacement.isEmpty) {
      throw ArgumentError.value(
        replacement,
        'replacement',
        'must not be empty',
      );
    }
    if (maskCharacter.runes.length != 1) {
      throw ArgumentError.value(
        maskCharacter,
        'maskCharacter',
        'must contain exactly one Unicode code point',
      );
    }
    if (visibleStart < 0 ||
        visibleEnd < 0 ||
        visibleCenter < 0 ||
        maskedStartUnits < 0 ||
        maskedEndUnits < 0 ||
        minimumMaskedUnits < 1 &&
            mode == ObservabilityMaskingMode.preserveEdges ||
        mode == ObservabilityMaskingMode.preserveEdges &&
            visibleStart + visibleEnd == 0 ||
        mode == ObservabilityMaskingMode.preserveCenter && visibleCenter < 1) {
      throw ArgumentError('Masking sizes must preserve some but not all data.');
    }
  }
}

/// Data-free explanation of an effective privacy decision.
final class ObservabilityPrivacyDecision {
  /// Creates a data-free decision explanation.
  const ObservabilityPrivacyDecision({
    required this.action,
    required this.source,
    this.winningClass,
  });

  /// Most restrictive effective action.
  final ObservabilityPrivacyAction action;

  /// Class whose resolved rule won, or null for an unknown value.
  final ObservabilityDataClass? winningClass;

  /// Scope that supplied the winning rule.
  final ObservabilityPrivacyDecisionSource source;
}

/// Immutable destination-aware privacy policy.
final class ObservabilityPrivacyPolicy {
  ObservabilityPrivacyPolicy._({
    required this.profile,
    required this.masking,
    required this.globalOverrides,
    required this.localOverrides,
    required this.remoteOverrides,
    required Map<String, ObservabilityDestinationPrivacyOverrides>
    namedOverrides,
    required this.riskAcceptance,
  }) : namedOverrides =
           UnmodifiableMapView<
             String,
             ObservabilityDestinationPrivacyOverrides
           >(namedOverrides);

  /// Builds a conflict-checked policy from one reviewed profile.
  factory ObservabilityPrivacyPolicy.fromProfile({
    required ObservabilityPrivacyProfile profile,
    ObservabilityMaskingPolicy masking =
        const ObservabilityMaskingPolicy.full(),
    Set<ObservabilityDataClass> overrideRuleAllow =
        const <ObservabilityDataClass>{},
    Set<ObservabilityDataClass> overrideRuleMask =
        const <ObservabilityDataClass>{},
    Set<ObservabilityDataClass> overrideRuleDeny =
        const <ObservabilityDataClass>{},
    ObservabilityPrivacyOverrides localOverrides =
        const ObservabilityPrivacyOverrides(),
    ObservabilityPrivacyOverrides remoteOverrides =
        const ObservabilityPrivacyOverrides(),
    Iterable<ObservabilityDestinationPrivacyOverrides> destinationOverrides =
        const <ObservabilityDestinationPrivacyOverrides>[],
    ObservabilityRiskAcceptance? riskAcceptance,
  }) {
    final global = ObservabilityPrivacyOverrides(
      allow: overrideRuleAllow,
      mask: overrideRuleMask,
      deny: overrideRuleDeny,
    );
    _validateRules('globalOverrides', global);
    _validateRules('localOverrides', localOverrides);
    _validateRules('remoteOverrides', remoteOverrides);
    masking._validate();
    if (riskAcceptance != null && riskAcceptance.reason.trim().isEmpty) {
      throw ArgumentError.value(
        riskAcceptance.reason,
        'riskAcceptance.reason',
        'must explain the controlled environment',
      );
    }
    final named = <String, ObservabilityDestinationPrivacyOverrides>{};
    for (final override in destinationOverrides) {
      _validateRules('destinationOverrides[${override.name}]', override.rules);
      if (named.containsKey(override.name)) {
        throw ArgumentError.value(
          override.name,
          'destinationOverrides',
          'contains a duplicate destination name',
        );
      }
      named[override.name] = override;
    }
    final riskyRemoteAllows = <ObservabilityDataClass>{
      ...global.allow.where((value) => value.isHighRisk),
      ...remoteOverrides.allow.where((value) => value.isHighRisk),
      for (final override in named.values)
        if (override.kind == ObservabilityDestinationKind.remote)
          ...override.rules.allow.where((value) => value.isHighRisk),
    };
    if (riskyRemoteAllows.isNotEmpty && riskAcceptance == null) {
      throw ArgumentError(
        'Allowing high-risk classes for a remote destination requires '
        'ObservabilityRiskAcceptance.explicit.',
      );
    }
    return ObservabilityPrivacyPolicy._(
      profile: profile,
      masking: masking,
      globalOverrides: _freeze(global),
      localOverrides: _freeze(localOverrides),
      remoteOverrides: _freeze(remoteOverrides),
      namedOverrides: named,
      riskAcceptance: riskAcceptance,
    );
  }

  /// Selected reviewed profile.
  final ObservabilityPrivacyProfile profile;

  /// Transformation used for effective mask decisions.
  final ObservabilityMaskingPolicy masking;

  /// Rules shared by local and remote destinations.
  final ObservabilityPrivacyOverrides globalOverrides;

  /// Rules for all local destinations.
  final ObservabilityPrivacyOverrides localOverrides;

  /// Rules for all remote destinations.
  final ObservabilityPrivacyOverrides remoteOverrides;

  /// Rules for validated concrete destination names.
  final Map<String, ObservabilityDestinationPrivacyOverrides> namedOverrides;

  /// Explicit high-risk acknowledgement, if configured.
  final ObservabilityRiskAcceptance? riskAcceptance;

  /// Returns category names and their effective actions without observed data.
  ///
  /// The result includes every built-in category and every application-owned
  /// category mentioned by an override. It intentionally excludes masking
  /// replacements and risk-acceptance reasons because those configuration
  /// strings are not required by read-only diagnostics.
  Map<String, ObservabilityPrivacyAction> effectiveActions({
    required ObservabilityDestinationKind destination,
    String? destinationName,
  }) {
    final classes =
        <ObservabilityDataClass>{
            ..._builtInDiagnosticClasses,
            ..._classesIn(globalOverrides),
            ..._classesIn(localOverrides),
            ..._classesIn(remoteOverrides),
            for (final override in namedOverrides.values)
              ..._classesIn(override.rules),
          }.toList(growable: false)
          ..sort((left, right) => left.wireName.compareTo(right.wireName));
    return Map<String, ObservabilityPrivacyAction>.unmodifiable(
      <String, ObservabilityPrivacyAction>{
        for (final dataClass in classes)
          dataClass.wireName: explain(
            destination: destination,
            destinationName: destinationName,
            classes: <ObservabilityDataClass>{dataClass},
          ).action,
      },
    );
  }

  /// Resolves classes independently, then combines them with
  /// `deny > mask > allow`.
  ObservabilityPrivacyDecision explain({
    required ObservabilityDestinationKind destination,
    required Set<ObservabilityDataClass> classes,
    String? destinationName,
  }) {
    if (destinationName != null) _validateDestinationName(destinationName);
    if (classes.isEmpty) {
      return ObservabilityPrivacyDecision(
        action: _defaultAction(profile, destination),
        source: ObservabilityPrivacyDecisionSource.defaultRule,
      );
    }
    final sorted = classes.toList(growable: false)
      ..sort((left, right) => left.wireName.compareTo(right.wireName));
    _ResolvedRule? winner;
    for (final dataClass in sorted) {
      final resolved = _resolveClass(
        dataClass,
        destination: destination,
        destinationName: destinationName,
      );
      if (winner == null || _wins(resolved, winner)) winner = resolved;
    }
    return ObservabilityPrivacyDecision(
      action: winner!.action,
      winningClass: winner.dataClass,
      source: winner.source,
    );
  }

  _ResolvedRule _resolveClass(
    ObservabilityDataClass dataClass, {
    required ObservabilityDestinationKind destination,
    required String? destinationName,
  }) {
    if (destinationName != null) {
      final named = namedOverrides[destinationName];
      if (named != null && named.kind == destination) {
        final action = _lookupOverrides(named.rules, dataClass);
        if (action != null) {
          return _ResolvedRule(
            action,
            dataClass,
            ObservabilityPrivacyDecisionSource.namedDestinationOverride,
          );
        }
      }
    }
    final destinationRules = destination == ObservabilityDestinationKind.local
        ? localOverrides
        : remoteOverrides;
    final destinationAction = _lookupOverrides(destinationRules, dataClass);
    if (destinationAction != null) {
      return _ResolvedRule(
        destinationAction,
        dataClass,
        ObservabilityPrivacyDecisionSource.destinationOverride,
      );
    }
    final globalAction = _lookupOverrides(globalOverrides, dataClass);
    if (globalAction != null) {
      return _ResolvedRule(
        globalAction,
        dataClass,
        ObservabilityPrivacyDecisionSource.globalOverride,
      );
    }
    final profileAction = _lookupProfile(
      _profileRules(profile, destination),
      dataClass,
    );
    if (profileAction != null) {
      return _ResolvedRule(
        profileAction,
        dataClass,
        ObservabilityPrivacyDecisionSource.profile,
      );
    }
    return _ResolvedRule(
      _defaultAction(profile, destination),
      dataClass,
      ObservabilityPrivacyDecisionSource.defaultRule,
    );
  }

  static bool _wins(_ResolvedRule candidate, _ResolvedRule current) {
    final actionComparison = _actionRank(candidate.action)
        .compareTo(_actionRank(current.action));
    if (actionComparison != 0) return actionComparison > 0;
    final sourceComparison = current.source.index.compareTo(
      candidate.source.index,
    );
    if (sourceComparison != 0) return sourceComparison > 0;
    return candidate.dataClass.wireName.compareTo(current.dataClass.wireName) <
        0;
  }

  static int _actionRank(ObservabilityPrivacyAction action) => switch (action) {
    ObservabilityPrivacyAction.allow => 0,
    ObservabilityPrivacyAction.mask => 1,
    ObservabilityPrivacyAction.deny => 2,
  };
}

Iterable<ObservabilityDataClass> _classesIn(
  ObservabilityPrivacyOverrides overrides,
) sync* {
  yield* overrides.allow;
  yield* overrides.mask;
  yield* overrides.deny;
}

final Set<ObservabilityDataClass> _builtInDiagnosticClasses =
    Set<ObservabilityDataClass>.unmodifiable(<ObservabilityDataClass>{
      ObservabilityDataClass.safe,
      ObservabilityDataClass.safeMetadata,
      ObservabilityDataClass.safeEnum,
      ObservabilityDataClass.safeCount,
      ObservabilityDataClass.safeDuration,
      ObservabilityDataClass.safeStatus,
      ObservabilityDataClass.safeRouteTemplate,
      ObservabilityDataClass.safeRuntimeType,
      ObservabilityDataClass.safeProtocolVersion,
      ObservabilityDataClass.http,
      ObservabilityDataClass.httpMethod,
      ObservabilityDataClass.httpRouteTemplate,
      ObservabilityDataClass.httpStatus,
      ObservabilityDataClass.httpErrorType,
      ObservabilityDataClass.httpPath,
      ObservabilityDataClass.httpQuery,
      ObservabilityDataClass.httpBody,
      ObservabilityDataClass.httpRequestBody,
      ObservabilityDataClass.httpResponseBody,
      ObservabilityDataClass.httpHeader,
      ObservabilityDataClass.httpAuthorization,
      ObservabilityDataClass.httpCookie,
      ObservabilityDataClass.httpTraceHeader,
      ObservabilityDataClass.httpContentType,
      ObservabilityDataClass.httpMultipart,
      ObservabilityDataClass.httpBinary,
      ObservabilityDataClass.credential,
      ObservabilityDataClass.password,
      ObservabilityDataClass.secret,
      ObservabilityDataClass.apiKey,
      ObservabilityDataClass.session,
      ObservabilityDataClass.cookie,
      ObservabilityDataClass.token,
      ObservabilityDataClass.httpToken,
      ObservabilityDataClass.accessToken,
      ObservabilityDataClass.refreshToken,
      ObservabilityDataClass.jwt,
      ObservabilityDataClass.dsn,
      ObservabilityDataClass.identity,
      ObservabilityDataClass.name,
      ObservabilityDataClass.email,
      ObservabilityDataClass.phone,
      ObservabilityDataClass.cpf,
      ObservabilityDataClass.cnpj,
      ObservabilityDataClass.address,
      ObservabilityDataClass.userId,
      ObservabilityDataClass.deviceId,
      ObservabilityDataClass.ipAddress,
      ObservabilityDataClass.uuid,
      ObservabilityDataClass.location,
      ObservabilityDataClass.storage,
      ObservabilityDataClass.storageQuery,
      ObservabilityDataClass.storageStatement,
      ObservabilityDataClass.storageTable,
      ObservabilityDataClass.storageValue,
      ObservabilityDataClass.storagePath,
      ObservabilityDataClass.file,
      ObservabilityDataClass.filePath,
      ObservabilityDataClass.fileName,
      ObservabilityDataClass.fileContent,
      ObservabilityDataClass.operation,
      ObservabilityDataClass.idempotencyKey,
      ObservabilityDataClass.requestId,
      ObservabilityDataClass.runId,
      ObservabilityDataClass.datasetKey,
      ObservabilityDataClass.checkpoint,
      ObservabilityDataClass.partition,
      ObservabilityDataClass.leaseOwner,
      ObservabilityDataClass.error,
      ObservabilityDataClass.errorType,
      ObservabilityDataClass.errorMessage,
      ObservabilityDataClass.errorStackTrace,
      ObservabilityDataClass.errorFingerprint,
    });

final class _ResolvedRule {
  const _ResolvedRule(this.action, this.dataClass, this.source);

  final ObservabilityPrivacyAction action;
  final ObservabilityDataClass dataClass;
  final ObservabilityPrivacyDecisionSource source;
}

ObservabilityPrivacyOverrides _freeze(ObservabilityPrivacyOverrides rules) =>
    ObservabilityPrivacyOverrides(
      allow: Set<ObservabilityDataClass>.unmodifiable(rules.allow),
      mask: Set<ObservabilityDataClass>.unmodifiable(rules.mask),
      deny: Set<ObservabilityDataClass>.unmodifiable(rules.deny),
    );

void _validateRules(String name, ObservabilityPrivacyOverrides rules) {
  final conflicts = <ObservabilityDataClass>{
    ...rules.allow.intersection(rules.mask),
    ...rules.allow.intersection(rules.deny),
    ...rules.mask.intersection(rules.deny),
  };
  if (conflicts.isNotEmpty) {
    throw ArgumentError.value(
      conflicts.map((value) => value.wireName).toList(growable: false),
      name,
      'contains classes assigned to multiple actions',
    );
  }
}

ObservabilityPrivacyAction? _lookupOverrides(
  ObservabilityPrivacyOverrides rules,
  ObservabilityDataClass dataClass,
) {
  for (final candidate in dataClass.hierarchy) {
    if (rules.deny.contains(candidate)) return ObservabilityPrivacyAction.deny;
    if (rules.mask.contains(candidate)) return ObservabilityPrivacyAction.mask;
    if (rules.allow.contains(candidate))
      return ObservabilityPrivacyAction.allow;
  }
  return null;
}

ObservabilityPrivacyAction? _lookupProfile(
  Map<String, ObservabilityPrivacyAction> rules,
  ObservabilityDataClass dataClass,
) {
  for (final candidate in dataClass.hierarchy) {
    final action = rules[candidate.wireName];
    if (action != null) return action;
  }
  return null;
}

Map<String, ObservabilityPrivacyAction> _profileRules(
  ObservabilityPrivacyProfile profile,
  ObservabilityDestinationKind destination,
) => switch ((profile, destination)) {
  (ObservabilityPrivacyProfile.strict, ObservabilityDestinationKind.local) =>
    _strictLocal,
  (ObservabilityPrivacyProfile.strict, ObservabilityDestinationKind.remote) =>
    _strictRemote,
  (ObservabilityPrivacyProfile.balanced, ObservabilityDestinationKind.local) =>
    _balancedLocal,
  (ObservabilityPrivacyProfile.balanced, ObservabilityDestinationKind.remote) =>
    _balancedRemote,
  (
    ObservabilityPrivacyProfile.diagnostic,
    ObservabilityDestinationKind.local,
  ) =>
    _diagnosticLocal,
  (
    ObservabilityPrivacyProfile.diagnostic,
    ObservabilityDestinationKind.remote,
  ) =>
    _diagnosticRemote,
};

ObservabilityPrivacyAction _defaultAction(
  ObservabilityPrivacyProfile profile,
  ObservabilityDestinationKind destination,
) => switch ((profile, destination)) {
  (ObservabilityPrivacyProfile.strict, _) => ObservabilityPrivacyAction.deny,
  (ObservabilityPrivacyProfile.balanced, ObservabilityDestinationKind.local) =>
    ObservabilityPrivacyAction.mask,
  (ObservabilityPrivacyProfile.balanced, ObservabilityDestinationKind.remote) =>
    ObservabilityPrivacyAction.deny,
  (ObservabilityPrivacyProfile.diagnostic, _) =>
    ObservabilityPrivacyAction.mask,
};

final Map<String, ObservabilityPrivacyAction> _strictLocal = _ruleTable(
  allow: const <String>[
    'safe',
    'http.method',
    'http.route_template',
    'http.status',
    'http.error_type',
    'error.type',
  ],
  mask: const <String>['operation'],
  deny: const <String>[
    'credential',
    'identity',
    'http.body',
    'http.header',
    'http.path',
    'http.query',
    'error.stack_trace',
    'storage',
    'file',
  ],
);

final Map<String, ObservabilityPrivacyAction> _strictRemote = _strictLocal;

final Map<String, ObservabilityPrivacyAction> _balancedLocal = _ruleTable(
  allow: const <String>[
    'safe',
    'http.method',
    'http.route_template',
    'http.status',
    'http.error_type',
    'error.type',
  ],
  mask: const <String>['operation', 'identity', 'error.message'],
  deny: const <String>[
    'credential',
    'http.body',
    'http.header',
    'http.path',
    'http.query',
    'storage',
    'file',
  ],
);

final Map<String, ObservabilityPrivacyAction> _balancedRemote = _ruleTable(
  allow: const <String>[
    'safe',
    'http.method',
    'http.route_template',
    'http.status',
    'http.error_type',
    'error.type',
  ],
  mask: const <String>['operation'],
  deny: const <String>[
    'identity',
    'credential',
    'http.body',
    'http.header',
    'http.path',
    'http.query',
    'storage',
    'file',
    'error.message',
    'error.stack_trace',
  ],
);

final Map<String, ObservabilityPrivacyAction> _diagnosticLocal = _ruleTable(
  allow: const <String>[
    'safe',
    'http.method',
    'http.route_template',
    'http.status',
    'http.error_type',
    'http.body',
    'http.header',
    'http.path',
    'http.query',
    'error.stack_trace',
  ],
  mask: const <String>['operation', 'identity', 'error'],
  deny: const <String>[
    'credential',
    'http.header.authorization',
    'http.header.cookie',
    'http.binary',
    'http.multipart',
    'file',
  ],
);

final Map<String, ObservabilityPrivacyAction> _diagnosticRemote =
    Map<String, ObservabilityPrivacyAction>.unmodifiable(
      <String, ObservabilityPrivacyAction>{
        ..._diagnosticLocal,
        'http.path': ObservabilityPrivacyAction.mask,
        'http.query': ObservabilityPrivacyAction.mask,
        'error.stack_trace': ObservabilityPrivacyAction.mask,
      },
    );

Map<String, ObservabilityPrivacyAction> _ruleTable({
  required List<String> allow,
  required List<String> mask,
  required List<String> deny,
}) => Map<String, ObservabilityPrivacyAction>.unmodifiable(
  <String, ObservabilityPrivacyAction>{
    for (final value in allow) value: ObservabilityPrivacyAction.allow,
    for (final value in mask) value: ObservabilityPrivacyAction.mask,
    for (final value in deny) value: ObservabilityPrivacyAction.deny,
  },
);

void _validateDestinationName(String name) {
  if (!RegExp(r'^[a-z][a-z0-9_-]{1,39}$').hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'must be 2-40 lowercase ASCII characters',
    );
  }
}
