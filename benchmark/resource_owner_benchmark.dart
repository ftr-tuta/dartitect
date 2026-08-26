import 'package:dartitect/dartitect.dart';

Future<void> main() async {
  for (final count in <int>[1, 10, 100, 1000]) {
    const repetitions = 200;
    final watch = Stopwatch()..start();
    for (var run = 0; run < repetitions; run += 1) {
      final owner = ResourceOwner();
      for (var index = 0; index < count; index += 1) {
        owner.own(index, (_) {});
      }
      await owner.disposeAsync();
    }
    watch.stop();
    final microseconds = watch.elapsedMicroseconds / repetitions;
    // ignore: avoid_print
    print('$count resources: ${microseconds.toStringAsFixed(2)} µs/run');
  }
}
