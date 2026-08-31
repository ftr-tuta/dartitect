import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget uiQualityViolations(BuildContext context) {
  SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  MediaQuery.of(context);
  final platformWidth = defaultTargetPlatform == TargetPlatform.fuchsia
      ? 360.0
      : 840.0;
  return Semantics(
    label: 'fixture group',
    child: RawMaterialButton(
      onPressed: () {
        OrientationBuilder(builder: (context, orientation) => const SizedBox());
        GestureDetector(onTap: () {}, child: const SizedBox());
        SizedBox(
          width: platformWidth,
          child: Container(color: Colors.red),
        );
        IconButton(onPressed: () {}, icon: const Icon(Icons.add));
      },
    ),
  );
}
