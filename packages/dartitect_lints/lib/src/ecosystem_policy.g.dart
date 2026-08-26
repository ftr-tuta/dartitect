// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: tool/ecosystem_policy.json (schema 2).
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';

enum DartitectEcosystemDecision {
  approved,
  advisoryAlternative,
  reviewedException,
  prohibitedNativeStrict,
  unreviewed,
}

final class DartitectLintEcosystemRecord {
  const DartitectLintEcosystemRecord(
    this.decision, {
    this.replacement,
    this.conflictsWith = const <String>[],
  });

  final DartitectEcosystemDecision decision;
  final String? replacement;
  final List<String> conflictsWith;
}

final class DartitectLintEcosystemPolicy {
  const DartitectLintEcosystemPolicy();

  DartitectLintEcosystemRecord explain(String package, [String? path]) {
    final base = _records[package] ?? _unreviewed;
    if (base.decision == DartitectEcosystemDecision.prohibitedNativeStrict) {
      return base;
    }
    final overlay = path == null ? null : _overlayAt(package, path);
    return overlay?.record ?? base;
  }

  bool allowsExceptionAt(String package, String path, DateTime now) {
    final overlay = _overlayAt(package, path);
    return overlay != null && !now.isAfter(overlay.expiresOn);
  }

  bool hasActiveConflict(String package, String path) {
    final record = explain(package, path);
    if (record.decision != DartitectEcosystemDecision.advisoryAlternative ||
        record.conflictsWith.isEmpty) {
      return false;
    }
    final dependencies = _dependenciesFor(path);
    return record.conflictsWith.any(dependencies.contains);
  }
}

final class _OverlayEntry {
  const _OverlayEntry({
    required this.package,
    required this.record,
    required this.expiresOn,
    required this.paths,
  });

  final String package;
  final DartitectLintEcosystemRecord record;
  final DateTime expiresOn;
  final List<String> paths;
}

_OverlayEntry? _overlayAt(String package, String sourcePath) {
  final root = _nearestRoot(sourcePath);
  if (root == null) return null;
  final entries = _overlayCache.putIfAbsent(root, () => _readOverlay(root));
  final relative = _relativeLibraryPath(sourcePath);
  final now = DateTime.now().toUtc();
  for (final entry in entries) {
    if (entry.package == package &&
        !now.isAfter(entry.expiresOn) &&
        entry.paths.any((glob) => _globMatches(glob, relative))) {
      return entry;
    }
  }
  return null;
}

List<_OverlayEntry> _readOverlay(String root) {
  final file = File(
    '$root${Platform.pathSeparator}.dartitect'
    '${Platform.pathSeparator}ecosystem-policy.json',
  );
  if (!file.existsSync()) return const <_OverlayEntry>[];
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on Object {
    return const <_OverlayEntry>[];
  }
  if (decoded is! Map<String, Object?> ||
      decoded['schemaVersion'] != 1 ||
      decoded['entries'] is! List<Object?>) {
    return const <_OverlayEntry>[];
  }
  final output = <_OverlayEntry>[];
  for (final raw in decoded['entries']! as List<Object?>) {
    if (raw is! Map<String, Object?> ||
        raw['package'] is! String ||
        !_packageName.hasMatch(raw['package']! as String) ||
        raw['decision'] is! String ||
        raw['owner'] is! String ||
        (raw['owner']! as String).trim().isEmpty ||
        raw['reason'] is! String ||
        (raw['reason']! as String).trim().isEmpty ||
        raw['expiresOn'] is! String ||
        raw['paths'] is! List<Object?> ||
        (raw['paths']! as List<Object?>).isEmpty ||
        raw['directOwners'] != null &&
            (raw['directOwners'] is! List<Object?> ||
                (raw['directOwners']! as List<Object?>).isEmpty)) {
      continue;
    }
    final package = raw['package']! as String;
    final base = _records[package] ?? _unreviewed;
    if (base.decision == DartitectEcosystemDecision.prohibitedNativeStrict) {
      continue;
    }
    final decision = switch (raw['decision']) {
      'approved' => DartitectEcosystemDecision.approved,
      'advisory_alternative' => DartitectEcosystemDecision.advisoryAlternative,
      'reviewed_exception' => DartitectEcosystemDecision.reviewedException,
      _ => null,
    };
    final expiresOn = DateTime.tryParse('${raw['expiresOn']}T23:59:59Z');
    final rawPaths = raw['paths']! as List<Object?>;
    final rawOwners = raw['directOwners'];
    final paths = rawPaths.whereType<String>().toList();
    if (decision == null ||
        expiresOn == null ||
        paths.length != rawPaths.length ||
        rawOwners is List<Object?> &&
            (rawOwners.whereType<String>().length != rawOwners.length ||
                rawOwners.whereType<String>().any(
                  (owner) => !_packageName.hasMatch(owner),
                )) ||
        paths.any(_unsafePath)) {
      continue;
    }
    output.add(
      _OverlayEntry(
        package: package,
        record: DartitectLintEcosystemRecord(
          decision,
          replacement: raw['replacement'] as String?,
        ),
        expiresOn: expiresOn,
        paths: List<String>.unmodifiable(paths),
      ),
    );
  }
  return List<_OverlayEntry>.unmodifiable(output);
}

