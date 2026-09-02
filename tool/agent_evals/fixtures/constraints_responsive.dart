import 'package:flutter/material.dart';

void main() => runApp(const CatalogApp());

final class CatalogApp extends StatelessWidget {
  const CatalogApp({super.key});

  static final items = List<String>.generate(10000, (index) => 'Item $index');

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items
              .map(
                (item) => SizedBox(
                  width: 240,
                  height: 96,
                  child: Card(child: Center(child: Text(item))),
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
}
