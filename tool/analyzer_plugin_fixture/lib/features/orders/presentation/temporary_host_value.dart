import 'package:dartitect/dartitect.dart';
import 'package:dartitect_flutter/dartitect_flutter.dart';

Object unsafeHost() =>
    ApplicationHost<Object>.value(value: BootstrapCoordinator<Object>());

Object safeHost(BootstrapCoordinator<Object> coordinator) =>
    ApplicationHost<Object>.value(value: coordinator);
