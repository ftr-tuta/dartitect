import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import 'composition/application_module.wiring.dartitect.g.dart';

void main() => runDartitectApplication<ApplicationGraph<Never, Never>>(
  create: ApplicationModule.create<Never, Never>,
  application: (_) => const MaterialApp(
    title: 'ThinConsumerCanary',
    home: Scaffold(body: SizedBox.shrink()),
  ),
);
