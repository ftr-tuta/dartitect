/// One named row in a public testing or ownership matrix.
final class TestingMatrixRow {
  /// Creates an immutable row with one value for every matrix column.
  TestingMatrixRow({required this.name, required Iterable<String> cells})
    : cells = List<String>.unmodifiable(cells);

  /// Stable resource or contract name.
  final String name;

  /// Ordered cell values excluding [name].
  final List<String> cells;
}

/// One named matrix with a fixed ordered schema.
final class TestingMatrix {
  /// Creates an immutable matrix.
  TestingMatrix({
    required this.columns,
    required Iterable<TestingMatrixRow> rows,
  }) : rows = List<TestingMatrixRow>.unmodifiable(rows);

  /// Ordered non-name columns.
  final List<String> columns;

  /// Ordered resource rows.
  final List<TestingMatrixRow> rows;
}

/// Detects schema, cell, duplicate, name, and row-order drift across matrices.
final class TestingMatrixAuditor {
  /// Audits [left] and [right] as two views of the same resource inventory.
  List<String> audit(TestingMatrix left, TestingMatrix right) {
    final errors = <String>[
      ..._auditMatrix('left', left),
      ..._auditMatrix('right', right),
    ];
    final leftNames = left.rows.map((row) => row.name).toList(growable: false);
    final rightNames = right.rows
        .map((row) => row.name)
        .toList(growable: false);
    if (leftNames.length != rightNames.length) {
      errors.add('Matrices contain different row counts.');
    }
    final sharedLength = leftNames.length < rightNames.length
        ? leftNames.length
        : rightNames.length;
    for (var index = 0; index < sharedLength; index += 1) {
      if (leftNames[index] != rightNames[index]) {
        errors.add(
          'Row $index differs: ${leftNames[index]} != ${rightNames[index]}.',
        );
      }
    }
    return List<String>.unmodifiable(errors);
  }

  List<String> _auditMatrix(String label, TestingMatrix matrix) {
    final errors = <String>[];
    if (matrix.columns.isEmpty ||
        matrix.columns.any((column) => column.trim().isEmpty)) {
      errors.add('$label matrix has an invalid column schema.');
    }
    if (matrix.columns.toSet().length != matrix.columns.length) {
      errors.add('$label matrix has duplicate columns.');
    }
    final names = <String>{};
    for (final row in matrix.rows) {
      if (row.name.trim().isEmpty || !names.add(row.name)) {
        errors.add('$label matrix has an invalid or duplicate row name.');
      }
      if (row.cells.length != matrix.columns.length) {
        errors.add('$label row ${row.name} has an invalid cell count.');
      } else if (row.cells.any((cell) => cell.trim().isEmpty)) {
        errors.add('$label row ${row.name} has an empty cell.');
      }
    }
    return errors;
  }
}
