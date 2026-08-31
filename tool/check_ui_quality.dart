import 'dart:convert';
import 'dart:io';

const _entrypoints = <String>[
  'package:dartitect_flutter/dartitect_flutter_ui.dart',
  'package:dartitect_flutter_testing/dartitect_flutter_testing.dart',
];
const _builders = <String>[
  'DartitectFormSnapshotBuilder',
  'DartitectQueryStateBuilder',
  'ResourcePresentationBuilder',
];
const _diagnostics = <String>[
  'DT3001',
  'DT3002',
  'DT3101',
  'DT3102',
  'DT3103',
  'DT3104',
  'DT3105',
  'DT3106',
];
const _sizes = <String>[
  '360x640',
  '430x932',
  '768x1024',
  '1024x768',
  '1440x900',
];

Future<void> main(List<String> arguments) async {
  try {
    final root = _root(arguments);
    final contract = _map(
      jsonDecode(
        File('${root.path}/tool/ui_quality_contract.json').readAsStringSync(),
      ),
    );
    final failures = <String>[];
    void require(bool condition, String message) {
      if (!condition) failures.add(message);
    }

    require(contract['schemaVersion'] == 1, 'Unsupported contract schema.');
    require(contract['artifact'] == 'ui-quality-v1', 'Wrong artifact name.');
    require(contract['goal'] == 'V1S-18', 'Wrong goal.');
    require(contract['releaseVersion'] == '1.0.0', 'Wrong cohort version.');
    final topology = _map(contract['topology']);
    require(topology['packages'] == 25, 'Expected 25 packages.');
    require(topology['publicEntrypoints'] == 32, 'Expected 32 entrypoints.');
    require(
      _same(_strings(contract['entrypoints']), _entrypoints),
      'UI entrypoint evidence is incomplete.',
    );
    require(
      _same(_strings(contract['builders']), _builders),
      'Builder evidence is incomplete.',
    );
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));

    final matrix = _list(contract['matrix']).map(_map).toList();
    require(matrix.length == 5, 'The paired matrix must contain five rows.');
    require(
      _same(matrix.map((row) => '${row['size']}').toList(), _sizes),
      'The paired matrix sizes differ from the contract.',
    );
    require(
      matrix.map((row) => row['textScale']).toSet().containsAll(<Object?>{
            1.0,
            2.0,
          }) &&
          matrix.map((row) => row['direction']).toSet().containsAll(<Object?>{
            'ltr',
            'rtl',
          }) &&
          matrix.map((row) => row['brightness']).toSet().containsAll(<Object?>{
            'light',
            'dark',
          }) &&
          matrix.any((row) => row['highContrast'] == true) &&
          matrix.any((row) => row['reducedMotion'] == true),
      'The paired matrix omits a required environment.',
    );

    final parity = _map(contract['diagnosticParity']);
    final declaredDiagnostics = <String>{
      ..._strings(parity['errors']),
      ..._strings(parity['warnings']),
    };
    require(
      declaredDiagnostics.length == _diagnostics.length &&
          declaredDiagnostics.containsAll(_diagnostics),
      'CLI/analyzer diagnostic evidence is incomplete.',
    );
    final corpus = _map(
      jsonDecode(_read(root, '${parity['corpus']}', failures)),
    );
    final diagnosticMap = _map(corpus['diagnosticMap']);
    require(
      diagnosticMap.values.toSet().containsAll(_diagnostics),
      'The parity corpus does not cover every UI diagnostic.',
    );
    _mustExist(root, '${parity['checker']}', failures);

    final api = _map(
      jsonDecode(_read(root, 'tool/api_surface.snapshot.json', failures)),
    );
    final surfaces = _map(api['entrypoints']);
    for (final entrypoint in _entrypoints) {
      final relative =
          'packages/${entrypoint.substring('package:'.length).replaceFirst('/', '/lib/')}';
      require(
        surfaces.containsKey(relative),
        'API snapshot lacks $entrypoint.',
      );
    }

    final matrixSource = _read(
      root,
      'packages/dartitect_flutter_testing/lib/src/ui_matrix.dart',
      failures,
    );
    for (final size in _sizes) {
      require(
        matrixSource.contains('Size(${size.replaceFirst('x', ', ')})'),
        'Matrix implementation lacks $size.',
      );
    }

    final skill = '${contract['skill']}';
    require(
      _read(root, skill, failures).contains('dartitect-ui'),
      'Managed skill is stale.',
    );
    final scaffold = _read(root, '${contract['scaffold']}', failures);
    for (final token in <String>[
      'ThemeData(useMaterial3: true)',
      'GlobalMaterialLocalizations.delegate',
      'testDartitectUiMatrix(',
      'NavigationBar(',
      'NavigationRail(',
    ]) {
      require(scaffold.contains(token), 'App scaffold lacks $token.');
    }

    final canary = _map(contract['canary']);
    final canaryRoot = '${canary['root']}';
    final canarySources = <String>[
      _read(root, '$canaryRoot/lib/main.dart', failures),
      _read(
        root,
        '$canaryRoot/lib/presentation/ui_quality_shell.dart',
        failures,
      ),
      _read(
        root,
        '$canaryRoot/lib/presentation/ui_quality_state_gallery.dart',
        failures,
      ),
      _read(root, '$canaryRoot/test/ui_quality_matrix_test.dart', failures),
      _read(
        root,
        '$canaryRoot/test/ui_quality_state_gallery_test.dart',
        failures,
      ),
    ].join('\n');
    for (final token in _strings(canary['controls'])) {
      require(canarySources.contains(token), 'UI canary lacks $token.');
    }
    for (final token in _strings(canary['states'])) {
      require(canarySources.contains(token), 'UI canary lacks $token state.');
    }
    for (final relative in <String>[
      ..._strings(canary['tests']),
      ..._strings(canary['goldens']),
    ]) {
      _mustExist(root, '$canaryRoot/$relative', failures);
    }
    for (final platform in _strings(canary['platformBuilds'])) {
      _mustExist(root, '$canaryRoot/$platform', failures);
    }
    final workflow = _read(root, '.github/workflows/ci.yaml', failures);
    for (final command in <String>[
      'flutter build apk --debug',
      'flutter build ios --release --no-codesign',
      'flutter build web --release',
      'flutter build linux --release',
      'flutter build windows --release',
      'flutter build macos --release',
      'flutter test --platform chrome',
    ]) {
      require(workflow.contains(command), 'Hosted CI lacks `$command`.');
    }
    require(
      workflow.split('working-directory: examples/paved_road_canary').length >=
          7,
      'Hosted builds are not all bound to the UI canary.',
    );

    final privacy = _map(contract['privacy']);
    require(
      privacy.values.every((value) => value == false),
      'UI evidence must not upload screen or semantics content.',
    );
    final goals = _map(
      jsonDecode(_read(root, 'tool/goal_gates.json', failures)),
    );
    final ids = _list(goals['goals'])
        .map((goal) => '${_map(goal)['id']}')
        .toList();
    require(
      ids.contains('V1S-18') &&
          ids.contains('V1-18') &&
          ids.indexOf('V1S-18') < ids.indexOf('V1-18'),
      'V1S-18 must precede V1-18.',
    );

    if (failures.isNotEmpty) {
      throw StateError(failures.join('\n'));
    }
    stdout.writeln(
      'ui-quality-v1 passed: 25 packages, 32 entrypoints, five paired '
      'scenarios, CLI/analyzer parity, canary, and six hosted builds.',
    );
  } on Object catch (error) {
    stderr.writeln('UI quality validation failed: $error');
    exitCode = error is FormatException ? 64 : 1;
  }
}

