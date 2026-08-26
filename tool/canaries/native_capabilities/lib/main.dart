import 'package:flutter/material.dart';

void main() => runApp(const _NativeCapabilityHarness());

final class _NativeCapabilityHarness extends StatelessWidget {
  const _NativeCapabilityHarness();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('Dartitect native harness'))),
  );
}
