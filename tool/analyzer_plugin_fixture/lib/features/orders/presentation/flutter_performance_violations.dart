import 'dart:convert';

import 'package:flutter/widgets.dart';

final class QualityPerformanceWidget extends StatelessWidget {
  const QualityPerformanceWidget({required this.items});

  final List<int> items;

  @override
  Widget build(BuildContext context) {
    final eager = items.map((item) => Text('$item')).toList();
    jsonDecode('[]');
    return Column(
      children: <Widget>[
        ...eager,
        SingleChildScrollView(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => Text('$index'),
          ),
        ),
        ListenableBuilder(
          listenable: Object(),
          builder: (context, child) => const Text('static'),
        ),
        Image.network('https://invalid.example/image.png'),
        ListView(
          children: <Widget>[
            ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => Text('$index'),
            ),
          ],
        ),
      ],
    );
  }
}