Directory _root(List<String> arguments) {
  Directory? root;
  for (final argument in arguments) {
    if (argument.startsWith('--root=')) {
      if (root != null) throw const FormatException('Duplicate root.');
      root = Directory(argument.substring('--root='.length)).absolute;
    } else {
      throw FormatException('Unknown argument: $argument');
    }
  }
  return root ?? File.fromUri(Platform.script).parent.parent.absolute;
}

String _read(Directory root, String path, List<String> failures) {
  final file = File('${root.path}/$path');
  if (!file.existsSync()) {
    failures.add('Missing $path.');
    return '{}';
  }
  return file.readAsStringSync();
}

void _mustExist(Directory root, String path, List<String> failures) {
  if (!FileSystemEntity.typeSync('${root.path}/$path').isFile &&
      !FileSystemEntity.typeSync('${root.path}/$path').isDirectory) {
    failures.add('Missing $path.');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('Expected a JSON list.');
  }
  return value;
}

List<String> _strings(Object? value) {
  final list = _list(value);
  if (list.any((item) => item is! String)) {
    throw const FormatException('Expected a JSON string list.');
  }
  return list.cast<String>();
}

bool _same(List<String> left, List<String> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

extension on FileSystemEntityType {
  bool get isFile => this == FileSystemEntityType.file;
  bool get isDirectory => this == FileSystemEntityType.directory;
}
