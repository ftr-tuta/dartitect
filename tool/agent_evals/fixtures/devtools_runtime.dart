import 'package:flutter/material.dart';

void main() => runApp(const RuntimeProbeApp());

final class RuntimeProbeApp extends StatefulWidget {
  const RuntimeProbeApp({super.key});

  @override
  State<RuntimeProbeApp> createState() => _RuntimeProbeAppState();
}

final class _RuntimeProbeAppState extends State<RuntimeProbeApp> {
  var count = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Runtime probe')),
      body: Center(child: Text('Count $count')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Increment runtime counter',
        onPressed: () => setState(() => count += 1),
        child: const Icon(Icons.add),
      ),
    ),
  );
}
