import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/material.dart';

import 'composition/application_module.wiring.dartitect.g.dart';
import 'features/tasks/presentation/tasks_view.dart';

void main() => runDartitectApplication<ApplicationGraph>(
  create: ApplicationModule.create,
  application: (_) => const MaterialApp(
    title: 'ThinConsumerCanary',
    home: Scaffold(body: Center(child: TasksPage())),
  ),
);
