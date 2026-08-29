import 'package:dartitect/dartitect.dart';

@DartitectProjectExtension()
/// Representative concrete extension declared only by the consumer project.
final class FixtureClockExtension
    implements DartitectLocalExtension<Stopwatch> {
  @override
  Stopwatch build() => Stopwatch()..start();

  @override
  void dispose(Stopwatch binding) => binding.stop();
}
