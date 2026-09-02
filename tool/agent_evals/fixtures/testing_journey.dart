import 'package:flutter/material.dart';

void main() => runApp(const CounterJourneyApp());

final class CounterJourneyApp extends StatefulWidget {
  const CounterJourneyApp({super.key});

  @override
  State<CounterJourneyApp> createState() => _CounterJourneyAppState();
}

final class _CounterJourneyAppState extends State<CounterJourneyApp> {
  var count = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Row(
        children: <Widget>[
          const SizedBox(width: 720, child: Text('Counter journey')),
          Text('$count', key: const ValueKey<String>('count')),
          IconButton(
            onPressed: () => setState(() => count += 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ),
  );
}
