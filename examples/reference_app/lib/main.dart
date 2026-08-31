import 'package:dartitect_flutter/dartitect_flutter.dart';

import 'app/reference_app.dart';
import 'composition/application_module.wiring.dartitect.g.dart';

void main() => runDartitectApplication<ApplicationGraph>(
  create: ApplicationModule.create,
  application: (graph) => ReferenceApp(graph: graph),
);
