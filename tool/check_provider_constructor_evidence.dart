import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:crypto/crypto.dart';

/// Verifies the fail-closed provider constructor compatibility registry.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final errors = await checkProviderConstructorEvidence(root);
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Provider constructor evidence passed: ObjectBox 5.3.2 primary '
    'probe rejected, scoped traditional fixture generated and runtime-bound.',
  );
}

/// Returns every registry or evidence violation without changing the fixture.
Future<List<String>> checkProviderConstructorEvidence(Directory root) async {
  final errors = <String>[];
  final registryFile = File(
    '${root.path}/tool/provider_constructor_evidence.json',
  );
  if (!registryFile.existsSync()) {
    return <String>['Provider constructor evidence registry is missing.'];
  }
  Map<String, Object?> registry;
  try {
    registry = _object(jsonDecode(registryFile.readAsStringSync()));
  } on Object catch (error) {
    return <String>['Provider constructor registry is invalid: $error'];
  }
  _expectKeys(
    registry,
    <String>{'schemaVersion', 'policy', 'entries'},
    'root',
    errors,
  );
  if (registry['schemaVersion'] != 1) {
    errors.add('Provider constructor registry schema must be 1.');
  }
  final policy = _objectOrNull(registry['policy']);
  if (policy != null) {
    _expectKeys(
      policy,
      <String>{
        'providerOwnedPrimaryDeclaringVar',
        'traditionalConstructor',
        'exceptionScope',
      },
      'policy',
      errors,
    );
  }
  if (policy == null ||
      policy['providerOwnedPrimaryDeclaringVar'] != 'allowed' ||
      policy['traditionalConstructor'] !=
          'denied_without_specific_generator_or_runtime_failure' ||
      policy['exceptionScope'] !=
          'exact_provider_generator_version_and_fixture') {
    errors.add('Provider constructor default policy is not fail-closed.');
  }
  final rawEntries = registry['entries'];
  if (rawEntries is! List<Object?> || rawEntries.length != 1) {
    errors.add('Registry must contain the one currently evidenced provider.');
    return errors;
  }
  final entry = _objectOrNull(rawEntries.single);
  if (entry == null) {
    errors.add('Provider constructor entry is not an object.');
    return errors;
  }
  _expectKeys(
    entry,
    <String>{
      'provider',
      'providerVersion',
      'generator',
      'generatorVersion',
      'resolvedAnalyzerVersion',
      'resolvedAnalyzerLanguageVersion',
      'decision',
      'reasonCode',
      'scope',
      'primaryCandidate',
      'failureEvidence',
      'acceptedFixture',
      'runtimeEvidence',
    },
    'entry',
    errors,
  );
  if (entry['provider'] != 'objectbox' ||
      entry['providerVersion'] != '5.3.2' ||
      entry['generator'] != 'objectbox_generator' ||
      entry['generatorVersion'] != '5.3.2' ||
      entry['resolvedAnalyzerVersion'] != '10.2.0' ||
      entry['resolvedAnalyzerLanguageVersion'] != '3.12.0' ||
      entry['decision'] != 'traditional_constructor_exception' ||
      entry['reasonCode'] !=
          'generator_rejects_primary_constructor_language_feature') {
    errors.add('ObjectBox constructor decision or exact versions changed.');
  }

  final fixturePubspec = File(
    '${root.path}/tool/objectbox_native_fixture/pubspec.yaml',
  );
  final fixtureLock = File(
    '${root.path}/tool/objectbox_native_fixture/pubspec.lock',
  );
  if (!fixturePubspec.existsSync() || !fixtureLock.existsSync()) {
    errors.add('ObjectBox fixture pubspec or lock is missing.');
    return errors;
  }
  final pubspec = fixturePubspec.readAsStringSync();
  final lock = fixtureLock.readAsStringSync();
  if (!pubspec.contains('objectbox: ^5.3.2') ||
      !pubspec.contains('objectbox_generator: ^5.3.2')) {
    errors.add('ObjectBox fixture constraints no longer select 5.3.2.');
  }
  for (final expected in <String, String>{
    'objectbox': '5.3.2',
    'objectbox_generator': '5.3.2',
    'analyzer': '10.2.0',
  }.entries) {
    final actual = _lockedVersion(lock, expected.key);
    if (actual != expected.value) {
      errors.add(
        'Fixture locks ${expected.key} at $actual; expected ${expected.value}.',
      );
    }
  }

  final scope = _objectOrNull(entry['scope']);
  if (scope == null ||
      scope['annotation'] != 'Entity' ||
      scope['entity'] != 'FixtureEntity' ||
      scope['fixture'] != 'tool/objectbox_native_fixture') {
    errors.add('ObjectBox traditional exception scope is not exact.');
  }
  final candidate = _objectOrNull(entry['primaryCandidate']);
  final failure = _objectOrNull(entry['failureEvidence']);
  final accepted = _objectOrNull(entry['acceptedFixture']);
  final runtime = _objectOrNull(entry['runtimeEvidence']);
  if (candidate == null ||
      failure == null ||
      accepted == null ||
      runtime == null) {
    errors.add('ObjectBox evidence sections are incomplete.');
    return errors;
  }
  _expectKeys(
    scope!,
    <String>{'annotation', 'entity', 'fixture'},
    'scope',
    errors,
  );
  _expectKeys(
    candidate,
    <String>{'path', 'sha256', 'constructorForm'},
    'primaryCandidate',
    errors,
  );
  _expectKeys(
    failure,
    <String>{'path', 'sha256', 'phase', 'diagnostic'},
    'failureEvidence',
    errors,
  );
  _expectKeys(
    accepted,
    <String>{
      'sourcePath',
      'sourceSha256',
      'constructorForm',
      'generatedPath',
      'generatedSha256',
      'modelPath',
      'modelSha256',
    },
    'acceptedFixture',
    errors,
  );
  _expectKeys(
    runtime,
    <String>{'path', 'sha256', 'command', 'required'},
    'runtimeEvidence',
    errors,
  );
  if (candidate['constructorForm'] != 'primary_declaring_var') {
    errors.add('The preferred provider constructor is not primary `var`.');
  }
  if (failure['phase'] != 'objectbox_generator:resolver' ||
      failure['diagnostic'] !=
          'This requires the primary-constructors language feature to be enabled.') {
    errors.add('Primary incompatibility is not generator-specific.');
  }
  if (accepted['constructorForm'] != 'traditional_named_properties') {
    errors.add('Accepted fixture constructor form is not explicit.');
  }
  if (runtime['command'] != 'flutter test test/native_store_test.dart' ||
      runtime['required'] != true) {
    errors.add('Native runtime evidence is not mandatory.');
  }

  final evidenceFiles = <({String path, String digest})>[];
  void retain(Map<String, Object?> section, String pathKey, String digestKey) {
    final path = section[pathKey];
    final digest = section[digestKey];
    if (path is! String || digest is! String) {
      errors.add('Evidence $pathKey/$digestKey must be strings.');
      return;
    }
    evidenceFiles.add((path: path, digest: digest));
  }

  retain(candidate, 'path', 'sha256');
  retain(failure, 'path', 'sha256');
  retain(accepted, 'sourcePath', 'sourceSha256');
  retain(accepted, 'generatedPath', 'generatedSha256');
  retain(accepted, 'modelPath', 'modelSha256');
  retain(runtime, 'path', 'sha256');
  for (final evidence in evidenceFiles) {
    final file = _evidenceFile(root, evidence.path, errors);
    if (file == null) continue;
    final actual = await sha256.bind(file.openRead()).first;
    if (actual.toString() != evidence.digest) {
      errors.add('Evidence digest mismatch: ${evidence.path}.');
    }
  }

  final candidatePath = candidate['path'];
  final acceptedPath = accepted['sourcePath'];
  final generatedPath = accepted['generatedPath'];
  final modelPath = accepted['modelPath'];
  final failurePath = failure['path'];
  if (candidatePath is String) {
    final file = _evidenceFile(root, candidatePath, errors);
    if (file != null) _checkPrimaryCandidate(file, errors);
  }
  if (acceptedPath is String) {
    final file = _evidenceFile(root, acceptedPath, errors);
    if (file != null) _checkTraditionalFixture(file, errors);
  }
  if (generatedPath is String) {
    final file = _evidenceFile(root, generatedPath, errors);
    if (file != null) {
      final source = file.readAsStringSync();
      if (!source.contains('FixtureEntity(id: idParam, value: valueParam)') ||
          !source.contains('object.id = id;')) {
        errors.add(
          'Generated ObjectBox binding lacks constructor/ID evidence.',
        );
      }
    }
  }
  if (modelPath is String) {
    final file = _evidenceFile(root, modelPath, errors);
    if (file != null) _checkObjectBoxModel(file, errors);
  }
  if (failurePath is String) {
    final file = _evidenceFile(root, failurePath, errors);
    if (file != null) {
      final source = file.readAsStringSync();
      for (final marker in <String>[
        'generator: objectbox_generator 5.3.2',
        'resolvedAnalyzer: 10.2.0',
        'exitCode: 1',
        'phase: objectbox_generator:resolver',
        failure['diagnostic']! as String,
      ]) {
        if (!source.contains(marker)) {
          errors.add('Failure evidence is missing `$marker`.');
        }
      }
    }
  }
  return errors;
}

