import 'package:dartitect_objectbox/dartitect_objectbox.dart';

/// Placeholder showing where consumer-generated `openStore` is injected.
OpenObjectBoxStore? get openObjectBoxStoreExample => null;

/// Explains the native ObjectBox ownership contract.
String get objectBoxCapability =>
    'ObjectBox uses a consumer-generated openStore callback.';
