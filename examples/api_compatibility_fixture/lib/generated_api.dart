import 'package:dartitect/dartitect.dart';

/// Mirrors the binding shape emitted into managed generated assemblies.
DartitectAssemblyBinding<Stopwatch> generatedBinding() =>
    DartitectAssemblyBinding<Stopwatch>.owned(
      Stopwatch()..start(),
      release: (value) => value.stop(),
      label: 'generated fixture stopwatch',
    );
