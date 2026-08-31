import 'package:dartitect_flutter/dartitect_flutter.dart';

import 'composition/application_module.wiring.dartitect.g.dart';
import 'presentation/thin_consumer_app.dart';

void main() => runDartitectApplication<ApplicationGraph>(
  create: ApplicationModule.create,
  application: (graph) => ThinConsumerApp(graph: graph),
);
