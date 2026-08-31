// ignore_for_file: public_member_api_docs

import 'package:flutter/widgets.dart';

import '../all_features.dart';

final class LargeConsumerApp extends StatelessWidget {
  const LargeConsumerApp({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Text('Large graphs: ${largeFeatureNames.length}')),
  );
}
