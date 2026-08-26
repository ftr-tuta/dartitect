import 'dart:io';
import 'dart:math';

/// A structured policy or request validation failure.
final class DartitectMcpException implements Exception {
  /// Creates an MCP domain failure.
  const DartitectMcpException(
    this.code,
    this.message, {
    this.retryable = false,
  });

  /// Stable machine-readable error code.
  final String code;

  /// Sanitized actionable description.
  final String message;

  /// Whether retrying after a state change may succeed.
  final bool retryable;

  @override
  String toString() => message;
}

/// Security and resource limits for a [DartitectMcpServer].
///
/// All roots are canonicalized during construction. Writes remain disabled
/// unless [allowWrites] is explicitly set.
final class DartitectMcpPolicy {
  /// Creates an immutable server policy.
  DartitectMcpPolicy({
    required Iterable<Directory> allowedRoots,
    this.allowWrites = false,
    this.planTtl = const Duration(minutes: 10),
    this.defaultResultLimit = 100,
    this.maxResultLimit = 500,
    this.operationTimeout = const Duration(minutes: 2),
    DateTime Function()? now,
    String Function()? createPlanId,
  }) : now = now ?? DateTime.now,
       createPlanId = createPlanId ?? _securePlanId,
       allowedRoots = List<Directory>.unmodifiable(
         allowedRoots.map(_canonicalDirectory),
       ) {
    if (this.allowedRoots.isEmpty) {
      throw ArgumentError.value(
        allowedRoots,
        'allowedRoots',
        'at least one root is required',
      );
    }
    if (planTtl <= Duration.zero) {
      throw ArgumentError.value(planTtl, 'planTtl', 'must be positive');
    }
    if (defaultResultLimit < 1 ||
        maxResultLimit < defaultResultLimit ||
        maxResultLimit > 5000) {
      throw ArgumentError('Invalid MCP result limits.');
    }
    if (operationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        operationTimeout,
        'operationTimeout',
        'must be positive',
      );
    }
    final names = rootNames.map(
      (name) => Platform.isWindows ? name.toLowerCase() : name,
    );
    if (names.toSet().length != names.length) {
      throw ArgumentError('Allowed roots must have unique directory names.');
    }
  }

  /// Canonical directories an MCP request may access.
  final List<Directory> allowedRoots;

  /// Whether reviewed plans may be committed.
  final bool allowWrites;

  /// Lifetime of an opaque, single-use change plan.
  final Duration planTtl;

  /// Result page size used when a request omits its limit.
  final int defaultResultLimit;

  /// Hard upper bound for a result page.
  final int maxResultLimit;

  /// Maximum duration of one tool operation.
  final Duration operationTimeout;

  /// Injected clock used for deterministic expiry tests.
  final DateTime Function() now;

  /// Injected opaque ID factory used for deterministic tests.
  final String Function() createPlanId;

  /// Stable non-sensitive names used to select among multiple roots.
  List<String> get rootNames => <String>[
    for (final root in allowedRoots) _basename(root.path),
  ];

  /// Resolves a model-supplied relative [path] inside an authorized root.
  ///
  /// Absolute paths, traversal, missing roots, and symbolic-link escapes are
  /// rejected before a project service is created.
  Future<Directory> resolveProject({String? rootName, String? path}) async {
    final base = _selectRoot(rootName);
    final relative = path?.trim() ?? '';
    _validateRelativePath(relative);
    final candidate = relative.isEmpty || relative == '.'
        ? base
        : Directory(_join(base.path, relative)).absolute;
    if (!_isInside(base.path, candidate.path)) {
      throw const DartitectMcpException(
        'path_outside_root',
        'The requested project path is outside the configured root.',
      );
    }
    if (!await candidate.exists()) {
      throw const DartitectMcpException(
        'root_not_found',
        'The requested project directory does not exist.',
      );
    }
    final canonical = Directory(await candidate.resolveSymbolicLinks());
    if (!_isInside(base.path, canonical.path)) {
      throw const DartitectMcpException(
        'symlink_escape',
        'The requested path crosses a symbolic link outside the configured root.',
      );
    }
    return canonical;
  }

  Directory _selectRoot(String? requested) {
    if (requested == null || requested.isEmpty) {
      if (allowedRoots.length == 1) return allowedRoots.single;
      throw const DartitectMcpException(
        'root_required',
        'Select a configured root by its non-sensitive name.',
      );
    }
    if (requested.contains('/') ||
        requested.contains('\\') ||
        requested == '.' ||
        requested == '..') {
      throw const DartitectMcpException(
        'invalid_root',
        'The root selector must be a configured root name.',
      );
    }
    for (var index = 0; index < allowedRoots.length; index += 1) {
      if (rootNames[index] == requested) return allowedRoots[index];
    }
    throw const DartitectMcpException(
      'root_not_allowed',
      'The selected root is not authorized by this server.',
    );
  }

  static void _validateRelativePath(String path) {
    if (path.isEmpty || path == '.') return;
    if (path.startsWith('/') ||
        path.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      throw const DartitectMcpException(
        'absolute_path_rejected',
        'Project paths supplied to tools must be relative.',
      );
    }
    final segments = path.replaceAll('\\', '/').split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw const DartitectMcpException(
        'path_traversal',
        'Project paths must not contain traversal or empty segments.',
      );
    }
  }

  static Directory _canonicalDirectory(Directory root) {
    final absolute = root.absolute;
    if (!absolute.existsSync()) {
      throw ArgumentError.value(root.path, 'allowedRoots', 'root is missing');
    }
    final canonical = Directory(absolute.resolveSymbolicLinksSync());
    if (canonical.parent.path == canonical.path) {
      throw ArgumentError(
        'The filesystem root cannot be an authorized Dartitect root.',
      );
    }
    return canonical;
  }

  static bool _isInside(String root, String path) =>
      path == root || path.startsWith('$root${Platform.pathSeparator}');

  static String _join(String left, String right) =>
      '$left${Platform.pathSeparator}${right.replaceAll('/', Platform.pathSeparator)}';

  static String _basename(String path) => path
      .split(Platform.pathSeparator)
      .where((segment) => segment.isNotEmpty)
      .last;

  static String _securePlanId() {
    final random = Random.secure();
    return List<String>.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      growable: false,
    ).join();
  }
}
