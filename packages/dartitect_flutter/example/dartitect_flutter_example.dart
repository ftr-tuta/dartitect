import 'package:dartitect_flutter/dartitect_flutter.dart';
import 'package:flutter/widgets.dart';

/// Shows owned ViewModel composition with native Flutter listenables.
Widget counterExample() => ViewModelHost<_Counter>.create(
  create: _Counter.new,
  builder: (context, counter) => ListenableBuilder(
    listenable: counter,
    builder: (context, child) => Text('${counter.value}'),
  ),
);

final class _Counter extends ChangeNotifier {
  int value = 0;

  void increment() {
    value += 1;
    notifyListeners();
  }
}
