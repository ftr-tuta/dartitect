import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final acceptedTheme = ThemeData(colorSchemeSeed: Colors.indigo);
final usesCupertinoConvention = defaultTargetPlatform == TargetPlatform.iOS;

Widget acceptedUiQuality(BuildContext context) {
  MediaQuery.sizeOf(context);
  return GestureDetector(
    onTap: () {},
    child: Semantics(
      label: 'Open order',
      button: true,
      child: IconButton(
        tooltip: 'Add order',
        onPressed: () {},
        icon: const Icon(Icons.add),
      ),
    ),
  );
}
