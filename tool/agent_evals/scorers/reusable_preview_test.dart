import 'dart:io';

import 'package:dartitect_flutter_quality_eval_fixture/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preview is dev-safe and widget accepts values and callbacks', (
    tester,
  ) async {
    final source = File('lib/main.dart').readAsStringSync();
    for (final prohibited in <String>[
      'dart:io',
      'File(',
      'HttpClient',
      'package:dio/',
      'MethodChannel',
    ]) {
      expect(source, isNot(contains(prohibited)), reason: prohibited);
    }
    expect(source, contains('@Preview'));
    expect(source, contains('VoidCallback'));

    await tester.pumpWidget(MaterialApp(home: previewTaskCard()));
    expect(find.text('Synthetic task'), findsOneWidget);
    expect(find.byType(TaskCard), findsOneWidget);
  });
}
