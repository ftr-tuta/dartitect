import 'package:dartitect_flutter_testing/dartitect_flutter_testing.dart';
import 'package:flutter/material.dart';

void main() {
  testDartitectUiMatrix(
    'application shell',
    buildRoot: (scenario) => MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: scenario.brightness),
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () {},
            child: const Text('Localized consumer action'),
          ),
        ),
      ),
    ),
  );
}