void _checkPrimaryCandidate(File file, List<String> errors) {
  final parsed = parseString(
    content: file.readAsStringSync(),
    path: file.path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  if (parsed.errors.any(
    (diagnostic) => diagnostic.severity == Severity.error,
  )) {
    errors.add('Primary `var` evidence is not valid current Dart syntax.');
    return;
  }
  final classes = parsed.unit.declarations.whereType<ClassDeclaration>();
  final entity = classes.where(
    (value) => value.namePart.typeName.lexeme == 'FixtureEntity',
  );
  final declaration = entity.firstOrNull;
  final primary = switch (declaration?.namePart) {
    final PrimaryConstructorDeclaration value => value,
    _ => null,
  };
  final parameters = primary?.formalParameters.parameters;
  if (declaration == null ||
      !_hasAnnotation(declaration, 'Entity') ||
      parameters == null ||
      parameters.length != 2 ||
      parameters.any(
        (parameter) =>
            parameter is! RegularFormalParameter ||
            parameter.varKeyword == null,
      )) {
    errors.add('Primary evidence must use two declaring `var` parameters.');
  }
}

void _checkTraditionalFixture(File file, List<String> errors) {
  final parsed = parseString(
    content: file.readAsStringSync(),
    path: file.path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  final entity = parsed.unit.declarations
      .whereType<ClassDeclaration>()
      .where((value) => value.namePart.typeName.lexeme == 'FixtureEntity')
      .firstOrNull;
  if (entity == null ||
      !_hasAnnotation(entity, 'Entity') ||
      entity.namePart is PrimaryConstructorDeclaration ||
      entity.body.members.whereType<ConstructorDeclaration>().length != 1) {
    errors.add('Accepted ObjectBox entity is not the scoped traditional form.');
  }
}

void _checkObjectBoxModel(File file, List<String> errors) {
  final model = _objectOrNull(jsonDecode(file.readAsStringSync()));
  final entities = model?['entities'];
  final entity = entities is List<Object?> && entities.length == 1
      ? _objectOrNull(entities.single)
      : null;
  final properties = entity?['properties'];
  final names = properties is List<Object?>
      ? properties
            .map(_objectOrNull)
            .whereType<Map<String, Object?>>()
            .map((value) => value['name'])
            .toList()
      : const <Object?>[];
  if (entity?['name'] != 'FixtureEntity' ||
      names.length != 2 ||
      !names.contains('id') ||
      !names.contains('value')) {
    errors.add(
      'ObjectBox model does not own exactly the fixture entity fields.',
    );
  }
}

bool _hasAnnotation(ClassDeclaration declaration, String name) => declaration
    .metadata
    .any((annotation) => annotation.name.toSource().split('.').last == name);

File? _evidenceFile(Directory root, String relative, List<String> errors) {
  if (relative.startsWith('/') ||
      relative.contains('\\') ||
      relative.split('/').contains('..')) {
    errors.add('Evidence path is unsafe: $relative.');
    return null;
  }
  final file = File('${root.path}/$relative');
  if (!file.existsSync()) {
    errors.add('Evidence file is missing: $relative.');
    return null;
  }
  if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.link) {
    errors.add('Evidence file cannot be a symlink: $relative.');
    return null;
  }
  final rootPath = root.resolveSymbolicLinksSync();
  final resolved = file.resolveSymbolicLinksSync();
  final prefix = '$rootPath${Platform.pathSeparator}';
  if (!resolved.startsWith(prefix)) {
    errors.add('Evidence file escapes through a symlink: $relative.');
    return null;
  }
  return file;
}

String? _lockedVersion(String lock, String package) {
  final lines = lock.split(RegExp(r'\r?\n'));
  final start = lines.indexOf('  $package:');
  if (start < 0) return null;
  for (var index = start + 1; index < lines.length; index += 1) {
    final line = lines[index];
    if (line.startsWith('  ') && !line.startsWith('    ')) break;
    final match = RegExp(r'^    version: "([^"]+)"$').firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

void _expectKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String context,
  List<String> errors,
) {
  final actual = value.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    errors.add('$context keys differ: expected $expected, got $actual.');
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an object.');
  }
  return value;
}

Map<String, Object?>? _objectOrNull(Object? value) =>
    value is Map<String, Object?> ? value : null;