Set<String> _dependenciesFor(String sourcePath) {
  final root = _nearestRoot(sourcePath);
  if (root == null) return const <String>{};
  return _dependencyCache.putIfAbsent(root, () {
    final file = File('$root${Platform.pathSeparator}pubspec.yaml');
    if (!file.existsSync()) return const <String>{};
    final dependencies = <String>{};
    for (final match in RegExp(
      r'^  ([a-zA-Z_][a-zA-Z0-9_]*):',
      multiLine: true,
    ).allMatches(file.readAsStringSync())) {
      dependencies.add(match.group(1)!);
    }
    return Set<String>.unmodifiable(dependencies);
  });
}

String? _nearestRoot(String sourcePath) {
  var directory = File(sourcePath).absolute.parent;
  while (true) {
    if (File('${directory.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

String _relativeLibraryPath(String sourcePath) {
  final normalized = sourcePath.replaceAll('\\', '/');
  final lib = normalized.lastIndexOf('/lib/');
  return lib < 0 ? normalized.split('/').last : normalized.substring(lib + 1);
}

bool _unsafePath(String path) =>
    path.isEmpty ||
    path == '*' ||
    path == '**' ||
    path == '**/*' ||
    path.startsWith('/') ||
    path.contains('\\') ||
    path.split('/').contains('..');

bool _globMatches(String glob, String path) {
  final pattern = StringBuffer('^');
  for (var index = 0; index < glob.length; index += 1) {
    final character = glob[index];
    if (character == '*' && index + 1 < glob.length && glob[index + 1] == '*') {
      pattern.write('.*');
      index += 1;
    } else if (character == '*') {
      pattern.write('[^/]*');
    } else if (character == '?') {
      pattern.write('[^/]');
    } else {
      pattern.write(RegExp.escape(character));
    }
  }
  pattern.write(r'$');
  return RegExp(pattern.toString()).hasMatch(path);
}

final _overlayCache = <String, List<_OverlayEntry>>{};
final _dependencyCache = <String, Set<String>>{};
final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');

const _approved = DartitectLintEcosystemRecord(
  DartitectEcosystemDecision.approved,
);
const _reviewed = DartitectLintEcosystemRecord(
  DartitectEcosystemDecision.reviewedException,
);
const _unreviewed = DartitectLintEcosystemRecord(
  DartitectEcosystemDecision.unreviewed,
);

const _records = <String, DartitectLintEcosystemRecord>{
  'app_tracking_transparency': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'dartitect_privacy',
  ),
  'bloc': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and Dartitect Commands/resources',
  ),
  'brasil_fields': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'dartitect_locale_br for CEP-only values',
  ),
  'build_runner': _approved,
  'collection': _approved,
  'crypto': _approved,
  'dart_polylabel2': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'dartitect_geometry',
  ),
  'dart_style': _approved,
  'dio': _approved,
  'elementary': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit ViewModels',
  ),
  'flutter': _approved,
  'flutter_bloc': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and Dartitect Commands/resources',
  ),
  'flutter_image_compress': _reviewed,
  'flutter_localizations': _approved,
  'flutter_mobx': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and Dartitect resources',
  ),
  'flutter_modular': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'flutter_native_splash': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement:
        'consumer-owned native assets plus dartitect_flutter FirstFrameGate',
  ),
  'flutter_pdfview': _reviewed,
  'flutter_riverpod': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and Dartitect Commands/resources',
  ),
  'flutter_secure_storage': _reviewed,
  'freezed': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'dartitect model sync for bounded value boilerplate',
  ),
  'freezed_annotation': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'DartitectValue for bounded value boilerplate',
  ),
  'gal': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'dartitect_media',
  ),
  'get': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'get_it': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'get_it_mixin': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'go_router': _approved,
  'hooks_riverpod': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and Dartitect Commands/resources',
  ),
  'hydrated_bloc': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'consumer-owned persistence with Dartitect resources',
  ),
  'image': _reviewed,
  'image_picker': _approved,
  'injectable': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'intl': _approved,
  'json_annotation': _approved,
  'json_serializable': _approved,
  'lottie': _reviewed,
  'mapbox_maps_flutter': _approved,
  'mobx': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and Dartitect resources',
  ),
  'objectbox': _approved,
  'objectbox_flutter_libs': _approved,
  'objectbox_generator': _approved,
  'package_info_plus': _approved,
  'path': _approved,
  'path_provider': _approved,
  'pdf': _reviewed,
  'printing': _reviewed,
  'pro_image_editor': _reviewed,
  'provider': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'retrofit': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'explicit clients over dartitect_dio DioJsonClient',
  ),
  'retrofit_generator': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'explicit endpoint clients',
  ),
  'riverpod': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and Dartitect Commands/resources',
  ),
  'riverpod_annotation': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'riverpod_generator': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'sentry': _approved,
  'sentry_dio': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'one reviewed Dio instrumentation path',
    conflictsWith: <String>['dartitect_dio'],
  ),
  'sentry_flutter': _approved,
  'share_plus': _approved,
  'shared_preferences': _approved,
  'signals': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'Dartitect resources and native listenables',
  ),
  'signals_flutter': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'Dartitect resources and native listenables',
  ),
  'stacked': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit ViewModels',
  ),
  'url_launcher': _approved,
  'uuid': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'SecureUuidV4Generator when only UUID v4 is required',
  ),
  'watch_it': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.prohibitedNativeStrict,
    replacement: 'constructor injection and explicit composition roots',
  ),
  'workmanager': DartitectLintEcosystemRecord(
    DartitectEcosystemDecision.advisoryAlternative,
    replacement: 'consumer-owned scheduling port around the native scheduler',
  ),
};
