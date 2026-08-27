import 'dart:convert';
import 'dart:io';

import 'package:dartitect_testing/dartitect_testing.dart';

void main() {
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final document = jsonDecode(
    File('${root.path}/tool/testing_matrices.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final ownership = _matrix(document['ownership']);
  final composition = _matrix(document['composition']);
  final errors = <String>[
    ...TestingMatrixAuditor().audit(ownership, composition),
  ];
  if (ownership.rows.length != 25) {
    errors.add('Testing matrices must contain exactly 25 resources.');
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln('Ownership and composition matrices cover 25 resources.');
}

TestingMatrix _matrix(Object? value) {
  final map = value! as Map<String, Object?>;
  return TestingMatrix(
    columns: (map['columns']! as List<Object?>).cast<String>(),
    rows: <TestingMatrixRow>[
      for (final raw in (map['rows']! as List<Object?>))
        _row(raw! as Map<String, Object?>),
    ],
  );
}

TestingMatrixRow _row(Map<String, Object?> raw) => TestingMatrixRow(
  name: raw['name']! as String,
  cells: (raw['cells']! as List<Object?>).cast<String>(),
);
